begin;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(coalesce(new.email, new.phone, 'ผู้ใช้งาน'), '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_auth_user();

-- Backfill users created before this migration.
insert into public.profiles (id, display_name)
select id, coalesce(nullif(raw_user_meta_data ->> 'display_name', ''), split_part(coalesce(email, phone, 'ผู้ใช้งาน'), '@', 1))
from auth.users
on conflict (id) do nothing;

insert into public.role_permissions(role, permission_id)
select role_name, p.id
from unnest(array['super_admin','owner']::public.app_role[]) role_name
cross join public.permissions p
on conflict do nothing;

insert into public.role_permissions(role, permission_id)
select role_name, p.id
from unnest(array['manager']::public.app_role[]) role_name
cross join public.permissions p
where p.code = any(array['rooms.read','rooms.create','rooms.update','tenants.read','contracts.manage','invoices.manage','payments.approve','receipts.issue'])
on conflict do nothing;

insert into public.role_permissions(role, permission_id)
select role_name, p.id
from unnest(array['staff']::public.app_role[]) role_name
cross join public.permissions p
where p.code = any(array['rooms.read','rooms.update','tenants.read','invoices.manage'])
on conflict do nothing;

insert into public.role_permissions(role, permission_id)
select role_name, p.id
from unnest(array['accountant']::public.app_role[]) role_name
cross join public.permissions p
where p.code = any(array['rooms.read','tenants.read','invoices.manage','payments.approve','receipts.issue','reports.finance'])
on conflict do nothing;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;

alter table public.profiles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
create policy profile_self_read on public.profiles for select using(id = auth.uid());
create policy profile_self_update on public.profiles for update using(id = auth.uid()) with check(id = auth.uid());
create policy permission_authenticated_read on public.permissions for select to authenticated using(true);
create policy role_permission_authenticated_read on public.role_permissions for select to authenticated using(true);

create or replace function public.bootstrap_organization(
  organization_name text,
  dormitory_name text,
  dormitory_code text,
  dormitory_address text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  new_org_id uuid;
begin
  if actor is null then raise exception 'UNAUTHENTICATED'; end if;
  if exists(select 1 from public.organization_members where profile_id = actor) then raise exception 'ALREADY_BOOTSTRAPPED'; end if;
  if length(trim(organization_name)) < 2 or length(trim(dormitory_name)) < 2 or length(trim(dormitory_code)) < 2 or length(trim(dormitory_address)) < 5 then raise exception 'INVALID_INPUT'; end if;

  insert into public.organizations(name) values(trim(organization_name)) returning id into new_org_id;
  insert into public.organization_members(organization_id, profile_id, role) values(new_org_id, actor, 'owner');
  insert into public.dormitories(organization_id, code, name, address) values(new_org_id, upper(trim(dormitory_code)), trim(dormitory_name), trim(dormitory_address));
  insert into public.audit_logs(organization_id, actor_id, action, entity_type, entity_id, after_data)
  values(new_org_id, actor, 'organization.bootstrap', 'organization', new_org_id, jsonb_build_object('name', trim(organization_name)));
  return new_org_id;
end;
$$;
revoke all on function public.bootstrap_organization(text,text,text,text) from public, anon;
grant execute on function public.bootstrap_organization(text,text,text,text) to authenticated;
commit;
