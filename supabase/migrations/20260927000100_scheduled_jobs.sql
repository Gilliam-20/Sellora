-- Sellora on Supabase — scheduled jobs (were the four onSchedule Cloud
-- Functions, plus the Firestore TTL policy on rate_limits).
--
-- pg_cron fires, pg_net POSTs to the `api` Edge Function's /cron/<job>
-- route, and the function checks the shared x-cron-secret before running
-- the job. The URL and secret come from Vault, which the owner fills in
-- once (TODO.md, "Supabase migration"):
--
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/api', 'sellora_api_url');
--   select vault.create_secret('<same value as the CRON_SECRET function secret>', 'sellora_cron_secret');
--
-- Until both exist every job run fails with a clear error in
-- cron.job_run_details, and nothing else is affected.

-- Callable by pg_cron (which runs as the owner) only.
create or replace function public.invoke_scheduled_job(job text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  api_url text;
  cron_secret text;
begin
  select decrypted_secret into api_url
  from vault.decrypted_secrets where name = 'sellora_api_url';
  select decrypted_secret into cron_secret
  from vault.decrypted_secrets where name = 'sellora_cron_secret';
  if api_url is null or cron_secret is null then
    raise exception 'Vault secrets sellora_api_url and sellora_cron_secret must be set';
  end if;
  return net.http_post(
    url := api_url || '/cron/' || job,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', cron_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 150000);
end;
$$;

revoke execute on function public.invoke_scheduled_job(text) from public, anon, authenticated;

-- Guarded so the migration still applies where the extensions don't exist
-- (the PGlite test run); on Supabase both are available.
do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'pg_cron/pg_net not available: scheduled jobs not created';
    return;
  end if;

  create extension if not exists pg_cron;
  create extension if not exists pg_net with schema extensions;

  -- cron.schedule upserts by name, so re-applying is harmless.
  -- Daily: keeps the cached USD-base FX rates fresh (fx.refreshFxRates).
  perform cron.schedule('sellora-refresh-fx', '0 3 * * *',
    $job$ select public.invoke_scheduled_job('refreshFxRate') $job$);
  -- Daily: mirrors the configured CJ sources into catalog_products.
  perform cron.schedule('sellora-sync-catalog', '30 3 * * *',
    $job$ select public.invoke_scheduled_job('syncCatalog') $job$);
  -- Every 30 minutes: re-drives paid orders whose CJ push failed.
  perform cron.schedule('sellora-retry-fulfilments', '*/30 * * * *',
    $job$ select public.invoke_scheduled_job('retryFailedFulfillments') $job$);
  -- Hourly: pulls tracking for every order still in flight.
  perform cron.schedule('sellora-refresh-tracking', '10 * * * *',
    $job$ select public.invoke_scheduled_job('refreshOrderTracking') $job$);
  -- Hourly: drops spent rate-limit windows (was a Firestore TTL policy).
  perform cron.schedule('sellora-expire-rate-limits', '40 * * * *',
    $job$ delete from public.rate_limits where expire_at < now() $job$);
end;
$$;
