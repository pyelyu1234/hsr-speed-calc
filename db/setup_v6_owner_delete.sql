-- v6: 통계 페이지에서 주인님 계정만 기록 삭제 가능 (오염된 기록 정리용)
drop policy if exists "owner can delete" on public.calc_logs;
create policy "owner can delete" on public.calc_logs
  for delete to authenticated
  using ((auth.jwt() ->> 'email') = '여기에_이메일');
