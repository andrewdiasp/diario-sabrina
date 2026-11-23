-- Aurora Fitness — parte social (amigos, feed, curtidas, comentários, receitas, fotos)
-- Rode no Supabase: SQL Editor > New query > colar tudo > Run. Pode rodar de novo sem problema.

-- ---------- tabelas ----------
create table if not exists public.perfil_pub (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  nome text not null default '',
  foto text,
  codigo text unique not null default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)),
  atualizado timestamptz not null default now()
);
create table if not exists public.amizades (
  de uuid not null default auth.uid() references auth.users(id) on delete cascade,
  para uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pendente' check (status in ('pendente','aceita')),
  criado timestamptz not null default now(),
  primary key (de, para),
  check (de <> para)
);
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  tipo text not null default 'livre',
  texto text not null default '',
  dados jsonb not null default '{}',
  fotos text[] not null default '{}',
  criado timestamptz not null default now()
);
create index if not exists posts_criado on public.posts (criado desc);
create table if not exists public.curtidas (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  primary key (post_id, user_id)
);
create table if not exists public.comentarios (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  autor_nome text not null default '',
  texto text not null check (length(texto) between 1 and 1000),
  criado timestamptz not null default now()
);
create table if not exists public.receitas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  dados jsonb not null,
  criado timestamptz not null default now()
);

-- ---------- funções ----------
-- a é amigo de b (ou é a mesma pessoa)
create or replace function public.sao_amigos(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a = b or exists (select 1 from amizades
    where status = 'aceita' and ((de = a and para = b) or (de = b and para = a)));
$$;
-- acha alguém pelo código de amigo (sem expor a lista de usuários)
create or replace function public.buscar_codigo(c text) returns table (user_id uuid, nome text, foto text)
language sql stable security definer set search_path = public as $$
  select user_id, nome, foto from perfil_pub where codigo = upper(trim(c)) limit 1;
$$;
-- pedir amizade: se a outra pessoa já tinha pedido, aceita direto
create or replace function public.pedir_amizade(c text) returns text
language plpgsql security definer set search_path = public as $$
declare alvo uuid; eu uuid := auth.uid();
begin
  if eu is null then return 'sem_login'; end if;
  select user_id into alvo from perfil_pub where codigo = upper(trim(c));
  if alvo is null then return 'nao_achei'; end if;
  if alvo = eu then return 'eu_mesmo'; end if;
  if exists (select 1 from amizades where de = alvo and para = eu) then
    update amizades set status = 'aceita' where de = alvo and para = eu; return 'aceita';
  end if;
  insert into amizades (de, para) values (eu, alvo) on conflict do nothing;
  return 'pedido';
end $$;

-- ---------- segurança (cada um só vê o que deve) ----------
alter table public.perfil_pub enable row level security;
alter table public.amizades enable row level security;
alter table public.posts enable row level security;
alter table public.curtidas enable row level security;
alter table public.comentarios enable row level security;
alter table public.receitas enable row level security;

drop policy if exists pp_ler on public.perfil_pub;
drop policy if exists pp_criar on public.perfil_pub;
drop policy if exists pp_alterar on public.perfil_pub;
create policy pp_ler on public.perfil_pub for select using (
  user_id = auth.uid() or exists (select 1 from public.amizades a
    where (a.de = auth.uid() and a.para = perfil_pub.user_id) or (a.para = auth.uid() and a.de = perfil_pub.user_id)));
create policy pp_criar on public.perfil_pub for insert with check (user_id = auth.uid());
create policy pp_alterar on public.perfil_pub for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists am_ler on public.amizades;
drop policy if exists am_aceitar on public.amizades;
drop policy if exists am_apagar on public.amizades;
create policy am_ler on public.amizades for select using (de = auth.uid() or para = auth.uid());
create policy am_aceitar on public.amizades for update using (para = auth.uid()) with check (para = auth.uid() and status = 'aceita');
create policy am_apagar on public.amizades for delete using (de = auth.uid() or para = auth.uid());

drop policy if exists po_ler on public.posts;
drop policy if exists po_criar on public.posts;
drop policy if exists po_alterar on public.posts;
drop policy if exists po_apagar on public.posts;
create policy po_ler on public.posts for select using (public.sao_amigos(auth.uid(), user_id));
create policy po_criar on public.posts for insert with check (user_id = auth.uid());
create policy po_alterar on public.posts for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy po_apagar on public.posts for delete using (user_id = auth.uid());

drop policy if exists cu_ler on public.curtidas;
drop policy if exists cu_criar on public.curtidas;
drop policy if exists cu_apagar on public.curtidas;
create policy cu_ler on public.curtidas for select using (exists (select 1 from public.posts p where p.id = post_id and public.sao_amigos(auth.uid(), p.user_id)));
create policy cu_criar on public.curtidas for insert with check (user_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id and public.sao_amigos(auth.uid(), p.user_id)));
create policy cu_apagar on public.curtidas for delete using (user_id = auth.uid());

drop policy if exists co_ler on public.comentarios;
drop policy if exists co_criar on public.comentarios;
drop policy if exists co_apagar on public.comentarios;
create policy co_ler on public.comentarios for select using (exists (select 1 from public.posts p where p.id = post_id and public.sao_amigos(auth.uid(), p.user_id)));
create policy co_criar on public.comentarios for insert with check (user_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id and public.sao_amigos(auth.uid(), p.user_id)));
create policy co_apagar on public.comentarios for delete using (user_id = auth.uid() or exists (select 1 from public.posts p where p.id = post_id and p.user_id = auth.uid()));

drop policy if exists re_ler on public.receitas;
drop policy if exists re_criar on public.receitas;
drop policy if exists re_alterar on public.receitas;
drop policy if exists re_apagar on public.receitas;
create policy re_ler on public.receitas for select using (public.sao_amigos(auth.uid(), user_id));
create policy re_criar on public.receitas for insert with check (user_id = auth.uid());
create policy re_alterar on public.receitas for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy re_apagar on public.receitas for delete using (user_id = auth.uid());

grant select, insert, update, delete on public.perfil_pub, public.amizades, public.posts, public.curtidas, public.comentarios, public.receitas to authenticated;
grant execute on function public.sao_amigos(uuid, uuid), public.buscar_codigo(text), public.pedir_amizade(text) to authenticated;

-- ---------- fotos (Storage) ----------
-- pasta de cada pessoa: <id da pessoa>/... ; a subpasta "corpo" só a própria pessoa vê; o resto os amigos veem
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', false, 6291456, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 6291456, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists fotos_ler on storage.objects;
drop policy if exists fotos_criar on storage.objects;
drop policy if exists fotos_alterar on storage.objects;
drop policy if exists fotos_apagar on storage.objects;
create policy fotos_ler on storage.objects for select to authenticated using (
  bucket_id = 'fotos' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or ((storage.foldername(name))[2] <> 'corpo'
        and exists (select 1 from public.amizades a where a.status = 'aceita'
          and ((a.de = auth.uid() and a.para::text = (storage.foldername(name))[1]) or (a.para = auth.uid() and a.de::text = (storage.foldername(name))[1]))))));
create policy fotos_criar on storage.objects for insert to authenticated with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy fotos_alterar on storage.objects for update to authenticated using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy fotos_apagar on storage.objects for delete to authenticated using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);
