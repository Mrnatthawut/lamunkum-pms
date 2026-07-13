import{z}from"zod";
const money=z.string().trim().regex(/^\d{1,12}(\.\d{1,2})?$/,"กรุณาระบุจำนวนเงินให้ถูกต้อง").refine(v=>Number(v)>0,"จำนวนเงินต้องมากกว่าศูนย์");
export const paymentSubmissionSchema=z.object({invoiceId:z.string().uuid(),paidAt:z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/),amount:money,method:z.enum(["cash","bank_transfer","promptpay","qr_payment","card","cheque","other"]),bankName:z.string().trim().max(100).optional().default(""),referenceNumber:z.string().trim().max(100).optional().default(""),payerNote:z.string().trim().max(500).optional().default(""),idempotencyKey:z.string().uuid()});
export const paymentIdSchema=z.object({id:z.string().uuid()});
export const rejectPaymentSchema=z.object({id:z.string().uuid(),reason:z.string().trim().min(3,"กรุณาระบุเหตุผลอย่างน้อย 3 ตัวอักษร").max(500)});
export type PaymentActionState={success?:boolean;message?:string;error?:string;receiptId?:string;fieldErrors?:Record<string,string[]|undefined>};
