begin;

insert into public.permissions(code,description) values
('maintenance.read','ดูงานแจ้งซ่อม'),('maintenance.manage','สร้างและอัปเดตงานแจ้งซ่อม'),('maintenance.assign','มอบหมายงานแจ้งซ่อม'),
('messages.read','ดูกล่องข้อความ'),('messages.send','ส่งและจัดการข้อความ') on conflict do nothing;
insert into public.role_permissions(role,permission_id)
select r,p.id from unnest(array['super_admin','owner','manager','staff','maintenance']::public.app_role[]) r
cross join public.permissions p where p.code in ('maintenance.read','maintenance.manage') on conflict do nothing;
insert into public.role_permissions(role,permission_id)
select r,p.id from unnest(array['super_admin','owner','manager']::public.app_role[]) r
cross join public.permissions p where p.code='maintenance.assign' on conflict do nothing;
insert into public.role_permissions(role,permission_id)
select r,p.id from unnest(array['super_admin','owner','manager','staff']::public.app_role[]) r
cross join public.permissions p where p.code in ('messages.read','messages.send') on conflict do nothing;

create table public.maintenance_tickets(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 dormitory_id uuid not null references public.dormitories(id) on delete restrict,tenant_id uuid references public.tenants(id) on delete restrict,
 room_id uuid not null references public.rooms(id) on delete restrict,ticket_number text not null,category text not null,
 title text not null,description text not null,urgency text not null default 'normal' check(urgency in ('low','normal','high','emergency')),
 status text not null default 'new' check(status in ('new','acknowledged','scheduled','in_progress','waiting_parts','completed','cancelled','closed')),
 preferred_at timestamptz,due_at timestamptz,assigned_to uuid references public.profiles(id) on delete restrict,
 cost numeric(14,2) not null default 0 check(cost>=0),cost_responsibility text not null default 'dormitory' check(cost_responsibility in ('dormitory','tenant','shared','pending')),
 internal_notes text,completed_at timestamptz,created_by uuid references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),version integer not null default 1,
 unique(organization_id,ticket_number)
);
create index maintenance_monitor_idx on public.maintenance_tickets(dormitory_id,status,due_at) where status not in ('completed','cancelled','closed');
create index maintenance_tenant_idx on public.maintenance_tickets(tenant_id,created_at desc);

create table public.maintenance_comments(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 dormitory_id uuid not null references public.dormitories(id) on delete restrict,ticket_id uuid not null references public.maintenance_tickets(id) on delete restrict,
 sender_profile_id uuid references public.profiles(id) on delete restrict,sender_tenant_id uuid references public.tenants(id) on delete restrict,
 body text not null,internal_note boolean not null default false,created_at timestamptz not null default now(),
 check((sender_profile_id is not null)::integer+(sender_tenant_id is not null)::integer=1)
);
create index maintenance_comments_ticket_idx on public.maintenance_comments(ticket_id,created_at);

create table public.maintenance_attachments(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 dormitory_id uuid not null references public.dormitories(id) on delete restrict,ticket_id uuid not null references public.maintenance_tickets(id) on delete restrict,
 comment_id uuid references public.maintenance_comments(id) on delete restrict,storage_path text not null,file_name text not null,mime_type text not null,
 file_size bigint not null check(file_size>0 and file_size<=26214400),attachment_stage text not null default 'reported' check(attachment_stage in ('reported','before','after')),
 uploaded_by uuid references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),unique(storage_path)
);

create table public.conversations(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 dormitory_id uuid not null references public.dormitories(id) on delete restrict,tenant_id uuid not null references public.tenants(id) on delete restrict,
 room_id uuid references public.rooms(id) on delete restrict,channel text not null default 'web' check(channel in ('web','line')),
 subject text not null,status text not null default 'open' check(status in ('open','pending','resolved','closed')),
 priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),assigned_to uuid references public.profiles(id) on delete restrict,
 last_message_at timestamptz not null default now(),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),version integer not null default 1
);
create index conversations_inbox_idx on public.conversations(dormitory_id,status,last_message_at desc);
create index conversations_tenant_idx on public.conversations(tenant_id,last_message_at desc);

