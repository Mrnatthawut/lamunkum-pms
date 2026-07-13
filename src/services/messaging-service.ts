import type{SupabaseClient}from"@supabase/supabase-js";
export class MessagingService{constructor(private readonly db:SupabaseClient){}
 async create(input:{tenantId:string;roomId:string;subject:string;priority:string;message:string}){const{data,error}=await this.db.rpc("create_conversation",{target_tenant_id:input.tenantId,target_room_id:input.roomId||null,target_subject:input.subject,target_priority:input.priority,target_message:input.message});if(error)throw error;return data as string;}
 async send(input:{conversationId:string;body:string;internal:boolean;status:string}){const{data,error}=await this.db.rpc("send_conversation_message",{target_conversation_id:input.conversationId,target_body:input.body,target_internal:input.internal,target_status:input.status});if(error)throw error;return data as string;}
}
