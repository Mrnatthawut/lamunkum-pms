begin;

revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon;

grant select, update on public.profiles to authenticated;
grant select on public.organizations, public.organization_members, public.permissions, public.role_permissions to authenticated;
grant select, insert, update on public.dormitories, public.buildings, public.floors, public.room_types, public.rooms to authenticated;
grant select, insert, update on public.tenants, public.contracts, public.meters, public.meter_readings to authenticated;
grant select, insert, update on public.billing_cycles, public.invoices, public.invoice_items to authenticated;
grant select, insert, update on public.payments, public.payment_allocations to authenticated;
grant select on public.financial_ledger, public.receipts, public.line_message_logs, public.audit_logs to authenticated;

grant execute on function public.current_profile_id() to authenticated;
grant execute on function public.is_member_of(uuid) to authenticated;
grant execute on function public.is_tenant_of(uuid) to authenticated;
grant execute on function public.has_permission(text) to authenticated;
grant execute on function public.bootstrap_organization(text,text,text,text) to authenticated;

commit;
