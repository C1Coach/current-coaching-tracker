-- CURRENT Coaching Tracker: initial database schema (new/empty Supabase project only)
-- Run ONCE in Supabase Dashboard > SQL Editor, as the project administrator.
-- Do not rerun on an existing populated database.

begin;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  role text not null default 'athlete' check (role in ('athlete','coach','parent')),
  created_at timestamptz not null default now()
);

create function public.new_user_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', ''), 'athlete');
  return new;
end;
$$;
create trigger create_profile after insert on auth.users
for each row execute function public.new_user_profile();

-- Coach-to-athlete assignments are provisioned manually by the administrator.
create table public.coach_athletes (
  coach_id uuid not null references public.profiles(id) on delete cascade,
  athlete_id uuid not null references public.profiles(id) on delete cascade,
  assigned_at timestamptz not null default now(),
  primary key (coach_id, athlete_id),
  check (coach_id <> athlete_id)
);

-- Parent-child links are provisioned manually after verifying entitlement.
create table public.parent_athletes (
  parent_id uuid not null references public.profiles(id) on delete cascade,
  athlete_id uuid not null references public.profiles(id) on delete cascade,
  approved_at timestamptz not null default now(),
  primary key (parent_id, athlete_id),
  check (parent_id <> athlete_id)
);

create function public.is_assigned_coach(child_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.coach_athletes ca
    join public.profiles p on p.id = ca.coach_id and p.role = 'coach'
    where ca.coach_id = (select auth.uid()) and ca.athlete_id = child_id
  );
$$;

create function public.is_linked_parent(child_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.parent_athletes pa
    join public.profiles p on p.id = pa.parent_id and p.role = 'parent'
    where pa.parent_id = (select auth.uid()) and pa.athlete_id = child_id
  );
$$;

