-- ============================================================
-- VILA STAY — Setup do banco (Supabase / PostgreSQL)
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique RUN.
-- Pode rodar mais de uma vez sem quebrar (idempotente).
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- TABELAS ----------

create table if not exists properties (
  id uuid primary key default gen_random_uuid(),
  name text not null default '',
  address text not null default '',
  maps_url text,
  description text not null default '',
  check_in_time text not null default '15:00',
  check_out_time text not null default '11:00',
  max_guests int not null default 2,
  wifi_name text not null default '',
  wifi_password text not null default '',
  contact_phone text,
  contact_email text,
  welcome_message text,
  review_url text,
  checkout_notes text,
  ical_url text,
  created_at timestamptz not null default now()
);

create table if not exists reservations (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  guest_name text not null,
  phone text,
  check_in date not null,
  check_out date not null,
  notes text,
  source text not null default 'manual',        -- manual | ical
  ical_uid text,
  token text not null unique default substr(md5(random()::text || clock_timestamp()::text), 1, 16),
  created_at timestamptz not null default now()
);

create table if not exists steps (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  kind text not null check (kind in ('checkin','checkout')),
  ord int not null default 0,
  title text not null,
  description text not null default '',
  requires_confirmation boolean not null default false
);

create table if not exists rules (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  ord int not null default 0,
  title text not null,
  description text not null default ''
);

create table if not exists tips (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  category text not null default 'Geral',
  title text not null,
  description text not null default '',
  maps_url text
);

create table if not exists faq_items (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  ord int not null default 0,
  question text not null,
  answer text not null default ''
);

create table if not exists confirmations (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references reservations(id) on delete cascade,
  step_id uuid not null references steps(id) on delete cascade,
  confirmed_at timestamptz not null default now(),
  unique (reservation_id, step_id)
);

create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references reservations(id) on delete cascade,
  type text not null default 'checkout',
  dismissed boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists message_templates (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  kind text not null,                            -- boas_vindas | vespera | dia_checkout | avaliacao
  body text not null default '',
  unique (property_id, kind)
);

-- ---------- SEGURANÇA (RLS) ----------
-- Admin (usuário logado) pode tudo. Visitante anônimo NÃO acessa
-- nenhuma tabela diretamente — só via funções do portal do hóspede.

alter table properties        enable row level security;
alter table reservations      enable row level security;
alter table steps             enable row level security;
alter table rules             enable row level security;
alter table tips              enable row level security;
alter table faq_items         enable row level security;
alter table confirmations     enable row level security;
alter table notifications     enable row level security;
alter table message_templates enable row level security;

do $$
declare t text;
begin
  foreach t in array array['properties','reservations','steps','rules','tips','faq_items','confirmations','notifications','message_templates'] loop
    execute format('drop policy if exists admin_all on %I', t);
    execute format('create policy admin_all on %I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

revoke all on all tables in schema public from anon;

-- ---------- FUNÇÕES DO PORTAL DO HÓSPEDE ----------
-- Acesso anônimo apenas por token de reserva. Link expira 2 dias após o checkout.

create or replace function public.guest_portal(p_token text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  r reservations%rowtype;
  prop jsonb;
begin
  select * into r from reservations where token = p_token;
  if not found then
    return jsonb_build_object('error', 'not_found');
  end if;
  if (r.check_out + 2) < current_date then
    return jsonb_build_object('error', 'expired');
  end if;

  select to_jsonb(p) - 'ical_url' - 'created_at' into prop
  from properties p where p.id = r.property_id;

  return jsonb_build_object(
    'reservation', jsonb_build_object(
      'guest_name', r.guest_name, 'check_in', r.check_in, 'check_out', r.check_out
    ),
    'property', prop,
    'checkin_steps',  (select coalesce(jsonb_agg(to_jsonb(s) order by s.ord), '[]'::jsonb) from steps s where s.property_id = r.property_id and s.kind = 'checkin'),
    'checkout_steps', (select coalesce(jsonb_agg(to_jsonb(s) order by s.ord), '[]'::jsonb) from steps s where s.property_id = r.property_id and s.kind = 'checkout'),
    'rules',          (select coalesce(jsonb_agg(to_jsonb(x) order by x.ord), '[]'::jsonb) from rules x where x.property_id = r.property_id),
    'tips',           (select coalesce(jsonb_agg(to_jsonb(x) order by x.category, x.title), '[]'::jsonb) from tips x where x.property_id = r.property_id),
    'faq',            (select coalesce(jsonb_agg(to_jsonb(x) order by x.ord), '[]'::jsonb) from faq_items x where x.property_id = r.property_id),
    'confirmed_step_ids', (select coalesce(jsonb_agg(c.step_id), '[]'::jsonb) from confirmations c where c.reservation_id = r.id),
    'checkout_done',  exists (select 1 from notifications n where n.reservation_id = r.id and n.type = 'checkout')
  );
end $$;

create or replace function public.guest_confirm_step(p_token text, p_step_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare r reservations%rowtype;
begin
  select * into r from reservations where token = p_token;
  if not found or (r.check_out + 2) < current_date then
    return jsonb_build_object('ok', false);
  end if;
  insert into confirmations (reservation_id, step_id)
  values (r.id, p_step_id)
  on conflict (reservation_id, step_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.guest_complete_checkout(p_token text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare r reservations%rowtype;
begin
  select * into r from reservations where token = p_token;
  if not found or (r.check_out + 2) < current_date then
    return jsonb_build_object('ok', false);
  end if;
  if not exists (select 1 from notifications n where n.reservation_id = r.id and n.type = 'checkout') then
    insert into notifications (reservation_id, type) values (r.id, 'checkout');
  end if;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.guest_portal(text) from public;
revoke all on function public.guest_confirm_step(text, uuid) from public;
revoke all on function public.guest_complete_checkout(text) from public;
grant execute on function public.guest_portal(text) to anon, authenticated;
grant execute on function public.guest_confirm_step(text, uuid) to anon, authenticated;
grant execute on function public.guest_complete_checkout(text) to anon, authenticated;

-- Fim. Agora crie seu usuário admin em Authentication → Users → Add user.
