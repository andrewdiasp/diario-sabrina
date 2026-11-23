-- Rode no Supabase: SQL Editor > New query > colar > Run
create table if not exists public.docs (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  path text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, path)
);
alter table public.docs enable row level security;
drop policy if exists "le os proprios" on public.docs;
drop policy if exists "cria os proprios" on public.docs;
drop policy if exists "altera os proprios" on public.docs;
drop policy if exists "apaga os proprios" on public.docs;
create policy "le os proprios" on public.docs for select using (auth.uid() = user_id);
create policy "cria os proprios" on public.docs for insert with check (auth.uid() = user_id);
create policy "altera os proprios" on public.docs for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "apaga os proprios" on public.docs for delete using (auth.uid() = user_id);
