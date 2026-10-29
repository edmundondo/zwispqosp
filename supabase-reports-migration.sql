-- qos_period_reports (2026-10-29)
-- Filtered weekly / monthly / quarterly / annual / custom reports across all *ispqosd countries,
-- built entirely inside Postgres so a scheduled Claude run needs just two calls:
--   1. execute_sql: select public.qos_period_report('weekly');
--   2. Gmail send_message with the returned subject / html (body) / csv_base64 (attachment).
-- Not callable by visitors: EXECUTE is revoked from public/anon/authenticated. It runs only through
-- the Supabase MCP / SQL editor (postgres role). Contact details (customers / customer_emails) are
-- only ever COUNTED, never listed.

-- 1. City -> province / region / district lookup (public, well-known administrative facts).
create table if not exists public.city_regions (
  site text not null,
  city text not null,
  province text not null,
  level_label text not null default 'Province',   -- what the country calls this level
  primary key (site, city)
);
alter table public.city_regions enable row level security;
drop policy if exists "Anyone can read the city/province lookup" on public.city_regions;
create policy "Anyone can read the city/province lookup" on public.city_regions for select using (true);

insert into public.city_regions (site, city, province, level_label) values
  ('zw','Harare','Harare Metropolitan','Province'), ('zw','Bulawayo','Bulawayo Metropolitan','Province'),
  ('zw','Chitungwiza','Harare Metropolitan','Province'), ('zw','Mutare','Manicaland','Province'),
  ('zw','Gweru','Midlands','Province'), ('zw','Kwekwe','Midlands','Province'),
  ('zw','Kadoma','Mashonaland West','Province'), ('zw','Masvingo','Masvingo','Province'),
  ('zw','Chinhoyi','Mashonaland West','Province'), ('zw','Norton','Mashonaland West','Province'),
  ('zw','Marondera','Mashonaland East','Province'), ('zw','Ruwa','Mashonaland East','Province'),
  ('zw','Chegutu','Mashonaland West','Province'), ('zw','Zvishavane','Midlands','Province'),
  ('zw','Bindura','Mashonaland Central','Province'), ('zw','Beitbridge','Matabeleland South','Province'),
  ('zw','Redcliff','Midlands','Province'), ('zw','Victoria Falls','Matabeleland North','Province'),
  ('zw','Hwange','Matabeleland North','Province'), ('zw','Rusape','Manicaland','Province'),
  ('bw','Gaborone','South-East','District'), ('bw','Francistown','North-East','District'),
  ('bw','Maun','North-West','District'), ('bw','Kasane','Chobe','District'),
  ('bw','Palapye','Central','District'), ('bw','Serowe','Central','District'),
  ('bw','Molepolole','Kweneng','District'), ('bw','Selebi-Phikwe','Central','District'),
  ('bw','Mahalapye','Central','District'), ('bw','Lobatse','South-East','District'),
  ('bw','Ghanzi','Ghanzi','District'),
  ('za','Johannesburg','Gauteng','Province'), ('za','Cape Town','Western Cape','Province'),
  ('za','Durban','KwaZulu-Natal','Province'), ('za','Pretoria','Gauteng','Province'),
  ('za','Gqeberha','Eastern Cape','Province'), ('za','Bloemfontein','Free State','Province'),
  ('za','East London','Eastern Cape','Province'), ('za','Polokwane','Limpopo','Province'),
  ('za','Mbombela','Mpumalanga','Province'), ('za','Kimberley','Northern Cape','Province'),
  ('zm','Lusaka','Lusaka','Province'), ('zm','Kitwe','Copperbelt','Province'),
  ('zm','Ndola','Copperbelt','Province'), ('zm','Kabwe','Central','Province'),
  ('zm','Chingola','Copperbelt','Province'), ('zm','Mufulira','Copperbelt','Province'),
  ('zm','Livingstone','Southern','Province'), ('zm','Chipata','Eastern','Province'),
  ('zm','Kasama','Northern','Province'), ('zm','Solwezi','North-Western','Province'),
  ('zm','Choma','Southern','Province'),
  ('mz','Maputo','Maputo City','Province'), ('mz','Matola','Maputo Province','Province'),
  ('mz','Beira','Sofala','Province'), ('mz','Nampula','Nampula','Province'),
  ('mz','Chimoio','Manica','Province'), ('mz','Tete','Tete','Province'),
  ('mz','Quelimane','Zambezia','Province'), ('mz','Pemba','Cabo Delgado','Province'),
  ('mw','Lilongwe','Central','Region'), ('mw','Blantyre','Southern','Region'),
  ('mw','Mzuzu','Northern','Region'), ('mw','Zomba','Southern','Region'),
  ('mw','Kasungu','Central','Region'), ('mw','Mangochi','Southern','Region'),
  ('mw','Karonga','Northern','Region'), ('mw','Salima','Central','Region'),
  ('mw','Balaka','Southern','Region'), ('mw','Mzimba','Northern','Region'),
  ('mw','Dedza','Central','Region'), ('mw','Mchinji','Central','Region'),
  ('mw','Nkhotakota','Central','Region'), ('mw','Ntcheu','Central','Region'),
  ('mw','Liwonde','Southern','Region'),
  ('na','Windhoek','Khomas','Region'), ('na','Walvis Bay','Erongo','Region'),
  ('na','Swakopmund','Erongo','Region'), ('na','Oshakati','Oshana','Region'),
  ('na','Rundu','Kavango East','Region'), ('na','Katima Mulilo','Zambezi','Region'),
  ('na','Rehoboth','Hardap','Region'), ('na','Otjiwarongo','Otjozondjupa','Region'),
  ('na','Ondangwa','Oshana','Region'), ('na','Keetmanshoop','ǁKaras','Region'),
  ('na','Lüderitz','ǁKaras','Region'), ('na','Tsumeb','Oshikoto','Region'),
  ('na','Gobabis','Omaheke','Region'), ('na','Grootfontein','Otjozondjupa','Region'),
  ('na','Okahandja','Otjozondjupa','Region'), ('na','Helao Nafidi','Ohangwena','Region'),
  ('na','Mariental','Hardap','Region')
