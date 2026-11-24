-- v7: 순위 탭용 분포 집계 (calc_dist) — v5 + 인기 파티 상세 (파티원별 성혼·광추 분포, 돌파+광추 조합은 5명 이상만)
-- 한 사람(브라우저)당 콘텐츠별 최신 1건 · 개별 기록 없이 집계만 · 5명 미만 항목은 숨김 · 본인 기록 제외
-- (setup_v3_rank.sql 의 jnum 함수가 먼저 있어야 함)

create or replace function public.calc_dist(q jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
with b as (
  select distinct on (l.session_id) x.pk, x.vk, l.party, l.results, l.settings
  from public.calc_logs l
  cross join lateral (
    select string_agg(p->>'key', ',' order by p->>'key') as pk,
           string_agg((p->>'key') || ':' || least(6, greatest(0, coalesce(public.jnum(p->'eid'), 0)))::int::text
                      || ':' || least(5, greatest(0, coalesce(public.jnum(p->'lc'), 0)))::int::text, ',' order by p->>'key') as vk
    from jsonb_array_elements(l.party) p) x
  where l.mode = q->>'mode'
    and l.created_at > now() - interval '180 days'
    and l.session_id is distinct from (q->>'session_id')
  order by l.session_id, l.created_at desc
),
p as (   -- 캐릭터 단위로 펼침
  select e->>'key' as ck, public.jnum(e->'spd') as spd,
         coalesce(public.jnum(e->'eid'), 0) as eid, coalesce(public.jnum(e->'lc'), 0) as lc
  from b cross join lateral jsonb_array_elements(b.party) e
  where public.jnum(e->'spd') between 50 and 400
),
chs as (
  select ck, count(*) as n, round(avg(spd), 1) as av,
    round((percentile_cont(0.25) within group (order by spd))::numeric, 1) as p25,
    round((percentile_cont(0.5)  within group (order by spd))::numeric, 1) as p50,
    round((percentile_cont(0.75) within group (order by spd))::numeric, 1) as p75,
    count(*) filter (where lc > 0) as lcn
  from p group by ck having count(*) >= 5
),
bins as (
  select ck, (floor(spd / 5) * 5)::int as bin, count(*) as c
  from p where ck in (select ck from chs) group by 1, 2),
eids as (
  select ck, least(6, greatest(0, eid))::int as e, count(*) as c
  from p where ck in (select ck from chs) group by 1, 2),
parties as (
  select pk, count(*) as n,
    round(avg(public.jnum(results->'aha')) filter (where public.jnum(settings->'cycles') = public.jnum(q->'cycles')), 2) as aha,
    round(avg(public.jnum(results->'ahaSpd')), 1) as ahaspd
  from b group by pk having count(*) >= 5
  order by count(*) desc limit 10
),
pvars as (   -- 인기 파티 안의 돌파 + 전용 광추 조합 (5명 이상만)
  select b.pk, b.vk, count(*) as c,
    round(avg(public.jnum(results->'aha')) filter (where public.jnum(settings->'cycles') = public.jnum(q->'cycles')), 2) as aha
  from b where b.pk in (select pk from parties) group by 1, 2 having count(*) >= 5),
pmem as (    -- 인기 파티 안의 파티원별 성혼 · 광추 (파티 자체가 5명 이상)
  select b.pk, e->>'key' as ck, least(6, greatest(0, coalesce(public.jnum(e->'eid'), 0)))::int as e,
         least(5, greatest(0, coalesce(public.jnum(e->'lc'), 0)))::int as l
  from b cross join lateral jsonb_array_elements(b.party) e where b.pk in (select pk from parties)),
pme as (select pk, ck, e, count(*) as c from pmem group by 1, 2, 3),
pml as (select pk, ck, l, count(*) as c from pmem group by 1, 2, 3),
me as (select string_agg(k, ',' order by k) as pk
       from jsonb_array_elements_text(case when jsonb_typeof(q->'keys') = 'array' then q->'keys' else '[]' end) k),
same as (select b.* from b, me where b.pk = me.pk),
same_aha as (
  select public.jnum(results->'aha')::int as v, count(*) as c from same
  where public.jnum(results->'aha') is not null
    and public.jnum(settings->'cycles') = public.jnum(q->'cycles')
  group by 1),
same_ch as (
  select e->>'key' as ck, round(avg(public.jnum(e->'spd')), 1) as av
  from same cross join lateral jsonb_array_elements(same.party) e
  where public.jnum(e->'spd') between 50 and 400
  group by 1)
select jsonb_build_object(
  'k', 5,
  'n', (select count(*) from b),
  'chars', coalesce((
    select jsonb_agg(jsonb_build_object(
      'key', c.ck, 'n', c.n, 'avg', c.av, 'p25', c.p25, 'p50', c.p50, 'p75', c.p75, 'lc', c.lcn,
      'bins', (select jsonb_object_agg(bins.bin::text, bins.c) from bins where bins.ck = c.ck),
      'eid',  (select jsonb_object_agg(eids.e::text, eids.c) from eids where eids.ck = c.ck)
    ) order by c.n desc) from chs c), '[]'::jsonb),
  'parties', coalesce((
    select jsonb_agg(jsonb_build_object('pk', pt.pk, 'n', pt.n, 'aha', pt.aha, 'ahaSpd', pt.ahaspd,
      'vars', coalesce((select jsonb_agg(jsonb_build_object('vk', v.vk, 'n', v.c, 'aha', v.aha) order by v.c desc)
                        from (select * from pvars where pvars.pk = pt.pk order by c desc limit 5) v), '[]'::jsonb),
      'mem', (select jsonb_object_agg(m.ck, jsonb_build_object(
                 'eid', (select jsonb_object_agg(x.e::text, x.c) from pme x where x.pk = pt.pk and x.ck = m.ck),
                 'lc',  (select jsonb_object_agg(y.l::text, y.c) from pml y where y.pk = pt.pk and y.ck = m.ck)))
              from (select distinct ck from pmem where pmem.pk = pt.pk) m)
    ) order by pt.n desc)
    from parties pt), '[]'::jsonb),
  'mine', jsonb_build_object(
    'n', (select count(*) from same),
    'aha', case when (select coalesce(sum(c), 0) from same_aha) >= 5
                then (select jsonb_object_agg(v::text, c) from same_aha) end,
    'chars', case when (select count(*) from same) >= 5
                  then (select jsonb_agg(jsonb_build_object('key', ck, 'avg', av)) from same_ch) end)
);
$$;

revoke all on function public.calc_dist(jsonb) from public;
grant execute on function public.calc_dist(jsonb) to anon, authenticated;
