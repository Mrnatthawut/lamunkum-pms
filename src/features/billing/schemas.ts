import {z} from "zod";

const money=z.string().trim().regex(/^\d{1,10}(\.\d{1,2})?$/,"กรุณาระบุจำนวนเงินให้ถูกต้อง");
const tax=z.string().trim().regex(/^\d{1,3}(\.\d{1,3})?$/,"กรุณาระบุภาษีให้ถูกต้อง").refine(value=>Number(value)<=100,"ภาษีต้องไม่เกิน 100%");
export const billingCycleSchema=z.object({billingMonth:z.string().regex(/^\d{4}-\d{2}-01$/),periodStart:z.string().date(),periodEnd:z.string().date(),issueDate:z.string().date(),dueDate:z.string().date(),notes:z.string().trim().max(500).optional().default("")}).superRefine((v,c)=>{if(v.periodEnd<v.periodStart)c.addIssue({code:"custom",path:["periodEnd"],message:"วันสิ้นสุดต้องไม่น้อยกว่าวันเริ่ม"});if(v.issueDate<v.periodStart)c.addIssue({code:"custom",path:["issueDate"],message:"วันออกบิลต้องไม่น้อยกว่าวันเริ่มรอบ"});if(v.dueDate<v.issueDate)c.addIssue({code:"custom",path:["dueDate"],message:"วันครบกำหนดต้องไม่น้อยกว่าวันออกบิล"});});
export const serviceChargeSchema=z.object({code:z.string().trim().min(2).max(30).regex(/^[A-Za-z0-9_-]+$/),name:z.string().trim().min(2).max(100),chargeType:z.enum(["recurring","one_time"]),defaultAmount:money,taxRate:tax});
export const assignChargeSchema=z.object({contractId:z.string().uuid(),serviceChargeTypeId:z.string().uuid(),amount:z.union([money,z.literal("")]),effectiveFrom:z.string().date(),effectiveTo:z.union([z.string().date(),z.literal("")])}).refine(v=>!v.effectiveTo||v.effectiveTo>=v.effectiveFrom,{path:["effectiveTo"],message:"วันสิ้นสุดต้องไม่น้อยกว่าวันเริ่ม"});
export const entityIdSchema=z.object({id:z.string().uuid()});
export type BillingActionState={success?:boolean;message?:string;error?:string;fieldErrors?:Record<string,string[]|undefined>};
