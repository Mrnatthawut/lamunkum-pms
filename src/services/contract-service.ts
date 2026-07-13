import type { SupabaseClient } from "@supabase/supabase-js";
import type { ContractInput, ReservationInput } from "@/features/contracts/schemas";

interface Scope { organizationId: string; dormitoryId: string }

export class ContractService {
  constructor(private readonly db: SupabaseClient, private readonly scope: Scope) {}

  async createReservation(input: ReservationInput) {
    const { data, error } = await this.db.rpc("create_reservation", {
      target_dormitory_id: this.scope.dormitoryId,
      target_room_id: input.roomId,
      target_tenant_id: input.tenantId,
      target_expected_move_in_date: input.expectedMoveInDate,
      target_booking_amount: input.bookingAmount,
      target_payment_method: input.paymentMethod,
      target_expires_at: new Date(input.expiresAt).toISOString(),
      target_status: input.status,
      target_notes: input.notes,
    });
    if (error) throw error;
    return data as string;
  }

  async setReservationStatus(reservationId: string, status: "confirmed" | "cancelled", reason = "") {
    const { error } = await this.db.rpc("set_reservation_status", { target_reservation_id: reservationId, target_status: status, target_reason: reason });
    if (error) throw error;
  }

  async createActiveContract(input: ContractInput) {
    const { data, error } = await this.db.rpc("create_active_contract_and_move_in", {
      target_dormitory_id: this.scope.dormitoryId,
      target_room_id: input.roomId,
      target_tenant_id: input.tenantId,
      target_reservation_id: input.reservationId ?? null,
      target_contract_date: input.contractDate,
      target_start_date: input.startDate,
      target_end_date: input.endDate,
      target_monthly_rent: input.monthlyRent,
      target_deposit: input.deposit,
      target_advance_rent: input.advanceRent,
      target_due_day: input.dueDay,
      target_notice_days: input.noticeDays,
      target_initial_water: input.initialWater,
      target_initial_electric: input.initialElectric,
      target_inspection_notes: input.inspectionNotes,
      target_notes: input.notes,
    });
    if (error) throw error;
    return data as string;
  }
}