create table public.training_sessions (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.profiles(id) on delete cascade,
  date date not null,
  category text not null,
  subtype text,
  location text,
  source text,
  warmup_minutes integer not null default 0 check (warmup_minutes between 0 and 600),
  main_minutes integer not null default 0 check (main_minutes between 0 and 600),
  cooldown_minutes integer not null default 0 check (cooldown_minutes between 0 and 600),
  rpe integer check (rpe between 1 and 10),
  notes text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.training_targets (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.profiles(id) on delete cascade,
  coach_id uuid not null references public.profiles(id),
  start_date date not null,
  end_date date,
  targets jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);

create table public.exercise_permissions (
  athlete_id uuid primary key references public.profiles(id) on delete cascade,
  coach_id uuid not null references public.profiles(id),
  allow_external_load boolean not null default false,
  blocked_exercises text[] not null default '{}',
  sets integer not null default 3 check (sets between 1 and 20),
  reps_min integer not null default 10 check (reps_min between 1 and 100),
  reps_max integer not null default 12 check (reps_max between 1 and 100),
  check (reps_min <= reps_max)
);

create table public.session_plans (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  category text not null,
  location text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Retain the previous values when an athlete corrects a saved session.
create table public.training_session_revisions (
  id bigint generated always as identity primary key,
  session_id uuid not null,
  athlete_id uuid not null,
  changed_by uuid,
  changed_at timestamptz not null default now(),
  previous_record jsonb not null
);

create function public.audit_training_session_update() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.training_session_revisions(session_id, athlete_id, changed_by, previous_record)
  values (old.id, old.athlete_id, auth.uid(), to_jsonb(old));
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end;
$$;
create trigger audit_training_session_update before update on public.training_sessions
for each row execute function public.audit_training_session_update();

-- Ensure users cannot change their own role through the client API.
-- No INSERT/UPDATE/DELETE policy is defined for profiles or assignment tables.
alter table public.profiles enable row level security;
alter table public.coach_athletes enable row level security;
alter table public.parent_athletes enable row level security;
alter table public.training_sessions enable row level security;
alter table public.training_targets enable row level security;
alter table public.exercise_permissions enable row level security;
alter table public.session_plans enable row level security;
alter table public.training_session_revisions enable row level security;

create policy profiles_read on public.profiles for select to authenticated
using (id = (select auth.uid()) or public.is_assigned_coach(id) or public.is_linked_parent(id));

create policy coach_links_read on public.coach_athletes for select to authenticated
using (coach_id = (select auth.uid()));
create policy parent_links_read on public.parent_athletes for select to authenticated
using (parent_id = (select auth.uid()) or public.is_assigned_coach(athlete_id));

create policy logs_read on public.training_sessions for select to authenticated
using (athlete_id = (select auth.uid()) or public.is_assigned_coach(athlete_id) or public.is_linked_parent(athlete_id));
create policy logs_insert on public.training_sessions for insert to authenticated
with check (
  athlete_id = (select auth.uid())
  and exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'athlete')
);
create policy logs_update on public.training_sessions for update to authenticated
using (athlete_id = (select auth.uid()))
with check (athlete_id = (select auth.uid()));

create policy targets_read on public.training_targets for select to authenticated
using (athlete_id = (select auth.uid()) or public.is_assigned_coach(athlete_id) or public.is_linked_parent(athlete_id));
create policy targets_insert on public.training_targets for insert to authenticated
with check (coach_id = (select auth.uid()) and public.is_assigned_coach(athlete_id));
create policy targets_update on public.training_targets for update to authenticated
using (coach_id = (select auth.uid()) and public.is_assigned_coach(athlete_id))
with check (coach_id = (select auth.uid()) and public.is_assigned_coach(athlete_id));

create policy perms_read on public.exercise_permissions for select to authenticated
using (athlete_id = (select auth.uid()) or public.is_assigned_coach(athlete_id) or public.is_linked_parent(athlete_id));
create policy perms_insert on public.exercise_permissions for insert to authenticated
with check (coach_id = (select auth.uid()) and public.is_assigned_coach(athlete_id));
create policy perms_update on public.exercise_permissions for update to authenticated
using (coach_id = (select auth.uid()) and public.is_assigned_coach(athlete_id))
with check (coach_id = (select auth.uid()) and public.is_assigned_coach(athlete_id));

create policy plans_read on public.session_plans for select to authenticated
using (athlete_id = (select auth.uid()) or public.is_assigned_coach(athlete_id) or public.is_linked_parent(athlete_id));
create policy plans_insert on public.session_plans for insert to authenticated
with check (athlete_id = (select auth.uid()));
create policy plans_update on public.session_plans for update to authenticated
using (athlete_id = (select auth.uid())) with check (athlete_id = (select auth.uid()));
create policy plans_delete on public.session_plans for delete to authenticated
using (athlete_id = (select auth.uid()));

-- Revision history: athlete and assigned coach can view; parent cannot.
create policy revisions_read on public.training_session_revisions for select to authenticated
using (athlete_id = (select auth.uid()) or public.is_assigned_coach(athlete_id));

create index on public.training_sessions (athlete_id, date desc);
create index on public.training_targets (athlete_id, start_date desc);
create index on public.training_session_revisions (athlete_id, changed_at desc);

-- Restrict exposed helper functions to authenticated users.
revoke all on function public.is_assigned_coach(uuid) from public, anon;
revoke all on function public.is_linked_parent(uuid) from public, anon;
grant execute on function public.is_assigned_coach(uuid) to authenticated;
grant execute on function public.is_linked_parent(uuid) to authenticated;

commit;

-- AFTER registering the coach's account through the app, run separately in SQL Editor:
-- update public.profiles set role = 'coach'
-- where id = (select id from auth.users where email = 'COACH_EMAIL_HERE');
--
-- AFTER registering fictional athlete accounts, link each to your coach account:
-- insert into public.coach_athletes (coach_id, athlete_id)
-- select c.id, a.id from auth.users c cross join auth.users a
-- where c.email = 'COACH_EMAIL_HERE' and a.email = 'ATHLETE_EMAIL_HERE';
--
-- AFTER registering a fictional parent account, mark it as parent:
-- update public.profiles set role = 'parent'
-- where id = (select id from auth.users where email = 'PARENT_EMAIL_HERE');
-- insert into public.parent_athletes (parent_id, athlete_id)
-- select p.id, a.id from auth.users p cross join auth.users a
-- where p.email = 'PARENT_EMAIL_HERE' and a.email = 'ATHLETE_EMAIL_HERE';
--
-- Real parent links must only be created after verifying parental responsibility.
