-- v2: 방문당 최종 1건 저장 + 주인님 전용 읽기 권한 (setup.sql 실행 후 1회 실행)
-- ⚠ 아래 '여기에_이메일' 을 Supabase Authentication에 만든 계정 이메일로 바꿔서 실행하세요.

-- 1) 방문 ID 칸 추가
alter table public.calc_logs add column if not exists visit_id text;
create index if not exists calc_logs_visit_idx on public.calc_logs (visit_id);
create index if not exists calc_logs_created_idx on public.calc_logs (created_at desc);

-- 2) 같은 방문의 새 기록이 들어오면 이전 기록을 지움 → 방문당 마지막 1건만 남음
create or replace function public.calc_logs_keep_last() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.visit_id is not null then
    delete from public.calc_logs where visit_id = new.visit_id;
  end if;
  return new;
end $$;
drop trigger if exists calc_logs_keep_last on public.calc_logs;
create trigger calc_logs_keep_last before insert on public.calc_logs
  for each row execute function public.calc_logs_keep_last();

-- 3) 로그인한 주인님 계정만 읽기 가능 (통계 페이지용)
drop policy if exists "owner can read" on public.calc_logs;
create policy "owner can read" on public.calc_logs
  for select to authenticated
  using ((auth.jwt() ->> 'email') = '여기에_이메일');
