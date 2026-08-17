-- Polaris Secure — schema para um PROJETO SUPABASE SEPARADO
-- Não executar no projeto RC_FOOD/produção sem revisão e backup.

create extension if not exists pgcrypto;

create type public.app_role as enum ('master', 'admin', 'user');

create table if not exists public.app_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  full_name text not null default '',
  role public.app_role not null default 'user',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint allowed_email_domain check (
    lower(email) like '%@linx.com.br' or lower(email) like '%@totvs.com.br'
  )
);

create table if not exists public.app_screens (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  label text not null,
  description text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.app_roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  label text not null,
  description text not null default '',
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.app_role_screens (
  role_id uuid not null references public.app_roles(id) on delete cascade,
  screen_id uuid not null references public.app_screens(id) on delete cascade,
  primary key (role_id, screen_id)
);

create table if not exists public.app_user_roles (
  user_id uuid not null references public.app_profiles(id) on delete cascade,
  role_id uuid not null references public.app_roles(id) on delete cascade,
  primary key (user_id, role_id)
);

create index if not exists app_profiles_email_idx on public.app_profiles (lower(email));

create or replace function public.is_allowed_email(p_email text)
returns boolean language sql immutable as $$
  select lower(coalesce(p_email, '')) like '%@linx.com.br'
      or lower(coalesce(p_email, '')) like '%@totvs.com.br';
$$;

create or replace function public.has_role(p_role public.app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.app_profiles p
    where p.id = auth.uid() and p.is_active = true and p.role = p_role
  );
$$;

create or replace function public.can_access_screen(p_screen_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_role('master') or exists (
    select 1
    from public.app_user_roles ur
    join public.app_role_screens rs on rs.role_id = ur.role_id
    join public.app_screens s on s.id = rs.screen_id
    join public.app_profiles p on p.id = ur.user_id
    where ur.user_id = auth.uid()
      and p.is_active = true
      and s.key = p_screen_key
  );
$$;

alter table public.app_profiles enable row level security;
alter table public.app_screens enable row level security;
alter table public.app_roles enable row level security;
alter table public.app_role_screens enable row level security;
alter table public.app_user_roles enable row level security;

drop policy if exists profiles_self_read on public.app_profiles;
create policy profiles_self_read on public.app_profiles for select to authenticated
  using (id = auth.uid() or public.has_role('master'));

drop policy if exists profiles_master_write on public.app_profiles;
create policy profiles_master_write on public.app_profiles for all to authenticated
  using (public.has_role('master')) with check (public.is_allowed_email(email));

drop policy if exists screens_authenticated_read on public.app_screens;
create policy screens_authenticated_read on public.app_screens for select to authenticated using (true);

drop policy if exists roles_master_all on public.app_roles;
create policy roles_master_all on public.app_roles for all to authenticated
  using (public.has_role('master')) with check (true);

drop policy if exists role_screens_master_all on public.app_role_screens;
create policy role_screens_master_all on public.app_role_screens for all to authenticated
  using (public.has_role('master')) with check (true);

drop policy if exists user_roles_master_all on public.app_user_roles;
create policy user_roles_master_all on public.app_user_roles for all to authenticated
  using (public.has_role('master')) with check (true);

insert into public.app_screens (key, label, description) values
 ('painel', 'Painel principal', 'Indicadores de atendimento'),
 ('config', 'Configurações', 'Parâmetros do painel'),
 ('reports', 'Inteligência e relatórios', 'Relatórios e exportações'),
 ('monitor', 'Fila e atendimento', 'Monitoramento completo'),
 ('admin_users', 'Usuários', 'Cadastro, edição e remoção de usuários'),
 ('admin_roles', 'Perfis e permissões', 'Perfis e telas autorizadas')
on conflict (key) do update set label = excluded.label, description = excluded.description;

insert into public.app_roles (name, label, description, is_system) values
 ('master', 'Master', 'Acesso total e administração de acessos', true),
 ('user', 'Usuário', 'Perfil básico', true)
on conflict (name) do update set label = excluded.label, description = excluded.description;

insert into public.app_role_screens (role_id, screen_id)
select r.id, s.id from public.app_roles r cross join public.app_screens s
where r.name = 'master' on conflict do nothing;

insert into public.app_role_screens (role_id, screen_id)
select r.id, s.id from public.app_roles r join public.app_screens s on s.key = 'painel'
where r.name = 'user' on conflict do nothing;

-- Após o primeiro login confirmado de cada conta master, execute no projeto de cópia:
-- update public.app_profiles set role = 'master'
-- where lower(email) in ('ruan.nascimento@linx.com.br','ruan.nascimento@totvs.com.br');

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_allowed_email(new.email) then
    raise exception 'Apenas e-mails @linx.com.br e @totvs.com.br são permitidos';
  end if;
  insert into public.app_profiles (id, email, full_name, role)
  values (
    new.id,
    lower(new.email),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    case when lower(new.email) in ('ruan.nascimento@linx.com.br','ruan.nascimento@totvs.com.br')
      then 'master'::public.app_role else 'user'::public.app_role end
  )
  on conflict (id) do update set email = excluded.email;
  insert into public.app_user_roles (user_id, role_id)
  select new.id, r.id from public.app_roles r
  where r.name = case when lower(new.email) in ('ruan.nascimento@linx.com.br','ruan.nascimento@totvs.com.br') then 'master' else 'user' end
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();
