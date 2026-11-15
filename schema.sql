-- STUDYFLOW COMMUNITY: Supabase SQL Editor'da tamamını çalıştır.
-- Auth > Providers > Email: Confirm email ayarını KAPAT.
-- Kullanıcı adı girişinde e-posta yerine dahili @studyflow.invalid adresi kullanılır.
-- Bu nedenle e-posta doğrulaması ve e-posta ile parola kurtarma bu sürümde yoktur.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_]{3,24}$'),
  display_name text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  constraint no_self_request check (requester_id <> addressee_id),
  constraint unique_friend_request unique(requester_id,addressee_id)
);

create table if not exists public.friendships (
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_a,user_b),
  constraint friendship_order check(user_a < user_b)
);

create table if not exists public.study_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  subject text not null default 'Genel',
  seconds integer not null check(seconds > 0 and seconds <= 86400),
  started_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.daily_stats (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,
  seconds bigint not null default 0,
  sessions_count integer not null default 0,
  primary key(user_id,day)
);

create table if not exists public.user_presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_seen_at timestamptz not null default now()
);

-- Auth hesabı açılınca profil satırını otomatik oluştur.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
declare uname text; dname text;
begin
  uname := lower(coalesce(new.raw_user_meta_data->>'username',
                           split_part(new.email,'@',1)));
  dname := coalesce(nullif(new.raw_user_meta_data->>'display_name',''),uname);
  insert into public.profiles(id,username,display_name)
  values(new.id,uname,dname);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_studyflow on auth.users;
create trigger on_auth_user_created_studyflow
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Her çalışma oturumu günlük toplamı otomatik günceller.
create or replace function public.add_daily_study_stats()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.daily_stats(user_id,day,seconds,sessions_count)
  values(new.user_id,(new.started_at at time zone 'Europe/Istanbul')::date,new.seconds,1)
  on conflict(user_id,day) do update
  set seconds=public.daily_stats.seconds + excluded.seconds,
      sessions_count=public.daily_stats.sessions_count + 1;
  return new;
end;
$$;
drop trigger if exists on_study_session_insert on public.study_sessions;
create trigger on_study_session_insert
after insert on public.study_sessions
for each row execute procedure public.add_daily_study_stats();

create or replace function public.are_friends(a uuid,b uuid)
returns boolean language sql stable security definer set search_path=public
as $$
 select exists(
  select 1 from public.friendships f
  where (f.user_a=a and f.user_b=b) or (f.user_a=b and f.user_b=a)
 );
$$;

alter table public.profiles enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.study_sessions enable row level security;
alter table public.daily_stats enable row level security;
alter table public.user_presence enable row level security;

-- Profil kullanıcı adları giriş yapan kullanıcılara aranabilir; diğer alanlar sınırlıdır.
drop policy if exists "profiles readable by authenticated" on public.profiles;
create policy "profiles readable by authenticated" on public.profiles
for select to authenticated using (true);
drop policy if exists "profile owner update" on public.profiles;
create policy "profile owner update" on public.profiles
for update to authenticated using(id=auth.uid()) with check(id=auth.uid());

drop policy if exists "request participants read" on public.friend_requests;
create policy "request participants read" on public.friend_requests
for select to authenticated using(requester_id=auth.uid() or addressee_id=auth.uid());
drop policy if exists "request sender insert" on public.friend_requests;
create policy "request sender insert" on public.friend_requests
for insert to authenticated with check(requester_id=auth.uid() and status='pending');
drop policy if exists "recipient update request" on public.friend_requests;
create policy "recipient update request" on public.friend_requests
for update to authenticated using(addressee_id=auth.uid()) with check(addressee_id=auth.uid());

drop policy if exists "friendship participants read" on public.friendships;
create policy "friendship participants read" on public.friendships
for select to authenticated using(user_a=auth.uid() or user_b=auth.uid());
-- Friendship rows are created only by the trusted trigger below after the recipient accepts.
drop policy if exists "friendship insert from accepted request" on public.friendships;

create or replace function public.create_friendship_after_accept()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if old.status='pending' and new.status='accepted'
     and new.addressee_id = auth.uid() then
    insert into public.friendships(user_a,user_b)
    values(least(new.requester_id,new.addressee_id),
           greatest(new.requester_id,new.addressee_id))
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_friend_request_accepted on public.friend_requests;
create trigger on_friend_request_accepted
after update of status on public.friend_requests
for each row execute procedure public.create_friendship_after_accept();

drop policy if exists "friendship delete own" on public.friendships;
create policy "friendship delete own" on public.friendships
for delete to authenticated using(user_a=auth.uid() or user_b=auth.uid());

drop policy if exists "sessions own all" on public.study_sessions;
create policy "sessions own all" on public.study_sessions
for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

drop policy if exists "daily stats self and friends read" on public.daily_stats;
create policy "daily stats self and friends read" on public.daily_stats
for select to authenticated using(user_id=auth.uid() or public.are_friends(auth.uid(),user_id));

drop policy if exists "presence self or friends read" on public.user_presence;
create policy "presence self or friends read" on public.user_presence
for select to authenticated using(user_id=auth.uid() or public.are_friends(auth.uid(),user_id));
drop policy if exists "presence own insert" on public.user_presence;
create policy "presence own insert" on public.user_presence
for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "presence own update" on public.user_presence;
create policy "presence own update" on public.user_presence
for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

-- Realtime: user_presence değişiklikleri için etkinleştir.
alter publication supabase_realtime add table public.user_presence;

grant usage on schema public to authenticated;
grant select,update on public.profiles to authenticated;
grant select,insert,update on public.friend_requests to authenticated;
grant select,insert,delete on public.friendships to authenticated;
grant select,insert on public.study_sessions to authenticated;
grant select on public.daily_stats to authenticated;
grant select,insert,update on public.user_presence to authenticated;
