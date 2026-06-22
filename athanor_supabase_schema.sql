-- =============================================================================
-- ATHANOR — Schema database Supabase (PostgreSQL)
-- Esegui questo file nell'SQL Editor del tuo progetto Supabase.
-- Crea: tabelle profiles / blocks / entries, Row Level Security,
-- trigger per profilo automatico e calcolo Opera Alchemica.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. ENUM: fasi alchemiche (3 fasi: nero, bianco, rosso) ed emozioni
-- ---------------------------------------------------------------------------
do $$ begin
  create type alch_phase as enum ('nigredo', 'albedo', 'rubedo');   -- nero, bianco, rosso
exception when duplicate_object then null; end $$;

do $$ begin
  create type emotion as enum
    ('rabbia','paura','tristezza','vergogna','gioia','frustrazione','ansia');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 2. PROFILES — un profilo per utente autenticato (1:1 con auth.users)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text        not null default 'Viandante',
  goal          text        default 'Crescere in consapevolezza',
  daily_time    text        default '15 min',
  streak        int         not null default 0,
  exercises_done int        not null default 0,
  minutes       int         not null default 0,
  onboarded     boolean     not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 3. BLOCKS — i blocchi interiori dell'utente, ognuno in una fase alchemica
-- ---------------------------------------------------------------------------
create table if not exists public.blocks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  phase       alch_phase not null default 'nigredo',
  is_main     boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists blocks_user_idx on public.blocks(user_id);

-- ---------------------------------------------------------------------------
-- 4. ENTRIES — voci del Diario Alchemico
-- ---------------------------------------------------------------------------
create table if not exists public.entries (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  block_id      uuid references public.blocks(id) on delete set null,
  event         text not null,                       -- "Evento: cosa e successo?"
  emotion       emotion not null,
  intensity     int  not null check (intensity between 1 and 10),
  interpretation text default '',                    -- "Cosa mi sta mostrando?"
  transmutation  text default '',                    -- "Quale insegnamento?"
  action         text default '',                    -- "Quale passo faro?"
  keywords       text[] default '{}',                -- parole ricorrenti (analisi schemi)
  created_at     timestamptz not null default now()
);
create index if not exists entries_user_idx on public.entries(user_id);
create index if not exists entries_created_idx on public.entries(user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY — ogni utente vede e modifica SOLO i propri dati
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.blocks   enable row level security;
alter table public.entries  enable row level security;

-- profiles
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

-- blocks
drop policy if exists "blocks_all_own" on public.blocks;
create policy "blocks_all_own" on public.blocks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- entries
drop policy if exists "entries_all_own" on public.entries;
create policy "entries_all_own" on public.entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 6. TRIGGER — crea automaticamente un profilo alla registrazione
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Viandante')
  )
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 7. TRIGGER — aggiorna updated_at automaticamente
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists touch_profiles on public.profiles;
create trigger touch_profiles before update on public.profiles
  for each row execute function public.touch_updated_at();
drop trigger if exists touch_blocks on public.blocks;
create trigger touch_blocks before update on public.blocks
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 8. VIEW — Opera Alchemica: % di trasformazione calcolata lato DB
--    (media fasi blocchi 65% + attivita diario 35%)
-- ---------------------------------------------------------------------------
create or replace view public.opera_progress as
select
  b.user_id,
  round(
    (coalesce(avg(
       case b.phase when 'nigredo' then 0 when 'albedo' then 1 when 'rubedo' then 2 end
     ) / 2.0, 0) * 0.65
     + least((select count(*) from public.entries e where e.user_id = b.user_id)::numeric / 8, 1) * 0.35
    ) * 100
  )::int as opera_percent
from public.blocks b
group by b.user_id;

-- =============================================================================
-- FINE. Dopo l'esecuzione:
--   - Authentication > Providers: abilita Google e Apple
--   - Authentication > URL Configuration: aggiungi l'URL della tua app
-- =============================================================================
