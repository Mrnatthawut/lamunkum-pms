begin;

insert into public.permissions(code,description) values
('announcements.read','ดูประกาศ'),('announcements.manage','สร้างและแก้ไขประกาศ'),('announcements.send','เผยแพร่ประกาศ'),('notifications.read','ดูการแจ้งเตือนภายในระบบ') on conflict do nothing;
insert into public.role_permissions(role,permission_id)
select r,p.id from unnest(array['super_admin','owner','manager','staff']::public.app_role[]) r cross join public.permissions p
where p.code in ('announcements.read','notifications.read') on conflict do nothing;
insert into public.role_permissions(role,permission_id)
select r,p.id from unnest(array['super_admin','owner','manager']::public.app_role[]) r cross join public.permissions p
where p.code in ('announcements.manage','announcements.send') on conflict do nothing;
insert into public.role_permissions(role,permission_id)
select r,p.id from unnest(array['accountant','maintenance']::public.app_role[]) r cross join public.permissions p
where p.code='notifications.read' on conflict do nothing;

create table public.announcements(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 dormitory_id uuid not null references public.dormitories(id) on delete restrict,title text not null,content text not null,
 status text not null default 'draft' check(status in ('draft','scheduled','publishing','published','cancelled')),
 target_type text not null default 'all' check(target_type in ('all','building','floor','room','tenant')),target_id uuid,
 channel_web boolean not null default true,channel_line boolean not null default false,publish_at timestamptz,starts_at timestamptz not null default now(),ends_at timestamptz,
 created_by uuid not null references public.profiles(id) on delete restrict,published_by uuid references public.profiles(id) on delete restrict,published_at timestamptz,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),version integer not null default 1,
 check(channel_web or channel_line),check((target_type='all' and target_id is null) or (target_type<>'all' and target_id is not null)),check(ends_at is null or ends_at>starts_at)
);
create index announcements_schedule_idx on public.announcements(dormitory_id,status,publish_at);
create index announcements_active_idx on public.announcements(dormitory_id,starts_at,ends_at) where status='published';

create table public.announcement_recipients(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 dormitory_id uuid not null references public.dormitories(id) on delete restrict,announcement_id uuid not null references public.announcements(id) on delete restrict,
 tenant_id uuid not null references public.tenants(id) on delete restrict,room_id uuid references public.rooms(id) on delete restrict,
 web_available boolean not null default false,line_status text not null default 'not_requested' check(line_status in ('not_requested','queued','sent','failed','not_connected')),
 line_error text,viewed_at timestamptz,sent_at timestamptz,created_at timestamptz not null default now(),unique(announcement_id,tenant_id)
);
create index announcement_recipients_tenant_idx on public.announcement_recipients(tenant_id,created_at desc);

create table public.user_notifications(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 dormitory_id uuid references public.dormitories(id) on delete restrict,profile_id uuid not null references public.profiles(id) on delete restrict,
 notification_type text not null,title text not null,body text not null,entity_type text,entity_id uuid,href text,
 idempotency_key text not null,read_at timestamptz,created_at timestamptz not null default now(),unique(profile_id,idempotency_key)
);
create index user_notifications_unread_idx on public.user_notifications(profile_id,created_at desc) where read_at is null;

