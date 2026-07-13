import { z } from "zod";
export const createConversationSchema = z.object({tenantId:z.string().uuid(),roomId:z.union([z.string().uuid(),z.literal("")]),subject:z.string().trim().min(3).max(160),priority:z.enum(["low","normal","high","urgent"]),message:z.string().trim().min(1).max(4000)});
export const sendMessageSchema = z.object({conversationId:z.string().uuid(),body:z.string().trim().min(1).max(4000),internal:z.enum(["true","false"]),status:z.enum(["open","pending","resolved","closed"])});
export type MessagingActionState={success?:boolean;message?:string;error?:string;fieldErrors?:Record<string,string[]|undefined>};
