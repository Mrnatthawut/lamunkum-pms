create unique index if not exists one_active_meter_type_per_room on public.meters(room_id,meter_type) where active;
