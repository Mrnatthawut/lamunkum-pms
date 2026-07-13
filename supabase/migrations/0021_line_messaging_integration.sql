begin;

insert into public.permissions(code,description) values('line.read','ดูสถานะและประวัติ LINE'),('line.send','ส่งข้อความ LINE'),('line.manage','จัดการการเชื่อมต่อ LINE') on conflict do nothing;
insert into public.role_permissions(role,permission_id) select role_name,p.id from unnest(array['super_admin','owner','manager']::public.app_role[]) role_name cross join public.permissions p where p.code like 'line.%' on conflict do nothing;
insert into public.role_permissions(role,permission_id) select role_name,p.id from unnest(array['staff','accountant']::public.app_role[]) role_name cross join public.permissions p where p.code in ('line.read','line.send') on conflict do nothing;

create table public.line_accounts (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,tenant_id uuid not null references public.tenants(id) on delete restrict,
  line_user_id text not null unique,display_name text,picture_url text,status text not null default 'connected' check(status in ('connected','disconnected','blocked')),
  linked_at timestamptz not null default now(),disconnected_at timestamptz,last_interaction_at timestamptz,
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),version integer not null default 1,unique(tenant_id)
);
create index line_accounts_dormitory_status_idx on public.line_accounts(dormitory_id,status);

create table public.line_link_tokens (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,tenant_id uuid not null references public.tenants(id) on delete restrict,
  token_hash text not null unique,expires_at timestamptz not null,used_at timestamptz,created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),check(token_hash ~ '^[a-f0-9]{64}$')
);
create unique index one_active_line_link_token on public.line_link_tokens(tenant_id) where used_at is null;
create table public.line_link_attempts(attempt_key text primary key,window_started_at timestamptz not null default now(),attempt_count integer not null default 1 check(attempt_count>0),updated_at timestamptz not null default now());

alter table public.line_webhook_events add column if not exists dormitory_id uuid references public.dormitories(id) on delete restrict;
alter table public.line_webhook_events add column if not exists source_line_user_id text;
alter table public.line_webhook_events add column if not exists message_type text;
alter table public.line_webhook_events add column if not exists command_name text;
alter table public.line_webhook_events add column if not exists event_timestamp timestamptz;
alter table public.line_webhook_events add column if not exists processing_status text not null default 'received' check(processing_status in ('received','processed','ignored','failed'));
create index if not exists line_webhook_status_idx on public.line_webhook_events(processing_status,received_at);

alter table public.line_message_logs add column if not exists channel text not null default 'push' check(channel in ('push','reply'));
alter table public.line_message_logs add column if not exists payload_summary jsonb not null default '{}'::jsonb;
alter table public.line_message_logs add column if not exists provider_request_id text;
alter table public.line_message_logs add column if not exists next_retry_at timestamptz;
alter table public.line_message_logs add column if not exists permanent_error boolean not null default false;

alter table public.line_accounts enable row level security;alter table public.line_link_tokens enable row level security;alter table public.line_webhook_events enable row level security;
create policy line_account_member_read on public.line_accounts for select using(public.has_org_permission(organization_id,'line.read') or public.is_tenant_of(tenant_id));
create policy line_token_manager_read on public.line_link_tokens for select using(public.has_org_permission(organization_id,'line.manage'));
create policy line_webhook_manager_read on public.line_webhook_events for select using(organization_id is not null and public.has_org_permission(organization_id,'line.read'));
drop policy if exists line_message_member_read on public.line_message_logs;
create policy line_message_member_read on public.line_message_logs for select using(public.has_org_permission(organization_id,'line.read') or (tenant_id is not null and public.is_tenant_of(tenant_id)));
grant select on public.line_accounts,public.line_link_tokens,public.line_webhook_events,public.line_message_logs to authenticated;

