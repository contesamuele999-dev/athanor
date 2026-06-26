-- =============================================================================
-- ATHANOR — Schema v2 (incrementale)
-- Aggiunge: ruolo admin, incontri, esercizi assegnati (con scadenza),
-- esercizi auto-creati con conferma giornaliera.
-- Esegui DOPO athanor_supabase_schema.sql nell'SQL Editor di Supabase.
-- È idempotente: puoi rieseguirlo senza danni.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. RUOLO sul profilo (admin / viandante)
--    Se hai già la tabella profiles dalla v1, questa riga aggiunge la colonna.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists role text not null default 'viandante';

-- Helper: l'utente corrente è admin?
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- ---------------------------------------------------------------------------
-- 1. MEETINGS — incontri creati dall'admin, visibili a tutti i viandanti
-- ---------------------------------------------------------------------------
create table if not exists public.meetings (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text default '',
  starts_at   timestamptz not null,
  duration    int  default 90,                 -- minuti
  location    text default 'Online',
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists meetings_starts_idx on public.meetings(starts_at);

-- ---------------------------------------------------------------------------
-- 2. ASSIGNED_EXERCISES — esercizi che l'admin assegna, con SCADENZA
--    Alla scadenza l'esercizio va sostituito (lato app viene segnalato).
-- ---------------------------------------------------------------------------
create table if not exists public.assigned_exercises (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,  -- null = per tutti
  title       text not null,
  description text default '',
  level       text default 'Livello 1',
  minutes     int  default 10,
  due_date    date,                            -- scadenza: dopo va cambiato
  completed   boolean not null default false,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists assigned_user_idx on public.assigned_exercises(user_id);
create index if not exists assigned_due_idx  on public.assigned_exercises(due_date);

-- ---------------------------------------------------------------------------
-- 3. HABIT_EXERCISES — esercizi auto-creati dal viandante (ricorrenti)
--    + HABIT_LOGS — conferma giornaliera (checkbox) di avvenuta esecuzione
-- ---------------------------------------------------------------------------
create table if not exists public.habit_exercises (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  title       text not null,
  note        text default '',
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists habit_user_idx on public.habit_exercises(user_id);

create table if not exists public.habit_logs (
  id          uuid primary key default gen_random_uuid(),
  habit_id    uuid not null references public.habit_exercises(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  log_date    date not null default current_date,
  done        boolean not null default true,
  unique (habit_id, log_date)
);
create index if not exists habit_logs_user_idx on public.habit_logs(user_id, log_date);

-- ---------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------------
alter table public.meetings           enable row level security;
alter table public.assigned_exercises enable row level security;
alter table public.habit_exercises    enable row level security;
alter table public.habit_logs         enable row level security;

-- profiles: l'admin può leggere TUTTI i profili (serve per assegnare esercizi)
drop policy if exists "profiles_select_admin" on public.profiles;
create policy "profiles_select_admin" on public.profiles
  for select using (public.is_admin());

-- meetings: tutti gli autenticati leggono; solo admin scrive
drop policy if exists "meetings_read_all" on public.meetings;
create policy "meetings_read_all" on public.meetings
  for select using (auth.role() = 'authenticated');
drop policy if exists "meetings_write_admin" on public.meetings;
create policy "meetings_write_admin" on public.meetings
  for all using (public.is_admin()) with check (public.is_admin());

-- assigned_exercises: il viandante legge i propri (o quelli per tutti);
-- l'admin gestisce tutto
drop policy if exists "assigned_read_own" on public.assigned_exercises;
create policy "assigned_read_own" on public.assigned_exercises
  for select using (user_id = auth.uid() or user_id is null or public.is_admin());
drop policy if exists "assigned_update_own" on public.assigned_exercises;
create policy "assigned_update_own" on public.assigned_exercises
  for update using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());
drop policy if exists "assigned_write_admin" on public.assigned_exercises;
create policy "assigned_write_admin" on public.assigned_exercises
  for all using (public.is_admin()) with check (public.is_admin());

-- habit_exercises + habit_logs: solo il proprietario
drop policy if exists "habit_all_own" on public.habit_exercises;
create policy "habit_all_own" on public.habit_exercises
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "habit_logs_all_own" on public.habit_logs;
create policy "habit_logs_all_own" on public.habit_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- =============================================================================
-- Per nominare un admin (esegui una volta con l'id del tuo utente):
--   update public.profiles set role = 'admin'
--   where id = (select id from auth.users where email = 'TUA@EMAIL.com');
-- =============================================================================
