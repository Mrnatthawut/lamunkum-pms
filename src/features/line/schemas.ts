import{z}from"zod";
export const lineLinkConfirmSchema=z.object({code:z.string().regex(/^[a-f0-9]{32}$/),idToken:z.string().min(20).max(4096).optional(),lineUserId:z.string().regex(/^U[A-Za-z0-9_-]{8,64}$/).optional(),displayName:z.string().trim().max(100).optional().default("")});
export const lineSendSchema=z.object({tenantId:z.string().uuid(),kind:z.enum(["invoice","text"]),text:z.string().trim().max(500).optional().default(""),idempotencyKey:z.string().uuid()}).refine(v=>v.kind!=="text"||v.text.length>0,{path:["text"],message:"กรุณาระบุข้อความ"});
export const lineDisconnectSchema=z.object({tenantId:z.string().uuid()});
export type LineActionState={success?:boolean;message?:string;error?:string;linkUrl?:string;fieldErrors?:Record<string,string[]|undefined>};