on conflict (site, city) do update set province = excluded.province, level_label = excluded.level_label;

-- 2. Small helpers
create or replace function public.qos_rpt_h(t text) returns text
language sql immutable set search_path = public as $$
  select replace(replace(replace(replace(coalesce(t,''), '&','&amp;'), '<','&lt;'), '>','&gt;'), '"','&quot;')
$$;
create or replace function public.qos_rpt_csv(t text) returns text
language sql immutable set search_path = public as $$
  -- RFC 4180 quoting + spreadsheet formula-injection guard (leading = + - @ get a quote prefix)
  select '"' || replace(case when coalesce(t,'') ~ '^[=+\-@]' then '''' || t else coalesce(t,'') end, '"', '""') || '"'
$$;
create or replace function public.qos_rpt_country(p_site text) returns text
language sql immutable set search_path = public as $$
  select case p_site when 'zw' then 'Zimbabwe' when 'bw' then 'Botswana' when 'za' then 'South Africa'
    when 'zm' then 'Zambia' when 'mz' then 'Mozambique' when 'mw' then 'Malawi' when 'na' then 'Namibia'
    else coalesce(p_site,'?') end
$$;

-- 3. The report
drop function if exists public.qos_period_report(text, timestamptz, text[], text, text, text, timestamptz, timestamptz, text, int);
create or replace function public.qos_period_report(
  p_period   text        default 'weekly',      -- weekly | monthly | quarterly | annual | custom
  p_as_of    timestamptz default now(),         -- the period reported is the last FULL one before this
  p_sites    text[]      default null,          -- e.g. '{zw,bw}'; null = every country
  p_province text        default null,          -- exact province/region/district name
  p_city     text        default null,          -- exact city name
  p_isp      text        default null,          -- case-insensitive substring of the provider name
  p_start    timestamptz default null,          -- custom only
  p_end      timestamptz default null,          -- custom only (exclusive)
  p_tz       text        default 'America/New_York',
  p_detail_limit int     default 25,            -- max detail rows per HTML table (email stays small)
  p_csv_limit    int     default 300            -- max CSV rows in the email (newest first); full export = admin app
) returns jsonb
language plpgsql set search_path = public as $fn$
declare
  v_local timestamp; v_start timestamptz; v_end timestamptz; v_pstart timestamptz;
  v_label text; v_title text; v_filters text; v_total int; v_prev int;
  v_html text := ''; v_part text; v_csv text;
  -- Styling lives in one <style> block (keeps the email small: Gmail clips messages over ~100 KB)
  th text := ''; td text := ''; tdr text := 'class="n"';
  tbl text := '<table cellspacing="0" cellpadding="0">';
  h2 text := '<h2>';
  empty text := '<p class="e">No reports in this period.</p>';
begin
  p_period := lower(coalesce(p_period,'weekly'));
  v_local := p_as_of at time zone p_tz;
  if p_period = 'custom' then
    if p_start is null or p_end is null then raise exception 'custom period needs p_start and p_end'; end if;
    v_start := p_start; v_end := p_end;
  elsif p_period in ('weekly','monthly','quarterly','annual') then
    v_end := date_trunc(case p_period when 'weekly' then 'week' when 'monthly' then 'month'
                                      when 'quarterly' then 'quarter' else 'year' end, v_local) at time zone p_tz;
    v_start := ((v_end at time zone p_tz) - case p_period when 'weekly' then interval '7 days'
               when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months'
               else interval '1 year' end) at time zone p_tz;
  else
    raise exception 'unknown period %, use weekly|monthly|quarterly|annual|custom', p_period;
  end if;
  v_pstart := v_start - (v_end - v_start);

  v_label := case p_period
    when 'weekly' then to_char(v_start at time zone p_tz, 'DD Mon') || ' – ' || to_char((v_end at time zone p_tz) - interval '1 day', 'DD Mon YYYY')
    when 'monthly' then to_char(v_start at time zone p_tz, 'FMMonth YYYY')
    when 'quarterly' then 'Q' || to_char(v_start at time zone p_tz, 'Q YYYY')
    when 'annual' then to_char(v_start at time zone p_tz, 'YYYY')
    else to_char(v_start at time zone p_tz, 'DD Mon YYYY') || ' – ' || to_char(v_end at time zone p_tz, 'DD Mon YYYY') end;
  v_filters := concat_ws(' · ',
    case when p_sites is null then 'All countries' else (select string_agg(qos_rpt_country(s), ', ') from unnest(p_sites) s) end,
    case when p_province is not null then 'Province/region: ' || p_province end,
    case when p_city is not null then 'City: ' || p_city end,
    case when p_isp is not null then 'Provider contains: ' || p_isp end);

  -- Unified, filtered rows (one shape for every table)
  drop table if exists _qr;
  create temp table _qr on commit drop as
  with u as (
    select 'Status report'::text kind, created_at, site, city, area, isp, status::text metric,
           null::numeric stars, null::numeric down, null::numeric up, null::numeric latency, comment detail, device_id from status_reports
    union all select 'Rating', created_at, site, city, area, isp, stars || '★', stars, null, null, null, comment, device_id from qos_reports
    union all select 'Speed test', created_at, site, city, area, isp,
           concat_ws(' · ', nullif(test_method,''), nullif(connection_type,''), nullif(device_type,'')),
           null, download_mbps, upload_mbps, latency_idle_ms, comment, device_id from speed_reports
    union all select 'Switch/signup', created_at, site, city, area, to_isp, 'from ' || coalesce(nullif(from_isp,''),'— (new customer)'),
           null, null, null, null, concat_ws(' · ', nullif(array_to_string(reasons, ', '),''), nullif(comment,'')), device_id from conversions
    union all select 'Referral click', created_at, site, null, null, isp, context, null, null, null, null, null, device_id from referral_clicks
    union all select 'Tester feedback', created_at, site, city, null, null,
           concat_ws(' · ', 'usability ' || usability, 'location ' || location_correct, 'language ' || language_ok),
           null, null, null, null, comment, device_id from tester_feedback
    union all select 'Translation', created_at, site, null, null, null, lang || ' · ' || string_key || ' · ' || coalesce(status,''),
           null, null, null, null, suggested_text, device_id from translations
  )
  select u.*, qos_rpt_country(u.site) country,
         coalesce(cr.province, case when coalesce(u.city,'') in ('','Unknown','unknown') then '—' else 'Unmapped' end) province
  from u left join city_regions cr on cr.site = u.site and cr.city = u.city
  where (p_sites is null or u.site = any(p_sites))
    and (p_province is null or cr.province = p_province)
    and (p_city is null or u.city = p_city)
    and (p_isp is null or u.isp ilike '%' || p_isp || '%')
    and u.created_at >= v_pstart and u.created_at < v_end;

  select count(*) filter (where created_at >= v_start), count(*) filter (where created_at < v_start)
    into v_total, v_prev from _qr;
  delete from _qr where created_at < v_start;   -- previous period only needed for the comparison

  v_title := 'Matokipedo QoS ' || p_period || ' report — ' || v_label;

  -- Header
  v_html := '<style>.q{font-family:Arial,Helvetica,sans-serif;color:#111827;max-width:980px}'
    || '.q table{border-collapse:collapse;width:100%;margin:6px 0 18px 0}'
    || '.q th{background:#1F3A5F;color:#fff;text-align:left;padding:6px 8px;font-size:12px;white-space:nowrap}'
    || '.q td{border-bottom:1px solid #e5e7eb;padding:5px 8px;font-size:12px;vertical-align:top}'
    || '.q td.n{text-align:right;white-space:nowrap}'
    || '.q h2{font-size:16px;color:#1F3A5F;border-left:4px solid #C8962E;padding-left:8px;margin:26px 0 6px 0}'
    || '.q .e{color:#6b7280;font-size:13px;margin:4px 0 18px 0}</style>'
    || '<div class="q">'
    || '<div style="background:#1F3A5F;color:#fff;padding:16px 18px;border-bottom:4px solid #C8962E">'
    || '<div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#E8C26A">Matokipedo · Independent ISP quality tracker</div>'
    || '<div style="font-size:20px;font-weight:bold;margin-top:4px">' || qos_rpt_h(initcap(p_period)) || ' report — ' || qos_rpt_h(v_label) || '</div>'
    || '<div style="font-size:12px;margin-top:6px;color:#dbe4f0">' || qos_rpt_h(v_filters) || ' · '
    || to_char(v_start at time zone p_tz, 'YYYY-MM-DD HH24:MI') || ' to ' || to_char(v_end at time zone p_tz, 'YYYY-MM-DD HH24:MI') || ' (' || qos_rpt_h(p_tz) || ')</div></div>'
    || '<p style="font-size:14px;margin:14px 0">' || '<b>' || v_total || '</b> submissions this period'
    || ' (previous period: ' || v_prev || case when v_prev > 0 then ', ' || case when v_total >= v_prev then '+' else '' end
       || round(100.0 * (v_total - v_prev) / v_prev) || '%' else '' end || '). Newest first throughout. Full rows are in the attached CSV.</p>';

  -- 1. Overview by country
  select string_agg(format('<tr><td %s><b>%s</b></td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td></tr>',
      td, qos_rpt_h(country), tdr, rat, tdr, coalesce(avgst::text,'—'), tdr, st, tdr, dn, tdr, sp,
      tdr, coalesce(avgd::text,'—'), tdr, coalesce(avgu::text,'—'), tdr, sw, tdr, oth, tdr, dev), '' order by tot desc, country)
    into v_part
  from (select country, count(*) tot,
          count(*) filter (where kind='Rating') rat, round(avg(stars),1) avgst,
          count(*) filter (where kind='Status report') st, count(*) filter (where kind='Status report' and metric='down') dn,
          count(*) filter (where kind='Speed test') sp, round(avg(down),1) avgd, round(avg(up),1) avgu,
          count(*) filter (where kind='Switch/signup') sw,
          count(*) filter (where kind in ('Referral click','Tester feedback','Translation')) oth,
          count(distinct device_id) dev
        from _qr group by country) x;
  v_html := v_html || h2 || '1. Overview by country</h2>' || coalesce(tbl || '<tr><th ' || th || '>Country</th><th ' || th || '>Ratings</th><th ' || th || '>Avg ★</th><th ' || th || '>Status reports</th><th ' || th || '>"Down"</th><th ' || th || '>Speed tests</th><th ' || th || '>Avg ↓ Mbps</th><th ' || th || '>Avg ↑ Mbps</th><th ' || th || '>Switches</th><th ' || th || '>Clicks / feedback / translations</th><th ' || th || '>Devices</th></tr>' || v_part || '</table>', empty);

  -- 2. Status reports, newest first
  select string_agg(format('<tr><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s><b style="color:%s">%s</b></td><td %s>%s</td></tr>',
      td, to_char(created_at at time zone p_tz, 'YYYY-MM-DD HH24:MI'), td, qos_rpt_h(country), td, qos_rpt_h(province), td, qos_rpt_h(city),
      td, qos_rpt_h(coalesce(area,'—')), td, qos_rpt_h(isp),
      td, case metric when 'live' then '#15803d' when 'partial' then '#b45309' else '#b91c1c' end, qos_rpt_h(metric), td, qos_rpt_h(detail)), '' order by created_at desc)
    into v_part
  from (select * from _qr where kind='Status report' order by created_at desc limit p_detail_limit) x;
  v_html := v_html || h2 || '2. Status reports (newest first)</h2>' || coalesce(tbl || '<tr><th ' || th || '>When</th><th ' || th || '>Country</th><th ' || th || '>Province</th><th ' || th || '>City</th><th ' || th || '>Area</th><th ' || th || '>Provider</th><th ' || th || '>Status</th><th ' || th || '>Comment</th></tr>' || v_part || '</table>', empty);

  -- 3. Location breakdown: country > province > city > area (most recent activity first)
  select string_agg(format('<tr><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td></tr>',
      td, qos_rpt_h(country), td, qos_rpt_h(province), td, qos_rpt_h(coalesce(city,'—')), td, qos_rpt_h(coalesce(area,'Whole city / not given')),
      tdr, n, tdr, coalesce(avgst::text,'—'), tdr, dn, tdr, coalesce(avgd::text,'—'), td, to_char(latest at time zone p_tz, 'YYYY-MM-DD')), '' order by country, latest desc)
    into v_part
  from (select country, province, city, area, count(*) n, round(avg(stars),1) avgst,
          count(*) filter (where kind='Status report' and metric='down') dn, round(avg(down),1) avgd, max(created_at) latest
        from _qr where city is not null and city <> '' group by country, province, city, area) x;
  v_html := v_html || h2 || '3. By location — country › province › city › area</h2>' || coalesce(tbl || '<tr><th ' || th || '>Country</th><th ' || th || '>Province / region</th><th ' || th || '>City</th><th ' || th || '>Area (sub-city)</th><th ' || th || '>Reports</th><th ' || th || '>Avg ★</th><th ' || th || '>"Down"</th><th ' || th || '>Avg ↓ Mbps</th><th ' || th || '>Latest</th></tr>' || v_part || '</table>', empty);

  -- 4. Speed tests: per provider, then the latest tests
  select string_agg(format('<tr><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td></tr>',
      td, qos_rpt_h(country), td, qos_rpt_h(isp), tdr, n, tdr, avgd, tdr, avgu, tdr, coalesce(lat::text,'—'), tdr, best), '' order by country, avgd desc nulls last)
    into v_part
  from (select country, isp, count(*) n, round(avg(down),1) avgd, round(avg(up),1) avgu, round(avg(latency)) lat, round(max(down),1) best
        from _qr where kind='Speed test' group by country, isp) x;
  v_html := v_html || h2 || '4. Speed tests</h2>' || coalesce(tbl || '<tr><th ' || th || '>Country</th><th ' || th || '>Provider</th><th ' || th || '>Tests</th><th ' || th || '>Avg ↓ Mbps</th><th ' || th || '>Avg ↑ Mbps</th><th ' || th || '>Avg idle latency ms</th><th ' || th || '>Best ↓ Mbps</th></tr>' || v_part || '</table>', empty);
  select string_agg(format('<tr><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td></tr>',
      td, to_char(created_at at time zone p_tz, 'YYYY-MM-DD HH24:MI'), td, qos_rpt_h(country), td, qos_rpt_h(coalesce(city,'—') || coalesce(' › ' || area, '')),
      td, qos_rpt_h(isp), tdr, coalesce(round(down,1)::text,'—'), tdr, coalesce(round(up,1)::text,'—'), tdr, coalesce(round(latency)::text,'—'), td, qos_rpt_h(metric)), '' order by created_at desc)
    into v_part
  from (select * from _qr where kind='Speed test' order by created_at desc limit p_detail_limit) x;
  if v_part is not null then
    v_html := v_html || '<div style="font-size:13px;font-weight:bold;margin-top:4px">Latest tests</div>' || tbl || '<tr><th ' || th || '>When</th><th ' || th || '>Country</th><th ' || th || '>City › area</th><th ' || th || '>Provider</th><th ' || th || '>↓ Mbps</th><th ' || th || '>↑ Mbps</th><th ' || th || '>Latency ms</th><th ' || th || '>Method / connection / device</th></tr>' || v_part || '</table>';
  end if;

  -- 5. Services: provider scorecard per country
  select string_agg(format('<tr><td %s>%s</td><td %s><b>%s</b></td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td></tr>',
      td, qos_rpt_h(country), td, qos_rpt_h(isp), tdr, rat, tdr, coalesce(avgst::text,'—'), tdr, lv, tdr, pa, tdr, dn,
      tdr, coalesce(avgd::text,'—'), tdr, swin, tdr, swout, tdr, clk), '' order by country, (rat + lv + pa + dn + swin + clk) desc, isp)
    into v_part
  from (select country, isp,
          count(*) filter (where kind='Rating') rat, round(avg(stars),1) avgst,
          count(*) filter (where kind='Status report' and metric='live') lv, count(*) filter (where kind='Status report' and metric='partial') pa,
          count(*) filter (where kind='Status report' and metric='down') dn, round(avg(down),1) avgd,
          count(*) filter (where kind='Switch/signup') swin,
          (select count(*) from _qr c where c.kind='Switch/signup' and c.country = q.country and c.metric = 'from ' || q.isp) swout,
          count(*) filter (where kind='Referral click') clk
        from _qr q where isp is not null and isp <> '' group by country, isp) x;
  v_html := v_html || h2 || '5. Services — provider scorecard</h2>' || coalesce(tbl || '<tr><th ' || th || '>Country</th><th ' || th || '>Provider</th><th ' || th || '>Ratings</th><th ' || th || '>Avg ★</th><th ' || th || '>Live</th><th ' || th || '>Partial</th><th ' || th || '>Down</th><th ' || th || '>Avg ↓ Mbps</th><th ' || th || '>Switched to</th><th ' || th || '>Switched from</th><th ' || th || '>Referral clicks</th></tr>' || v_part || '</table>', empty);

  -- 6. Ratings, switches, feedback and translations — newest first
  select string_agg(format('<tr><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td><td %s>%s</td></tr>',
      td, to_char(created_at at time zone p_tz, 'YYYY-MM-DD HH24:MI'), td, qos_rpt_h(kind), td, qos_rpt_h(country),
      td, qos_rpt_h(concat_ws(' › ', nullif(province,'—'), city, area)), td, qos_rpt_h(coalesce(isp,'—')), td, qos_rpt_h(metric), td, qos_rpt_h(detail)), '' order by created_at desc)
    into v_part
  from (select * from _qr where kind not in ('Status report','Speed test') order by created_at desc limit p_detail_limit) x;
  v_html := v_html || h2 || '6. Ratings, switches, clicks, feedback &amp; translations (newest first)</h2>' || coalesce(tbl || '<tr><th ' || th || '>When</th><th ' || th || '>Type</th><th ' || th || '>Country</th><th ' || th || '>Where</th><th ' || th || '>Provider</th><th ' || th || '>Value</th><th ' || th || '>Comment / text</th></tr>' || v_part || '</table>', empty);

  -- 7. Follow-up contacts: counts only
  select string_agg(format('<tr><td %s>%s</td><td %s>%s</td><td %s>%s</td></tr>', td, qos_rpt_h(qos_rpt_country(site)), tdr, ph, tdr, em), '' order by site)
    into v_part
  from (select site, sum(ph) ph, sum(em) em from (
          select site, count(*) ph, 0 em from customers where first_seen >= v_start and first_seen < v_end group by site
          union all select site, 0, count(*) from customer_emails where first_seen >= v_start and first_seen < v_end group by site) c
        where p_sites is null or site = any(p_sites) group by site) x;
  v_html := v_html || h2 || '7. New follow-up contacts (counts only)</h2>' || coalesce(tbl || '<tr><th ' || th || '>Country</th><th ' || th || '>New phone numbers</th><th ' || th || '>New emails</th></tr>' || v_part || '</table>', empty)
    || '<p style="font-size:11px;color:#6b7280;margin-top:24px">Generated by public.qos_period_report() in the shared Supabase project. Detail tables show at most '
    || p_detail_limit || ' rows each; the CSV has up to ' || p_csv_limit || ' rows (this period: ' || v_total || '). Contact details are never included in reports — open the admin app (Raw CSV export) for those. '
    || '"Unmapped" = a city typed by a tester that is not in the city_regions lookup.</p></div>';

  -- CSV (every row, newest first)
  select 'reported_at,type,country,site,province,city,area,provider,value,stars,download_mbps,upload_mbps,latency_ms,comment_or_text,device_id' || E'\r\n'
         || coalesce(string_agg(concat_ws(',',
              qos_rpt_csv(to_char(created_at at time zone p_tz, 'YYYY-MM-DD HH24:MI:SS')), qos_rpt_csv(kind), qos_rpt_csv(country), qos_rpt_csv(site),
              qos_rpt_csv(province), qos_rpt_csv(city), qos_rpt_csv(area), qos_rpt_csv(isp), qos_rpt_csv(metric),
              qos_rpt_csv(stars::text), qos_rpt_csv(down::text), qos_rpt_csv(up::text), qos_rpt_csv(latency::text),
              qos_rpt_csv(detail), qos_rpt_csv(device_id)), E'\r\n' order by created_at desc) || E'\r\n', '')
    into v_csv from (select * from _qr order by created_at desc limit p_csv_limit) c;

  return jsonb_build_object(
    'subject', v_title || ' (' || v_filters || ') — ' || v_total || ' submissions',
    'html', v_html,
    'csv_filename', 'matokipedo-qos-' || p_period || '-' || to_char(v_start at time zone p_tz, 'YYYY-MM-DD') || '.csv',
    'csv_base64', replace(encode(convert_to(v_csv, 'UTF8'), 'base64'), E'\n', ''),
    'total', v_total, 'previous_total', v_prev,
    'window_start', v_start, 'window_end', v_end, 'filters', v_filters,
    'by_kind', (select coalesce(jsonb_object_agg(kind, n), '{}'::jsonb) from (select kind, count(*) n from _qr group by kind) k));
end $fn$;

revoke all on function public.qos_period_report(text, timestamptz, text[], text, text, text, timestamptz, timestamptz, text, int, int) from public, anon, authenticated;
revoke all on function public.qos_rpt_h(text) from public, anon, authenticated;
revoke all on function public.qos_rpt_csv(text) from public, anon, authenticated;
revoke all on function public.qos_rpt_country(text) from public, anon, authenticated;
