-- add_namibia_site_support (2026-10-20): allow site code 'na' (Namibia) everywhere a site list is hardcoded.
-- Generated edits (not hand-retyped definitions) so nothing else in each constraint/policy/function changes.
do $mig$
declare r record; newdef text; n_con int := 0; n_pol int := 0; n_fn int := 0;
begin
  -- 1. CHECK constraints listing the site codes (7 report tables + customers + customer_emails)
  for r in select conrelid::regclass as tbl, conname, pg_get_constraintdef(oid) as def
           from pg_constraint where connamespace = 'public'::regnamespace and contype = 'c'
             and pg_get_constraintdef(oid) like '%''mw''::text%' and pg_get_constraintdef(oid) not like '%''na''::text%'
  loop
    newdef := replace(r.def, '''mw''::text]', '''mw''::text, ''na''::text]');
    if newdef = r.def then raise exception 'pattern not found in %', r.conname; end if;
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format('alter table %s add constraint %I %s', r.tbl, r.conname, newdef);
    n_con := n_con + 1;
  end loop;
  -- 2. Public-insert RLS policies (WITH CHECK allow-lists)
  for r in select schemaname, tablename, policyname, with_check from pg_policies
           where schemaname = 'public' and with_check like '%''mw''::text%' and with_check not like '%''na''::text%'
  loop
    newdef := replace(r.with_check, '''mw''::text]', '''mw''::text, ''na''::text]');
    if newdef = r.with_check then raise exception 'pattern not found in policy %', r.policyname; end if;
    execute format('alter policy %I on %I.%I with check (%s)', r.policyname, r.schemaname, r.tablename, newdef);
    n_pol := n_pol + 1;
  end loop;
  -- 3. Contact RPC allow-lists and the calling-code map
  for r in select p.oid, p.proname, pg_get_functiondef(p.oid) as def from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.proname in ('upsert_contact_phone','add_contact_email','site_calling_code')
  loop
    if r.proname = 'site_calling_code' then
      newdef := replace(r.def, 'when ''mw'' then ''265''', 'when ''mw'' then ''265'' when ''na'' then ''264''');
    else
      newdef := replace(r.def, '''mw''])', '''mw'',''na''])');
      if newdef = r.def then newdef := replace(r.def, '''mw'']', '''mw'',''na'']'); end if;
    end if;
    if newdef = r.def then raise exception 'pattern not found in function %: %', r.proname, r.def; end if;
    execute newdef;
    n_fn := n_fn + 1;
  end loop;
  if n_con <> 9 or n_pol <> 7 or n_fn <> 3 then
    raise exception 'unexpected counts: constraints %, policies %, functions %', n_con, n_pol, n_fn;
  end if;
  raise notice 'na added: % constraints, % policies, % functions', n_con, n_pol, n_fn;
end $mig$;
notify pgrst, 'reload schema';
