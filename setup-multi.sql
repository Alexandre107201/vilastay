-- ============================================================
-- VILA STAY — Modo multiusuário (você + amigos, dados isolados)
-- Cada usuário só enxerga e mexe nos PRÓPRIOS imóveis.
-- Rode DEPOIS do setup.sql. Pode rodar mais de uma vez.
-- IMPORTANTE: rode ANTES de convidar amigos — os imóveis já
-- existentes serão atribuídos ao usuário mais antigo (você).
-- ============================================================

-- 1. Coluna de dono no imóvel
alter table properties add column if not exists owner_id uuid references auth.users(id) on delete cascade;

-- Imóveis já existentes ficam com o primeiro usuário criado (você)
update properties
set owner_id = (select id from auth.users order by created_at asc limit 1)
where owner_id is null;

alter table properties alter column owner_id set not null;
alter table properties alter column owner_id set default auth.uid();

-- 2. Políticas: cada um no que é seu
drop policy if exists admin_all on properties;
drop policy if exists owner_all on properties;
create policy owner_all on properties
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- Tabelas ligadas ao imóvel
do $$
declare t text;
begin
  foreach t in array array['reservations','steps','rules','tips','faq_items','message_templates'] loop
    execute format('drop policy if exists admin_all on %I', t);
    execute format('drop policy if exists owner_all on %I', t);
    execute format($f$
      create policy owner_all on %I
        for all to authenticated
        using (exists (select 1 from properties p where p.id = %I.property_id and p.owner_id = auth.uid()))
        with check (exists (select 1 from properties p where p.id = %I.property_id and p.owner_id = auth.uid()))
    $f$, t, t, t);
  end loop;
end $$;

-- Tabelas ligadas à reserva
do $$
declare t text;
begin
  foreach t in array array['confirmations','notifications'] loop
    execute format('drop policy if exists admin_all on %I', t);
    execute format('drop policy if exists owner_all on %I', t);
    execute format($f$
      create policy owner_all on %I
        for all to authenticated
        using (exists (
          select 1 from reservations r join properties p on p.id = r.property_id
          where r.id = %I.reservation_id and p.owner_id = auth.uid()))
        with check (exists (
          select 1 from reservations r join properties p on p.id = r.property_id
          where r.id = %I.reservation_id and p.owner_id = auth.uid()))
    $f$, t, t, t);
  end loop;
end $$;

-- 3. O portal do hóspede não muda: as funções por token continuam
--    funcionando para qualquer reserva, de qualquer dono.

-- 4. Para permitir que amigos criem a própria conta na tela de login:
--    Supabase → Authentication → Sign In / Up →
--    desative "Confirm email" (senão o cadastro fica preso esperando e-mail).
