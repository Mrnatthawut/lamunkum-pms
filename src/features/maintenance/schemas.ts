import { z } from "zod";

const optionalDateTime = z.union([z.string().datetime({ local: true }), z.literal("")]);
const money = z.string().trim().regex(/^\d{1,12}(\.\d{1,2})?$/, "จำนวนเงินไม่ถูกต้อง");
export const createTicketSchema = z.object({
  roomId: z.string().uuid(), category: z.string().trim().min(2).max(60), title: z.string().trim().min(3).max(160),
  description: z.string().trim().min(5).max(4000), urgency: z.enum(["low", "normal", "high", "emergency"]), preferredAt: optionalDateTime,
});
export const updateTicketSchema = z.object({
  ticketId: z.string().uuid(), status: z.enum(["new", "acknowledged", "scheduled", "in_progress", "waiting_parts", "completed", "cancelled", "closed"]),
  assignedTo: z.union([z.string().uuid(), z.literal("")]), cost: money, costResponsibility: z.enum(["dormitory", "tenant", "shared", "pending"]), note: z.string().trim().max(2000).optional().default(""),
});
export const addCommentSchema = z.object({ ticketId: z.string().uuid(), body: z.string().trim().min(1).max(2000), internal: z.enum(["true", "false"]) });
export type MaintenanceActionState = { success?: boolean; message?: string; error?: string; fieldErrors?: Record<string, string[] | undefined> };
