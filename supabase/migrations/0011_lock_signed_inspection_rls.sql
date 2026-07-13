begin;
create or replace function public.can_edit_contract_inspection(target_contract_id uuid,target_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select public.has_org_permission(target_organization_id,'contracts.manage')
    and exists(select 1 from public.contracts c where c.id=target_contract_id and c.organization_id=target_organization_id)
    and not exists(select 1 from public.contract_signatures s where s.contract_id=target_contract_id)
$$;
create or replace function public.can_upload_inspection_file(object_name text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.contracts c where c.organization_id::text=split_part(object_name,'/',1)
    and c.dormitory_id::text=split_part(object_name,'/',2) and split_part(object_name,'/',3)='contracts'
    and c.id::text=split_part(object_name,'/',4) and public.can_edit_contract_inspection(c.id,c.organization_id))
$$;
revoke all on function public.can_edit_contract_inspection(uuid,uuid),public.can_upload_inspection_file(text) from public,anon;
grant execute on function public.can_edit_contract_inspection(uuid,uuid),public.can_upload_inspection_file(text) to authenticated;

drop policy if exists inspection_member_write on public.room_asset_inspections;
drop policy if exists inspection_member_update on public.room_asset_inspections;
drop policy if exists inspection_attachment_member_create on public.room_inspection_attachments;
create policy inspection_member_write on public.room_asset_inspections for insert
  with check(public.can_edit_contract_inspection(contract_id,organization_id));
create policy inspection_member_update on public.room_asset_inspections for update
  using(public.can_edit_contract_inspection(contract_id,organization_id)) with check(public.can_edit_contract_inspection(contract_id,organization_id));
create policy inspection_attachment_member_create on public.room_inspection_attachments for insert
  with check(exists(select 1 from public.room_asset_inspections i where i.id=inspection_id and i.organization_id=organization_id and public.can_edit_contract_inspection(i.contract_id,i.organization_id)));

drop policy if exists room_inspection_object_insert on storage.objects;
create policy room_inspection_object_insert on storage.objects for insert to authenticated
  with check(bucket_id='room-inspections' and public.can_upload_inspection_file(name));
commit;
