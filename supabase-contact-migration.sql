-- contact_rpc_e164_and_email_option (2026-09-23)
-- Why RPCs: the demo sites used supabase-js .upsert() on `customers`, which is
-- INSERT ... ON CONFLICT DO UPDATE. Postgres requires the conflicting row to pass a SELECT policy
-- for that, and `customers` (rightly) has no public SELECT policy — so every contact upsert from
-- the public sites has always failed with 42501. SECURITY DEFINER functions let anonymous visitors
-- write a contact without ever being able to read one back.
alter table public.customers add column if not exists site text;
alter table public.customers drop constraint if exists customers_site_chk;
alter table public.customers add constraint customers_site_chk
  check (site is null or site = any (array['zw','bw','za','zm','mz','mw']));

-- Public direct writes are no longer needed (and the old UPDATE policy let anyone overwrite any row).
drop policy if exists "Public can add a contact record" on public.customers;
drop policy if exists "Public can refresh their own contact record" on public.customers;
drop policy if exists "admins can read customers" on public.customers;
create policy "admins can read customers" on public.customers for select using (public.is_admin());
drop policy if exists "admins can delete customers" on public.customers;
create policy "admins can delete customers" on public.customers for delete using (public.has_write_access(site));

create table if not exists public.customer_emails (
  email text primary key check (char_length(email) <= 254
    and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$' and email = lower(email)),
  site text check (site is null or site = any (array['zw','bw','za','zm','mz','mw'])),
  country text,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
alter table public.customer_emails enable row level security;
drop policy if exists "admins can read customer emails" on public.customer_emails;
create policy "admins can read customer emails" on public.customer_emails for select using (public.is_admin());
drop policy if exists "admins can delete customer emails" on public.customer_emails;
create policy "admins can delete customer emails" on public.customer_emails for delete using (public.has_write_access(site));
revoke all on public.customer_emails from anon;
grant select, delete on public.customer_emails to authenticated;

create or replace function public.site_calling_code(p_site text) returns text
language sql immutable set search_path = public as $$
  select case p_site when 'zw' then '263' when 'bw' then '267' when 'za' then '27'
                     when 'zm' then '260' when 'mz' then '258' when 'mw' then '265' end
$$;

create or replace function public.upsert_contact_phone(p_phone text, p_site text, p_isp text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_phone is null or p_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'invalid_phone' using errcode = '22023';
  end if;
  if p_site is null or not (p_site = any (array['zw','bw','za','zm','mz','mw'])) then
    raise exception 'invalid_site' using errcode = '22023';
  end if;
  insert into public.customers (phone_number, site, country, detected_isp, first_seen, last_seen)
  values (p_phone, p_site, public.site_calling_code(p_site), left(p_isp, 120), now(), now())
  on conflict (phone_number) do update
    set last_seen = now(), site = excluded.site,
        detected_isp = coalesce(excluded.detected_isp, public.customers.detected_isp);
end $$;

create or replace function public.add_contact_email(p_email text, p_site text)
returns void language plpgsql security definer set search_path = public as $$
declare e text := lower(btrim(coalesce(p_email, '')));
begin
  if char_length(e) > 254 or e !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$' then
    raise exception 'invalid_email' using errcode = '22023';
  end if;
  if p_site is null or not (p_site = any (array['zw','bw','za','zm','mz','mw'])) then
    raise exception 'invalid_site' using errcode = '22023';
  end if;
  insert into public.customer_emails (email, site, country)
  values (e, p_site, public.site_calling_code(p_site))
  on conflict (email) do update set last_seen = now(), site = excluded.site;
end $$;

grant execute on function public.upsert_contact_phone(text, text, text) to anon, authenticated;
grant execute on function public.add_contact_email(text, text) to anon, authenticated;
notify pgrst, 'reload schema';
