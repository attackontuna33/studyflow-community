-- StudyFlow: plan-linked study sessions and reversible daily totals
-- Run once in Supabase SQL Editor after the study_plans table exists.

alter table public.study_sessions
  add column if not exists plan_id uuid references public.study_plans(id) on delete cascade;

create index if not exists study_sessions_plan_id_idx
  on public.study_sessions(plan_id) where plan_id is not null;

-- Deleting a session (including sessions cascaded from a deleted plan)
-- reverses its contribution to daily_stats.
create or replace function public.remove_daily_study_stats()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare session_day date;
begin
  session_day := (old.started_at at time zone 'Europe/Istanbul')::date;

  update public.daily_stats
  set seconds = greatest(0, seconds - old.seconds),
      sessions_count = greatest(0, sessions_count - 1)
  where user_id = old.user_id and day = session_day;

  delete from public.daily_stats
  where user_id = old.user_id and day = session_day
    and seconds = 0 and sessions_count = 0;

  return old;
end;
$$;

drop trigger if exists on_study_session_delete on public.study_sessions;
create trigger on_study_session_delete
after delete on public.study_sessions
for each row execute procedure public.remove_daily_study_stats();

-- Atomically completes a plan, adding only the time not already recorded
-- against that plan. Safe against repeated taps.
create or replace function public.complete_study_plan(p_plan_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare p public.study_plans%rowtype;
declare logged_seconds bigint;
declare remaining_seconds integer;
begin
  select * into p
  from public.study_plans
  where id = p_plan_id and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'Plan bulunamadı veya erişim iznin yok.';
  end if;

  select coalesce(sum(seconds),0) into logged_seconds
  from public.study_sessions
  where plan_id = p_plan_id and user_id = auth.uid();

  remaining_seconds := greatest(0, p.planned_minutes * 60 - logged_seconds);

  if remaining_seconds > 0 then
    insert into public.study_sessions(user_id, subject, seconds, started_at, plan_id)
    values(auth.uid(), p.subject, remaining_seconds,
           (p.plan_date::timestamp + coalesce(p.start_time, time '09:00')) at time zone 'Europe/Istanbul',
           p_plan_id);
  end if;

  update public.study_plans set completed = true
  where id = p_plan_id and user_id = auth.uid();
end;
$$;

grant execute on function public.complete_study_plan(uuid) to authenticated;

grant select, insert, delete on public.study_sessions to authenticated;
