begin;
alter function public.create_contract_template_version(uuid,text,text) set search_path=pg_catalog,extensions;
alter function public.create_contract_document_snapshot(uuid) set search_path=pg_catalog,extensions;
commit;