create or replace function public.create_line_link_token(target_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.tenants%rowtype;raw_token text;new_id uuid;expiry timestamptz:=now()+interval '15 minutes';
begin select * into t from public.tenants where id=target_tenant_id and deleted_at is null;if t.id is null then raise exception 'TENANT_NOT_FOUND';end if;
  if not public.has_org_permission(t.organization_id,'line.manage') then raise exception 'FORBIDDEN';end if;
  update public.line_link_tokens set used_at=now() where tenant_id=t.id and used_at is null;
  raw_token:=encode(extensions.gen_random_bytes(16),'hex');
  insert into public.line_link_tokens(organization_id,dormitory_id,tenant_id,token_hash,expires_at,created_by) values(t.organization_id,t.dormitory_id,t.id,encode(extensions.digest(raw_token,'sha256'),'hex'),expiry,auth.uid()) returning id into new_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data) values(t.organization_id,t.dormitory_id,auth.uid(),'line.link_token_create','line_link_token',new_id,jsonb_build_object('tenant_id',t.id,'expires_at',expiry));
  return jsonb_build_object('token',raw_token,'expires_at',expiry);
end $$;

create or replace function public.consume_line_link_token(target_token text,target_line_user_id text,target_display_name text,target_attempt_key text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare link public.line_link_tokens%rowtype;account_id uuid;attempts integer;
begin
  insert into public.line_link_attempts(attempt_key) values(target_attempt_key) on conflict(attempt_key) do update set attempt_count=case when public.line_link_attempts.window_started_at<now()-interval '15 minutes' then 1 else public.line_link_attempts.attempt_count+1 end,window_started_at=case when public.line_link_attempts.window_started_at<now()-interval '15 minutes' then now() else public.line_link_attempts.window_started_at end,updated_at=now() returning attempt_count into attempts;
  if attempts>10 then raise exception 'RATE_LIMITED';end if;
  if target_token !~ '^[a-f0-9]{32}$' or target_line_user_id !~ '^U[A-Za-z0-9_-]{8,64}$' then raise exception 'INVALID_LINK_REQUEST';end if;
  select * into link from public.line_link_tokens where token_hash=encode(extensions.digest(target_token,'sha256'),'hex') for update;
  if link.id is null or link.used_at is not null or link.expires_at<now() then raise exception 'LINK_TOKEN_INVALID';end if;
  insert into public.line_accounts(organization_id,dormitory_id,tenant_id,line_user_id,display_name,status,linked_at,disconnected_at)
  values(link.organization_id,link.dormitory_id,link.tenant_id,target_line_user_id,nullif(left(trim(target_display_name),100),''),'connected',now(),null)
  on conflict(tenant_id) do update set line_user_id=excluded.line_user_id,display_name=excluded.display_name,status='connected',linked_at=now(),disconnected_at=null,updated_at=now(),version=public.line_accounts.version+1 returning id into account_id;
  update public.line_link_tokens set used_at=now() where id=link.id;delete from public.line_link_attempts where attempt_key=target_attempt_key;
  update public.tenants set line_user_id=target_line_user_id,updated_at=now(),version=version+1 where id=link.tenant_id;
  insert into public.audit_logs(organization_id,dormitory_id,action,entity_type,entity_id,after_data) values(link.organization_id,link.dormitory_id,'line.account_link','line_account',account_id,jsonb_build_object('tenant_id',link.tenant_id,'linked_at',now()));
  return jsonb_build_object('account_id',account_id,'tenant_id',link.tenant_id,'dormitory_id',link.dormitory_id);
end $$;

create or replace function public.disconnect_line_account(target_tenant_id uuid)
returns text language plpgsql security definer set search_path='' as $$
declare a public.line_accounts%rowtype;
begin select * into a from public.line_accounts where tenant_id=target_tenant_id for update;if a.id is null then raise exception 'LINE_ACCOUNT_NOT_FOUND';end if;
  if not public.has_org_permission(a.organization_id,'line.manage') and not public.is_tenant_of(a.tenant_id) then raise exception 'FORBIDDEN';end if;
  update public.line_accounts set status='disconnected',disconnected_at=now(),updated_at=now(),version=version+1 where id=a.id;update public.tenants set line_user_id=null,updated_at=now(),version=version+1 where id=a.tenant_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data) values(a.organization_id,a.dormitory_id,auth.uid(),'line.account_disconnect','line_account',a.id,jsonb_build_object('tenant_id',a.tenant_id));return a.line_user_id;end $$;

revoke all on function public.create_line_link_token(uuid),public.disconnect_line_account(uuid) from public,anon;
grant execute on function public.create_line_link_token(uuid),public.disconnect_line_account(uuid) to authenticated;
revoke all on function public.consume_line_link_token(text,text,text,text) from public,anon,authenticated;
grant execute on function public.consume_line_link_token(text,text,text,text) to service_role;
commit;
