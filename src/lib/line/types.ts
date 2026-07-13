export type LineMessage={type:"text";text:string}|{type:"flex";altText:string;contents:Record<string,unknown>};
export type LineSource={type?:"user"|"group"|"room";userId?:string;groupId?:string;roomId?:string};
export interface LineWebhookEvent{webhookEventId?:string;type?:"follow"|"unfollow"|"message"|"postback"|"join"|"leave";timestamp?:number;replyToken?:string;source?:LineSource;message?:{id?:string;type?:string;text?:string};postback?:{data?:string};deliveryContext?:{isRedelivery?:boolean}}
export interface LineWebhookPayload{destination?:string;events?:LineWebhookEvent[]}
export interface LineSendResult{requestId:string;mock:boolean;status:number;response:unknown}
