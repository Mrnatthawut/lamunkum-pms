begin;
grant select,insert,update on public.line_accounts,public.line_webhook_events,public.line_message_logs to service_role;
grant select on public.invoices,public.invoice_items,public.billing_cycles,public.rooms,public.dormitories,public.tenants to service_role;
grant select,insert,update,delete on public.line_link_attempts to service_role;
grant select,update on public.line_link_tokens to service_role;
commit;
