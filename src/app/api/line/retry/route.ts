import{NextResponse}from"next/server";import{requireDormitoryContext}from"@/lib/auth/context";import{LineMessagingService}from"@/services/line-messaging-service";
async function authorized(request:Request){const cron=process.env.CRON_SECRET;const authorization=request.headers.get("authorization");if(cron&&authorization===`Bearer ${cron}`)return true;try{await requireDormitoryContext("line.manage");return true;}catch{return false;}}
async function run(request:Request){if(!await authorized(request))return NextResponse.json({code:"UNAUTHORIZED"},{status:401});const result=await new LineMessagingService().retryDue();return NextResponse.json(result,{headers:{"Cache-Control":"no-store"}});}
export const GET=run;export const POST=run;
