-- =============================================================================
-- Matokipedo — Privileged Admin Backend migration (for zwispqosp)
-- =============================================================================
-- Run this once in the Supabase SQL editor for the SAME project zwispqosd
-- already talks to (project ref etdxreehedewcctkdvuo, per the SUPABASE_CONFIG
-- baked into zwispqosd/index.html). It is additive and re-runnable:
-- it only adds new tables + admin-only policies, it does not touch the public
-- anon read/insert policies the live site already depends on.
--
-- Design choice: privilege comes from Supabase Auth + Row Level Security, not
-- a hardcoded service_role key baked into a file. Even though zwispqosp is a
-- private repo, an admin dashboard that only needs the same public anon key
-- plus a real login is safer (no single string that, if the repo is ever
-- made public or forked by mistake, hands over full database control) and
-- is the standard Supabase pattern for "one project, two front-ends with
-- different privilege levels."
-- =============================================================================

-- 1. Who is an admin -----------------------------------------------------
create table if not exists admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);

alter table admins enable row level security;

drop policy if exists "admins can read the admins table" on admins;
create policy "admins can read the admins table"
  on admins for select
  using (auth.uid() = user_id);

-- Helper used by every admin policy below. security definer so it can read
-- the admins table even from a policy on a different table.
create or replace function is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (select 1 from admins where user_id = auth.uid());
$$;

-- After running this file: Authentication → Users → Add user (your email +
-- a password), copy the new user's UUID, then run once:
--   insert into admins (user_id, email) values ('<uuid-here>', 'you@example.com');

-- 2. ISP licensing / CRM (operationalizes the "reach out to discuss a
--    licensed subscription" call-to-action already printed on the free
--    teaser benchmark report in zwispqosd) --------------------------------
create table if not exists provider_licenses (
  id bigint generated always as identity primary key,
  site text not null,                 -- "zw" / "bw" / "za" ... matches SITE_ID
  isp text not null,
  status text not null default 'prospect'
    check (status in ('prospect','contacted','trial','active','lapsed','declined')),
  contact_name text,
  contact_email text,
  monthly_fee_usd numeric(10,2),
  started_at date,
  renews_at date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site, isp)
);

alter table provider_licenses enable row level security;

drop policy if exists "admins full access to provider_licenses" on provider_licenses;
create policy "admins full access to provider_licenses"
  on provider_licenses for all
  using (is_admin())
  with check (is_admin());

-- 3. Admin-only elevated access to the existing crowdsourced tables -------
-- These tables already have public policies (anon can insert, and the site
-- reads its own recent rows back for the aggregates it shows). This adds a
-- SEPARATE admin policy alongside those — it does not replace or narrow the
-- existing public ones — so admins can additionally see the full history
-- (not capped at the site's client-side .limit(1000)) and delete spam/abuse.
do $$
declare
  t text;
begin
  foreach t in array array['qos_reports','status_reports','speed_reports',
                            'conversions','translations','referral_clicks',
                            'tester_feedback']
  loop
    execute format('alter table %I enable row level security;', t);

    -- Policy names are identifiers, not string literals — %I, not %L.
    execute format('drop policy if exists %I on %I;',
                    'admins full read on '||t, t);
    execute format(
      'create policy %I on %I for select using (is_admin());',
      'admins full read on '||t, t);

    execute format('drop policy if exists %I on %I;',
                    'admins can delete on '||t, t);
    execute format(
      'create policy %I on %I for delete using (is_admin());',
      'admins can delete on '||t, t);

    execute format('drop policy if exists %I on %I;',
                    'admins can update on '||t, t);
    execute format(
      'create policy %I on %I for update using (is_admin()) with check (is_admin());',
      'admins can update on '||t, t);
  end loop;
end $$;

-- 4. Translations: allow admins to flip status without going through the
--    app's own "2 endorsements" auto-approve logic (covered by the update
--    policy above, called out here since it's the main moderation workflow:
--    update translations set status = 'approved' where id = ...;) ---------

-- =============================================================================
-- Verify: after inserting yourself into `admins`, in the SQL editor run
--   select * from provider_licenses;                -- should return 0 rows, no error
--   select count(*) from qos_reports;                -- should work now even
--                                                     -- though anon could only
--                                                     -- ever see/insert its own
--                                                     -- recent slice client-side
-- =============================================================================
