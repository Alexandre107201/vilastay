-- ============================================================
-- VILA STAY — Fotos no guia (passos + capa do imóvel)
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- ============================================================

alter table steps add column if not exists photo_url text;
alter table properties add column if not exists cover_url text;

-- Bucket público de fotos (as URLs são impossíveis de adivinhar)
insert into storage.buckets (id, name, public)
values ('fotos', 'fotos', true)
on conflict (id) do nothing;

-- Quem está logado pode enviar/gerenciar fotos; leitura é pública (bucket public)
drop policy if exists fotos_insert on storage.objects;
create policy fotos_insert on storage.objects
  for insert to authenticated with check (bucket_id = 'fotos');

drop policy if exists fotos_update on storage.objects;
create policy fotos_update on storage.objects
  for update to authenticated using (bucket_id = 'fotos');

drop policy if exists fotos_delete on storage.objects;
create policy fotos_delete on storage.objects
  for delete to authenticated using (bucket_id = 'fotos');

-- Vídeos nos passos (link do YouTube não listado ou .mp4)
alter table steps add column if not exists video_url text;
