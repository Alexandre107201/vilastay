-- ============================================================
-- VILA STAY — Agendamento da sincronização automática
-- Roda a Edge Function "ical-sync" a cada 3 horas, sozinha.
--
-- ANTES DE RODAR, substitua nos 2 lugares indicados:
--   SEU_PROJETO  → o subdomínio do seu projeto (está na Project URL)
--   SUA_CHAVE_ANON → a chave "anon public" (Settings → API)
-- Depois cole tudo no SQL Editor do Supabase e clique RUN.
-- ============================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Remove agendamento anterior, se existir (permite rodar de novo)
do $$
begin
  perform cron.unschedule('vilastay-ical-sync');
exception when others then null;
end $$;

select cron.schedule(
  'vilastay-ical-sync',
  '0 */3 * * *',   -- a cada 3 horas, em ponto
  $$
  select net.http_post(
    url     := 'https://SEU_PROJETO.supabase.co/functions/v1/ical-sync',
    headers := jsonb_build_object(
      'Authorization', 'Bearer SUA_CHAVE_ANON',
      'Content-Type', 'application/json'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- Para conferir se ficou agendado:
--   select jobname, schedule from cron.job;