create table public.messages(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 dormitory_id uuid not null references public.dormitories(id) on delete restrict,conversation_id uuid not null references public.conversations(id) on delete restrict,
 sender_profile_id uuid references public.profiles(id) on delete restrict,sender_tenant_id uuid references public.tenants(id) on delete restrict,
 direction text not null check(direction in ('inbound','outbound')),body text not null,internal_note boolean not null default false,
 line_message_id text,delivery_status text not null default 'stored' check(delivery_status in ('stored','queued','sent','delivered','failed')),
 read_at timestamptz,created_at timestamptz not null default now(),
 check((sender_profile_id is not null)::integer+(sender_tenant_id is not null)::integer=1)
);
create index messages_conversation_idx on public.messages(conversation_id,created_at);
create unique index messages_line_id_unique on public.messages(line_message_id) where line_message_id is not null;

alter table public.maintenance_tickets enable row level security;
alter table public.maintenance_comments enable row level security;
alter table public.maintenance_attachments enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

create policy maintenance_staff_read on public.maintenance_tickets for select using(public.has_org_permission(organization_id,'maintenance.read'));
create policy maintenance_tenant_read on public.maintenance_tickets for select using(tenant_id is not null and public.is_tenant_of(tenant_id));
create policy maintenance_comment_staff_read on public.maintenance_comments for select using(public.has_org_permission(organization_id,'maintenance.read'));
create policy maintenance_comment_tenant_read on public.maintenance_comments for select using(not internal_note and exists(select 1 from public.maintenance_tickets t where t.id=ticket_id and public.is_tenant_of(t.tenant_id)));
create policy maintenance_attachment_staff_read on public.maintenance_attachments for select using(public.has_org_permission(organization_id,'maintenance.read'));
create policy maintenance_attachment_tenant_read on public.maintenance_attachments for select using(exists(select 1 from public.maintenance_tickets t where t.id=ticket_id and public.is_tenant_of(t.tenant_id)));
create policy conversation_staff_read on public.conversations for select using(public.has_org_permission(organization_id,'messages.read'));
create policy conversation_tenant_read on public.conversations for select using(public.is_tenant_of(tenant_id));
create policy message_staff_read on public.messages for select using(public.has_org_permission(organization_id,'messages.read'));
create policy message_tenant_read on public.messages for select using(not internal_note and exists(select 1 from public.conversations c where c.id=conversation_id and public.is_tenant_of(c.tenant_id)));
grant select on public.maintenance_tickets,public.maintenance_comments,public.maintenance_attachments,public.conversations,public.messages to authenticated;

