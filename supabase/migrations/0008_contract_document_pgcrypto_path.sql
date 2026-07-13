begin;
revoke create on schema public from public,anon,authenticated;
alter function public.create_contract_template_version(uuid,text,text) set search_path=pg_catalog,public;
alter function public.create_contract_document_snapshot(uuid) set search_path=pg_catalog,public;
commit;
