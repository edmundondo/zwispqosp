-- add_device_id_antispam_and_open_lang_codes (2026-09-23)
-- 1) Every *ispqosd site sends `device_id` (SpamGuard's anonymous per-browser token) on six of the
--    seven report tables, but the column never existed -> PostgREST rejected every insert with 400
--    (PGRST204 "column not found"). Add it (nullable, bounded) to all seven tables.
-- 2) translations.lang CHECK only listed Zimbabwe's language codes, so every translation suggestion
--    from bw/za/zm/mz/mw would fail. Replace the hardcoded list with a format check.
-- 3) The server-side antispam backstop the site comments promise (per-device rate limit) never
--    existed. Add a lenient BEFORE INSERT trigger: max 30 rows / table / device / hour.
do $$
declare t text;
begin
  foreach t in array array['qos_reports','status_reports','speed_reports','conversions',
                           'translations','referral_clicks','tester_feedback'] loop
    execute format('alter table public.%I add column if not exists device_id text', t);
    execute format('alter table public.%I drop constraint if exists %I', t, t||'_device_id_len_chk');
    execute format('alter table public.%I add constraint %I check (device_id is null or char_length(device_id) <= 80)', t, t||'_device_id_len_chk');
    execute format('create index if not exists %I on public.%I (device_id, created_at desc) where device_id is not null', t||'_device_id_idx', t);
  end loop;
end $$;

alter table public.translations drop constraint if exists translations_lang_check;
alter table public.translations add constraint translations_lang_check
  check (lang ~ '^[a-z]{2,4}(-[a-z0-9]{2,8})?$');

create or replace function public.enforce_device_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  if new.device_id is null then
    return new;
  end if;
  execute format(
    'select count(*) from public.%I where device_id = $1 and created_at > now() - interval ''1 hour''',
    tg_table_name) into n using new.device_id;
  if n >= 30 then
    raise exception 'rate_limited: too many submissions from this device, try again later'
      using errcode = 'P0001';
  end if;
  return new;
end $$;

revoke all on function public.enforce_device_rate_limit() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['qos_reports','status_reports','speed_reports','conversions',
                           'translations','referral_clicks','tester_feedback'] loop
    execute format('drop trigger if exists device_rate_limit on public.%I', t);
    execute format('create trigger device_rate_limit before insert on public.%I for each row execute function public.enforce_device_rate_limit()', t);
  end loop;
end $$;

notify pgrst, 'reload schema';