create table public.notification_jobs(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 dormitory_id uuid not null references public.dormitories(id) on delete restrict,job_type text not null check(job_type in ('announcement_publish')),
 entity_id uuid not null,run_at timestamptz not null,status text not null default 'queued' check(status in ('queued','running','completed','failed','cancelled')),
 idempotency_key text not null unique,attempt_count integer not null default 0,locked_at timestamptz,completed_at timestamptz,error text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index notification_jobs_due_idx on public.notification_jobs(status,run_at) where status in ('queued','failed');

alter table public.announcements enable row level security;alter table public.announcement_recipients enable row level security;
alter table public.user_notifications enable row level security;alter table public.notification_jobs enable row level security;
create policy announcement_staff_read on public.announcements for select using(public.has_org_permission(organization_id,'announcements.read'));
create policy announcement_tenant_read on public.announcements for select using(status='published' and exists(select 1 from public.announcement_recipients ar where ar.announcement_id=id and public.is_tenant_of(ar.tenant_id)));
create policy recipient_staff_read on public.announcement_recipients for select using(public.has_org_permission(organization_id,'announcements.read'));
create policy recipient_tenant_read on public.announcement_recipients for select using(public.is_tenant_of(tenant_id));
create policy notification_self_read on public.user_notifications for select using(profile_id=auth.uid());
create policy job_manager_read on public.notification_jobs for select using(public.has_org_permission(organization_id,'announcements.manage'));
grant select on public.announcements,public.announcement_recipients,public.user_notifications,public.notification_jobs to authenticated;

create or replace function public.create_announcement(target_dormitory_id uuid,target_title text,target_content text,target_target_type text,target_target_id uuid,target_web boolean,target_line boolean,target_publish_at timestamptz,target_starts_at timestamptz,target_ends_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare d public.dormitories%rowtype;new_id uuid;initial_status text;
begin select * into d from public.dormitories where id=target_dormitory_id and deleted_at is null;if d.id is null then raise exception 'DORMITORY_NOT_FOUND';end if;
 if not public.has_org_permission(d.organization_id,'announcements.manage') then raise exception 'FORBIDDEN';end if;
 if length(trim(target_title))<3 or length(trim(target_content))<5 or target_target_type not in ('all','building','floor','room','tenant') or not(target_web or target_line) then raise exception 'INVALID_ANNOUNCEMENT';end if;
 if (target_target_type='all' and target_target_id is not null) or (target_target_type<>'all' and target_target_id is null) then raise exception 'INVALID_TARGET';end if;
 if target_target_type='building' and not exists(select 1 from public.buildings x where x.id=target_target_id and x.dormitory_id=d.id) then raise exception 'INVALID_TARGET';end if;
 if target_target_type='floor' and not exists(select 1 from public.floors x where x.id=target_target_id and x.dormitory_id=d.id) then raise exception 'INVALID_TARGET';end if;
 if target_target_type='room' and not exists(select 1 from public.rooms x where x.id=target_target_id and x.dormitory_id=d.id) then raise exception 'INVALID_TARGET';end if;
 if target_target_type='tenant' and not exists(select 1 from public.tenants x where x.id=target_target_id and x.dormitory_id=d.id and x.deleted_at is null) then raise exception 'INVALID_TARGET';end if;
 initial_status:=case when target_publish_at is not null then 'scheduled' else 'draft' end;
 insert into public.announcements(organization_id,dormitory_id,title,content,status,target_type,target_id,channel_web,channel_line,publish_at,starts_at,ends_at,created_by)
 values(d.organization_id,d.id,left(trim(target_title),200),left(trim(target_content),10000),initial_status,target_target_type,target_target_id,target_web,target_line,target_publish_at,coalesce(target_starts_at,now()),target_ends_at,auth.uid()) returning id into new_id;
 if initial_status='scheduled' then insert into public.notification_jobs(organization_id,dormitory_id,job_type,entity_id,run_at,idempotency_key) values(d.organization_id,d.id,'announcement_publish',new_id,target_publish_at,'announcement:'||new_id::text||':publish') on conflict do nothing;end if;
 insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data) values(d.organization_id,d.id,auth.uid(),'announcement.create','announcement',new_id,jsonb_build_object('status',initial_status,'target_type',target_target_type,'web',target_web,'line',target_line,'publish_at',target_publish_at));return new_id;end $$;

create or replace function public.prepare_announcement_publish(target_announcement_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.announcements%rowtype;recipients jsonb;
begin select * into a from public.announcements where id=target_announcement_id for update;if a.id is null then raise exception 'ANNOUNCEMENT_NOT_FOUND';end if;
 if coalesce(auth.role(),'')<>'service_role' and not public.has_org_permission(a.organization_id,'announcements.send') then raise exception 'FORBIDDEN';end if;
 if a.status='cancelled' then raise exception 'ANNOUNCEMENT_CANCELLED';end if;
 insert into public.announcement_recipients(organization_id,dormitory_id,announcement_id,tenant_id,room_id,web_available,line_status)
 select distinct a.organization_id,a.dormitory_id,a.id,c.tenant_id,c.room_id,a.channel_web,case when a.channel_line then case when la.id is null then 'not_connected' else 'queued' end else 'not_requested' end
 from public.contracts c join public.rooms r on r.id=c.room_id left join public.line_accounts la on la.tenant_id=c.tenant_id and la.status='connected'
 where c.dormitory_id=a.dormitory_id and c.status in ('active','expiring') and (
  a.target_type='all' or (a.target_type='building' and r.building_id=a.target_id) or (a.target_type='floor' and r.floor_id=a.target_id) or
  (a.target_type='room' and r.id=a.target_id) or (a.target_type='tenant' and c.tenant_id=a.target_id))
 on conflict(announcement_id,tenant_id) do nothing;
 update public.announcements set status='published',published_at=coalesce(published_at,now()),published_by=coalesce(published_by,auth.uid()),updated_at=now(),version=version+1 where id=a.id;
 insert into public.user_notifications(organization_id,dormitory_id,profile_id,notification_type,title,body,entity_type,entity_id,href,idempotency_key)
 select a.organization_id,a.dormitory_id,m.profile_id,'announcement_published','เผยแพร่ประกาศแล้ว',a.title,'announcement',a.id,'/announcements','announcement:'||a.id::text||':staff:'||m.profile_id::text
 from public.organization_members m where m.organization_id=a.organization_id and m.active on conflict do nothing;
 select coalesce(jsonb_agg(jsonb_build_object('recipient_id',ar.id,'tenant_id',ar.tenant_id)),'[]'::jsonb) into recipients from public.announcement_recipients ar where ar.announcement_id=a.id and ar.line_status='queued';
 update public.notification_jobs set status='completed',completed_at=now(),updated_at=now(),error=null where entity_id=a.id and job_type='announcement_publish';
 insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data) values(a.organization_id,a.dormitory_id,auth.uid(),'announcement.publish','announcement',a.id,jsonb_build_object('recipient_count',(select count(*) from public.announcement_recipients ar where ar.announcement_id=a.id)));
 return jsonb_build_object('announcement_id',a.id,'title',a.title,'content',a.content,'line',a.channel_line,'recipients',recipients);end $$;

create or replace function public.mark_notification_read(target_notification_id uuid)
returns void language plpgsql security definer set search_path='' as $$ begin update public.user_notifications set read_at=coalesce(read_at,now()) where id=target_notification_id and profile_id=auth.uid();if not found then raise exception 'NOTIFICATION_NOT_FOUND';end if;end $$;
create or replace function public.mark_all_notifications_read()
returns integer language plpgsql security definer set search_path='' as $$ declare changed integer;begin update public.user_notifications set read_at=now() where profile_id=auth.uid() and read_at is null;get diagnostics changed=row_count;return changed;end $$;

revoke all on function public.create_announcement(uuid,text,text,text,uuid,boolean,boolean,timestamptz,timestamptz,timestamptz),public.prepare_announcement_publish(uuid),public.mark_notification_read(uuid),public.mark_all_notifications_read() from public,anon;
grant execute on function public.create_announcement(uuid,text,text,text,uuid,boolean,boolean,timestamptz,timestamptz,timestamptz),public.prepare_announcement_publish(uuid),public.mark_notification_read(uuid),public.mark_all_notifications_read() to authenticated;
grant execute on function public.prepare_announcement_publish(uuid) to service_role;
grant select,update on public.announcement_recipients,public.announcements,public.notification_jobs to service_role;
commit;