create or replace function public.create_maintenance_ticket(target_room_id uuid,target_category text,target_title text,target_description text,target_urgency text,target_preferred_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare r public.rooms%rowtype;t public.tenants%rowtype;seq bigint;ticket_id uuid;number text;deadline timestamptz;
begin
 select * into r from public.rooms where id=target_room_id and deleted_at is null;if r.id is null then raise exception 'ROOM_NOT_FOUND';end if;
 if not public.has_org_permission(r.organization_id,'maintenance.manage') then raise exception 'FORBIDDEN';end if;
 if length(trim(target_title))<3 or length(trim(target_description))<5 or target_urgency not in ('low','normal','high','emergency') then raise exception 'INVALID_TICKET';end if;
 select tn.* into t from public.contracts c join public.tenants tn on tn.id=c.tenant_id where c.room_id=r.id and c.status in ('active','expiring') limit 1;
 insert into public.document_sequences(organization_id,dormitory_id,document_type,period,current_value,prefix)
 values(r.organization_id,r.dormitory_id,'maintenance',to_char(now() at time zone 'Asia/Bangkok','YYYYMM'),1,'MNT')
 on conflict(organization_id,dormitory_id,document_type,period) do update set current_value=public.document_sequences.current_value+1,updated_at=now()
 returning current_value into seq;
 number:='MNT-'||to_char(now() at time zone 'Asia/Bangkok','YYYYMM')||'-'||lpad(seq::text,4,'0');
 deadline:=now()+case target_urgency when 'emergency' then interval '4 hours' when 'high' then interval '1 day' when 'normal' then interval '3 days' else interval '7 days' end;
 insert into public.maintenance_tickets(organization_id,dormitory_id,tenant_id,room_id,ticket_number,category,title,description,urgency,preferred_at,due_at,created_by)
 values(r.organization_id,r.dormitory_id,t.id,r.id,number,left(trim(target_category),60),left(trim(target_title),160),left(trim(target_description),4000),target_urgency,target_preferred_at,deadline,auth.uid()) returning id into ticket_id;
 insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
 values(r.organization_id,r.dormitory_id,auth.uid(),'maintenance.create','maintenance_ticket',ticket_id,jsonb_build_object('ticket_number',number,'room_id',r.id,'urgency',target_urgency,'due_at',deadline));
 return ticket_id;
end $$;

create or replace function public.update_maintenance_ticket(target_ticket_id uuid,target_status text,target_assigned_to uuid,target_cost numeric,target_cost_responsibility text,target_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.maintenance_tickets%rowtype;new_version integer;
begin
 select * into t from public.maintenance_tickets where id=target_ticket_id for update;if t.id is null then raise exception 'TICKET_NOT_FOUND';end if;
 if not public.has_org_permission(t.organization_id,'maintenance.manage') then raise exception 'FORBIDDEN';end if;
 if target_assigned_to is distinct from t.assigned_to and not public.has_org_permission(t.organization_id,'maintenance.assign') then raise exception 'ASSIGN_FORBIDDEN';end if;
 if target_status not in ('new','acknowledged','scheduled','in_progress','waiting_parts','completed','cancelled','closed') or target_cost<0 or target_cost_responsibility not in ('dormitory','tenant','shared','pending') then raise exception 'INVALID_TICKET_UPDATE';end if;
 if target_assigned_to is not null and not exists(select 1 from public.organization_members m where m.profile_id=target_assigned_to and m.organization_id=t.organization_id and m.active) then raise exception 'ASSIGNEE_INVALID';end if;
 update public.maintenance_tickets set status=target_status,assigned_to=target_assigned_to,cost=target_cost,cost_responsibility=target_cost_responsibility,
 internal_notes=case when trim(coalesce(target_note,''))='' then internal_notes else left(trim(target_note),2000) end,
 completed_at=case when target_status in ('completed','closed') then coalesce(completed_at,now()) else null end,updated_at=now(),version=version+1 where id=t.id returning version into new_version;
 if trim(coalesce(target_note,''))<>'' then insert into public.maintenance_comments(organization_id,dormitory_id,ticket_id,sender_profile_id,body,internal_note) values(t.organization_id,t.dormitory_id,t.id,auth.uid(),left(trim(target_note),2000),true);end if;
 insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,before_data,after_data)
 values(t.organization_id,t.dormitory_id,auth.uid(),'maintenance.update','maintenance_ticket',t.id,jsonb_build_object('status',t.status,'assigned_to',t.assigned_to,'cost',t.cost),jsonb_build_object('status',target_status,'assigned_to',target_assigned_to,'cost',target_cost,'version',new_version));
 return jsonb_build_object('ticket_id',t.id,'ticket_number',t.ticket_number,'tenant_id',t.tenant_id,'status',target_status,'version',new_version);
end $$;

create or replace function public.add_maintenance_comment(target_ticket_id uuid,target_body text,target_internal boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare t public.maintenance_tickets%rowtype;comment_id uuid;
begin select * into t from public.maintenance_tickets where id=target_ticket_id;if t.id is null then raise exception 'TICKET_NOT_FOUND';end if;
 if not public.has_org_permission(t.organization_id,'maintenance.manage') or length(trim(target_body))<1 then raise exception 'FORBIDDEN';end if;
 insert into public.maintenance_comments(organization_id,dormitory_id,ticket_id,sender_profile_id,body,internal_note) values(t.organization_id,t.dormitory_id,t.id,auth.uid(),left(trim(target_body),2000),target_internal) returning id into comment_id;
 update public.maintenance_tickets set updated_at=now(),version=version+1 where id=t.id;
 return comment_id;end $$;

create or replace function public.create_conversation(target_tenant_id uuid,target_room_id uuid,target_subject text,target_priority text,target_message text)
returns uuid language plpgsql security definer set search_path='' as $$
declare t public.tenants%rowtype;conversation_id uuid;
begin select * into t from public.tenants where id=target_tenant_id and deleted_at is null;if t.id is null then raise exception 'TENANT_NOT_FOUND';end if;
 if not public.has_org_permission(t.organization_id,'messages.send') then raise exception 'FORBIDDEN';end if;
 if target_priority not in ('low','normal','high','urgent') or length(trim(target_subject))<3 or length(trim(target_message))<1 then raise exception 'INVALID_CONVERSATION';end if;
 if target_room_id is not null and not exists(select 1 from public.rooms r where r.id=target_room_id and r.dormitory_id=t.dormitory_id) then raise exception 'ROOM_INVALID';end if;
 insert into public.conversations(organization_id,dormitory_id,tenant_id,room_id,subject,priority) values(t.organization_id,t.dormitory_id,t.id,target_room_id,left(trim(target_subject),160),target_priority) returning id into conversation_id;
 insert into public.messages(organization_id,dormitory_id,conversation_id,sender_profile_id,direction,body) values(t.organization_id,t.dormitory_id,conversation_id,auth.uid(),'outbound',left(trim(target_message),4000));
 insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data) values(t.organization_id,t.dormitory_id,auth.uid(),'conversation.create','conversation',conversation_id,jsonb_build_object('tenant_id',t.id,'priority',target_priority));return conversation_id;end $$;

create or replace function public.send_conversation_message(target_conversation_id uuid,target_body text,target_internal boolean,target_status text)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.conversations%rowtype;message_id uuid;
begin select * into c from public.conversations where id=target_conversation_id for update;if c.id is null then raise exception 'CONVERSATION_NOT_FOUND';end if;
 if not public.has_org_permission(c.organization_id,'messages.send') then raise exception 'FORBIDDEN';end if;
 if length(trim(target_body))<1 or target_status not in ('open','pending','resolved','closed') then raise exception 'INVALID_MESSAGE';end if;
 insert into public.messages(organization_id,dormitory_id,conversation_id,sender_profile_id,direction,body,internal_note) values(c.organization_id,c.dormitory_id,c.id,auth.uid(),'outbound',left(trim(target_body),4000),target_internal) returning id into message_id;
 update public.conversations set status=target_status,last_message_at=now(),updated_at=now(),version=version+1 where id=c.id;
 insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data) values(c.organization_id,c.dormitory_id,auth.uid(),'conversation.message','conversation',c.id,jsonb_build_object('message_id',message_id,'internal',target_internal,'status',target_status));return message_id;end $$;

revoke all on function public.create_maintenance_ticket(uuid,text,text,text,text,timestamptz),public.update_maintenance_ticket(uuid,text,uuid,numeric,text,text),public.add_maintenance_comment(uuid,text,boolean),public.create_conversation(uuid,uuid,text,text,text),public.send_conversation_message(uuid,text,boolean,text) from public,anon;
grant execute on function public.create_maintenance_ticket(uuid,text,text,text,text,timestamptz),public.update_maintenance_ticket(uuid,text,uuid,numeric,text,text),public.add_maintenance_comment(uuid,text,boolean),public.create_conversation(uuid,uuid,text,text,text),public.send_conversation_message(uuid,text,boolean,text) to authenticated;
commit;
