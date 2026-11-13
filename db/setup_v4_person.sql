-- v4: 한 사람(브라우저)당 콘텐츠별 최신 1건 기준 순위 (calc_rank_v2)
-- 예전 기록은 지우지 않고 보관 · 집계만 사람당 최신 1건
-- 테스트 사이트(beta)가 먼저 사용하고, 본 사이트는 확인 후 전환
-- (setup_v3_rank.sql 의 jnum 함수가 먼저 있어야 함)

create or replace function public.calc_rank_v2(q jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
with b as (   -- 같은 콘텐츠 · 최근 180일 · 한 사람(브라우저)당 최신 1건 · 본인 제외
  select distinct on (l.session_id) x.pk, l.party, l.results, l.settings
  from public.calc_logs l
  cross join lateral (
    select string_agg(p->>'key', ',' order by p->>'key') as pk
    from jsonb_array_elements(l.party) p) x
  where l.mode = q->>'mode'
    and l.created_at > now() - interval '180 days'
    and l.session_id is distinct from (q->>'session_id')
  order by l.session_id, l.created_at desc
),
me as (select string_agg(k, ',' order by k) as pk from jsonb_array_elements_text(case when jsonb_typeof(q->'keys') = 'array' then q->'keys' else '[]' end) k),
same as (select b.* from b, me where b.pk = me.pk),
same_aha as (
  select public.jnum(results->'aha') as v from same
  where public.jnum(results->'aha') is not null
    and public.jnum(settings->'cycles') = public.jnum(q->'cycles')),
same_spd as (
  select public.jnum(results->'ahaSpd') as v from same
  where public.jnum(results->'ahaSpd') is not null),
ch as (
  select c->>'key' as ck, public.jnum(c->'spd') as my
  from jsonb_array_elements(case when jsonb_typeof(q->'chars') = 'array' then q->'chars' else '[]' end) c
  where public.jnum(c->'spd') is not null),
chs as (
  select ch.ck, count(*) as n, avg(public.jnum(p->'spd')) as av,
         count(*) filter (where public.jnum(p->'spd') < ch.my) as below,
         count(*) filter (where public.jnum(p->'spd') = ch.my) as eq
  from ch
  join b on true
  cross join lateral jsonb_array_elements(b.party) p
  where p->>'key' = ch.ck
    and public.jnum(p->'spd') between 1 and 1000
  group by ch.ck)
select jsonb_build_object(
  'k', 5,
  'n_mode', (select count(*) from b),
  'party_n', (select count(*) from same),
  'aha', (select case when count(*) >= 5 then jsonb_build_object(
            'n', count(*), 'avg', round(avg(v), 2),
            'below', count(*) filter (where v < public.jnum(q->'aha')),
            'eq', count(*) filter (where v = public.jnum(q->'aha'))) end
          from same_aha),
  'ahaSpd', (select case when count(*) >= 5 then jsonb_build_object(
            'n', count(*), 'avg', round(avg(v), 1),
            'below', count(*) filter (where v < public.jnum(q->'ahaSpd')),
            'eq', count(*) filter (where v = public.jnum(q->'ahaSpd'))) end
          from same_spd),
  'chars', coalesce((
    select jsonb_agg(jsonb_build_object('key', ck, 'n', n, 'avg', round(av, 1), 'below', below, 'eq', eq))
    from chs where n >= 5), '[]'::jsonb)
);
$$;

revoke all on function public.calc_rank_v2(jsonb) from public;
grant execute on function public.calc_rank_v2(jsonb) to anon, authenticated;
