-- What supabase/scripts/preflight.js reads to check a real project's
-- rollout: which migrations are applied, whether the Vault secrets and
-- scheduled jobs exist, whether plans are seeded and an admin exists, and
-- whether any seller would be cut off by the standing checks. Service role
-- only. It reports whether each secret *exists*, never its value.
--
-- Every Supabase-only schema (supabase_migrations, vault, cron) is looked up
-- with to_regclass first, so this also applies in the PGlite test run.

create or replace function public.deployment_report()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  applied jsonb := null;
  vault_names jsonb := null;
  cron_jobs jsonb := null;
  cron_failures integer := null;
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select coalesce(jsonb_agg(version order by version), ''[]'') from supabase_migrations.schema_migrations'
      into applied;
  end if;
  if to_regclass('vault.secrets') is not null then
    execute $q$select coalesce(jsonb_agg(name), '[]') from vault.secrets
               where name in ('sellora_api_url', 'sellora_cron_secret')$q$
      into vault_names;
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select coalesce(jsonb_agg(jobname order by jobname), '[]') from cron.job
               where jobname like 'sellora-%'$q$
      into cron_jobs;
  end if;
  if to_regclass('cron.job_run_details') is not null then
    execute $q$select count(*) from cron.job_run_details
               where status = 'failed' and start_time > now() - interval '24 hours'$q$
      into cron_failures;
  end if;

  return jsonb_build_object(
    'appliedMigrations', applied,
    'vaultSecrets', vault_names,
    'extensions', (select coalesce(jsonb_agg(extname order by extname), '[]')
                   from pg_extension where extname in ('pg_cron', 'pg_net')),
    'cronJobs', cron_jobs,
    'cronFailures24h', cron_failures,
    'plans', (select coalesce(jsonb_agg(id order by id), '[]') from public.subscription_plans),
    'storageBucket', to_regclass('storage.buckets') is not null
                     and exists (select 1 from storage.buckets where id = 'store-media'),
    'admins', (select count(*) from public.profiles where role = 'admin'),
    -- The rollout note in TODO.md: an approved seller with no current
    -- subscription has an empty storefront and a refused checkout.
    'activeSellersWithoutSubscription', (
      select count(*) from public.profiles p
      where p.role = 'seller' and p.seller_status = 'active'
        and not exists (
          select 1 from public.subscriptions s
          where s.seller_id = p.uid and s.status = 'active' and s.current_period_end > now())));
end;
$$;

revoke execute on function public.deployment_report() from public, anon, authenticated;
grant execute on function public.deployment_report() to service_role;
