begin;

create or replace function public.has_org_permission(target_organization_id uuid, permission_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.organization_members m
    join public.role_permissions rp on rp.role = m.role
    join public.permissions p on p.id = rp.permission_id
    where m.organization_id = target_organization_id
      and m.profile_id = auth.uid()
      and m.active
      and p.code = permission_code
  )
$$;

drop policy if exists dormitory_scope on public.dormitories;
create policy dormitory_read on public.dormitories for select using(public.is_member_of(organization_id));
create policy dormitory_create on public.dormitories for insert with check(public.has_org_permission(organization_id, 'settings.manage'));
create policy dormitory_update on public.dormitories for update using(public.has_org_permission(organization_id, 'settings.manage')) with check(public.has_org_permission(organization_id, 'settings.manage'));

drop policy if exists building_scope on public.buildings;
create policy building_read on public.buildings for select using(public.is_member_of(organization_id));
create policy building_create on public.buildings for insert with check(public.has_org_permission(organization_id, 'rooms.create'));
create policy building_update on public.buildings for update using(public.has_org_permission(organization_id, 'rooms.update')) with check(public.has_org_permission(organization_id, 'rooms.update'));

drop policy if exists floor_scope on public.floors;
create policy floor_read on public.floors for select using(public.is_member_of(organization_id));
create policy floor_create on public.floors for insert with check(public.has_org_permission(organization_id, 'rooms.create'));
create policy floor_update on public.floors for update using(public.has_org_permission(organization_id, 'rooms.update')) with check(public.has_org_permission(organization_id, 'rooms.update'));

drop policy if exists room_type_scope on public.room_types;
create policy room_type_read on public.room_types for select using(public.is_member_of(organization_id));
create policy room_type_create on public.room_types for insert with check(public.has_org_permission(organization_id, 'rooms.create'));
create policy room_type_update on public.room_types for update using(public.has_org_permission(organization_id, 'rooms.update')) with check(public.has_org_permission(organization_id, 'rooms.update'));

drop policy if exists room_scope on public.rooms;
create policy room_read on public.rooms for select using(public.is_member_of(organization_id));
create policy room_create on public.rooms for insert with check(public.has_org_permission(organization_id, 'rooms.create'));
create policy room_update on public.rooms for update using(public.has_org_permission(organization_id, 'rooms.update')) with check(public.has_org_permission(organization_id, 'rooms.update'));

create or replace function public.create_building_with_floors(
  target_dormitory_id uuid,
  building_code text,
  building_name text,
  number_of_floors integer
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_org_id uuid;
  new_building_id uuid;
  floor_no integer;
begin
  select organization_id into target_org_id from public.dormitories where id = target_dormitory_id and deleted_at is null;
  if target_org_id is null then raise exception 'DORMITORY_NOT_FOUND'; end if;
  if not public.has_org_permission(target_org_id, 'rooms.create') then raise exception 'FORBIDDEN'; end if;
  if number_of_floors < 1 or number_of_floors > 100 then raise exception 'INVALID_FLOOR_COUNT'; end if;
  if length(trim(building_code)) < 1 or length(trim(building_name)) < 2 then raise exception 'INVALID_INPUT'; end if;

  insert into public.buildings(organization_id, dormitory_id, code, name, floor_count)
  values(target_org_id, target_dormitory_id, upper(trim(building_code)), trim(building_name), number_of_floors)
  returning id into new_building_id;

  for floor_no in 1..number_of_floors loop
    insert into public.floors(organization_id, dormitory_id, building_id, floor_number, name, display_order)
    values(target_org_id, target_dormitory_id, new_building_id, floor_no, 'ชั้น ' || floor_no, floor_no);
  end loop;

  insert into public.audit_logs(organization_id, dormitory_id, actor_id, action, entity_type, entity_id, after_data)
  values(target_org_id, target_dormitory_id, auth.uid(), 'building.create', 'building', new_building_id,
    jsonb_build_object('code', upper(trim(building_code)), 'name', trim(building_name), 'floor_count', number_of_floors));
  return new_building_id;
end;
$$;

revoke all on function public.has_org_permission(uuid,text) from public, anon;
grant execute on function public.has_org_permission(uuid,text) to authenticated;
revoke all on function public.create_building_with_floors(uuid,text,text,integer) from public, anon;
grant execute on function public.create_building_with_floors(uuid,text,text,integer) to authenticated;

commit;
