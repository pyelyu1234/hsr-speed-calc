-- 붕괴: 스타레일 속도 계산기 — 익명 사용 통계 테이블
create table if not exists public.calc_logs (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  session_id  text,
  mode        text,
  party       jsonb not null,
  settings    jsonb,
  results     jsonb
);

-- 너무 큰 데이터는 거부 (스팸 방지)
alter table public.calc_logs
  add constraint calc_logs_size check (
    octet_length(coalesce(party::text,'') || coalesce(settings::text,'') || coalesce(results::text,'')) < 8000
  );

-- RLS: 외부(anon)는 '추가'만 가능, 읽기·수정·삭제 불가 → 데이터는 대시보드에서 본인만 열람
alter table public.calc_logs enable row level security;
create policy "anon can insert" on public.calc_logs
  for insert to anon with check (true);
