begin;

create or replace function public.generate_billing_cycle_invoices(target_billing_cycle_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cycle public.billing_cycles%rowtype; contract_row record; new_invoice_id uuid; sequence_value bigint; invoice_no text;
  subtotal_value numeric(14,2); tax_value numeric(14,2); generated_count integer:=0; skipped_count integer:=0; period_key text;
begin
  select * into cycle from public.billing_cycles where id=target_billing_cycle_id for update;
  if cycle.id is null then raise exception 'BILLING_CYCLE_NOT_FOUND'; end if;
  if not public.has_org_permission(cycle.organization_id,'invoices.manage') then raise exception 'FORBIDDEN'; end if;
  if cycle.status not in ('draft','review') then raise exception 'BILLING_CYCLE_LOCKED'; end if;
  period_key:=to_char(cycle.billing_month,'YYYYMM');
  for contract_row in select ct.*,t.id as bill_tenant_id from public.contracts ct join public.tenants t on t.id=ct.tenant_id and t.deleted_at is null
    where ct.dormitory_id=cycle.dormitory_id and ct.status in ('active','expiring') and ct.start_date<=cycle.period_end and ct.end_date>=cycle.period_start order by ct.room_id
  loop
    if exists(select 1 from public.invoices i where i.billing_cycle_id=cycle.id and i.room_id=contract_row.room_id and i.revision=1) then skipped_count:=skipped_count+1;continue;end if;
    insert into public.document_sequences(organization_id,dormitory_id,document_type,period,current_value,prefix) values(cycle.organization_id,cycle.dormitory_id,'invoice',period_key,1,'INV')
      on conflict(organization_id,dormitory_id,document_type,period) do update set current_value=public.document_sequences.current_value+1,updated_at=now() returning current_value into sequence_value;
    invoice_no:='INV-'||period_key||'-'||lpad(sequence_value::text,4,'0');
    insert into public.invoices(organization_id,dormitory_id,billing_cycle_id,room_id,tenant_id,invoice_number,issue_date,due_date,currency,total,balance,status)
      values(cycle.organization_id,cycle.dormitory_id,cycle.id,contract_row.room_id,contract_row.bill_tenant_id,invoice_no,cycle.issue_date,cycle.due_date,'THB',0,0,'pending_approval') returning id into new_invoice_id;
    insert into public.invoice_items(organization_id,invoice_id,code,description,quantity,unit,unit_price,discount,tax_rate,line_total)
      values(cycle.organization_id,new_invoice_id,'RENT','ค่าเช่าห้อง',1,'เดือน',contract_row.monthly_rent,0,0,contract_row.monthly_rent);
    insert into public.invoice_items(organization_id,invoice_id,code,description,quantity,unit,unit_price,discount,tax_rate,line_total)
      select cycle.organization_id,new_invoice_id,case m.meter_type when 'water' then 'WATER' when 'electricity' then 'ELECTRICITY' else 'UTILITY' end,case m.meter_type when 'water' then 'ค่าน้ำ' when 'electricity' then 'ค่าไฟ' else 'ค่าสาธารณูปโภค' end,mr.units,'หน่วย',case when mr.units>0 then round(mr.total_amount/mr.units,2) else 0 end,0,0,mr.total_amount
      from public.meters m join public.meter_readings mr on mr.meter_id=m.id where m.room_id=contract_row.room_id and mr.billing_month=cycle.billing_month;
    insert into public.invoice_items(organization_id,invoice_id,code,description,quantity,unit,unit_price,discount,tax_rate,line_total)
      select cycle.organization_id,new_invoice_id,s.code,s.name,1,'รายการ',coalesce(cs.amount,s.default_amount),0,s.tax_rate,coalesce(cs.amount,s.default_amount)
      from public.contract_service_charges cs join public.service_charge_types s on s.id=cs.service_charge_type_id and s.active
      where cs.contract_id=contract_row.id and cs.active and cs.effective_from<=cycle.period_end and (cs.effective_to is null or cs.effective_to>=cycle.period_start)
        and (s.charge_type='recurring' or date_trunc('month',cs.effective_from)::date=cycle.billing_month);
    select coalesce(sum(line_total-discount),0),coalesce(sum(round((line_total-discount)*tax_rate/100,2)),0) into subtotal_value,tax_value from public.invoice_items where invoice_id=new_invoice_id;
    update public.invoices set subtotal=subtotal_value,tax_total=tax_value,total=subtotal_value+tax_value,balance=subtotal_value+tax_value,updated_at=now() where id=new_invoice_id;
    insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data) values(cycle.organization_id,cycle.dormitory_id,auth.uid(),'invoice.generate','invoice',new_invoice_id,jsonb_build_object('invoice_number',invoice_no,'total',subtotal_value+tax_value));
    generated_count:=generated_count+1;
  end loop;
  update public.billing_cycles set status='review' where id=cycle.id and status='draft';
  return jsonb_build_object('generated',generated_count,'skipped',skipped_count);
end $$;

revoke all on function public.generate_billing_cycle_invoices(uuid) from public,anon;
grant execute on function public.generate_billing_cycle_invoices(uuid) to authenticated;
commit;
