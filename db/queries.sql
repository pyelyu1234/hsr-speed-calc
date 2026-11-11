-- 대시보드 SQL Editor에서 실행하는 집계 쿼리 (본인만 볼 수 있음)

-- 1) 많이 쓰는 파티 조합 TOP 20
select string_agg(p->>'name', ' / ' order by p->>'name') as party, count(*) as uses
from public.calc_logs, jsonb_array_elements(party) p
group by id
order by 1;  -- (아래 2번처럼 묶어서 보려면 2번 사용)

-- 2) 파티 조합별 사용 횟수
with t as (
  select id, string_agg(p->>'name', ' / ' order by p->>'name') as party
  from public.calc_logs, jsonb_array_elements(party) p group by id
)
select party, count(*) as uses from t group by party order by uses desc limit 20;

-- 3) 캐릭터별 평균·최고 속도, 평균 성혼
select p->>'name' as character, count(*) as n,
       round(avg((p->>'spd')::numeric),1) as avg_spd,
       max((p->>'spd')::numeric) as max_spd,
       round(avg((p->>'eid')::numeric),2) as avg_eid
from public.calc_logs, jsonb_array_elements(party) p
group by 1 order by n desc;

-- 4) 콘텐츠별 아하 타임 평균 횟수
select mode, count(*) as n, round(avg((results->>'aha')::numeric),2) as avg_aha,
       round(avg((results->>'ahaSpd')::numeric),1) as avg_aha_spd
from public.calc_logs group by mode;

-- 5) 최근 50건
select created_at, mode, party, results from public.calc_logs order by created_at desc limit 50;
