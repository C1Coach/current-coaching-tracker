-- Apply once to an existing Current Supabase project; do not rerun full schema.sql.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check(role in ('athlete','coach','parent'));
create table if not exists public.parent_athletes(parent_id uuid not null references public.profiles(id) on delete cascade,athlete_id uuid not null references public.profiles(id) on delete cascade,approved_at timestamptz not null default now(),primary key(parent_id,athlete_id),check(parent_id<>athlete_id));
create or replace function public.is_linked_parent(child_id uuid) returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.parent_athletes where parent_id=(select auth.uid()) and athlete_id=child_id and exists(select 1 from public.profiles where id=(select auth.uid()) and role='parent'))$$;
alter table public.parent_athletes enable row level security;
create policy parent_links_read on public.parent_athletes for select to authenticated using(parent_id=(select auth.uid()) or public.is_coach());
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()) or public.is_coach() or public.is_linked_parent(id));
drop policy if exists logs_read on public.training_sessions;
create policy logs_read on public.training_sessions for select to authenticated using(athlete_id=(select auth.uid()) or public.is_coach() or public.is_linked_parent(athlete_id));
drop policy if exists targets_read on public.training_targets;
create policy targets_read on public.training_targets for select to authenticated using(athlete_id=(select auth.uid()) or public.is_coach() or public.is_linked_parent(athlete_id));
drop policy if exists perms_read on public.exercise_permissions;
create policy perms_read on public.exercise_permissions for select to authenticated using(athlete_id=(select auth.uid()) or public.is_coach() or public.is_linked_parent(athlete_id));
drop policy if exists plans_read on public.session_plans;
create policy plans_read on public.session_plans for select to authenticated using(athlete_id=(select auth.uid()) or public.is_coach() or public.is_linked_parent(athlete_id));
