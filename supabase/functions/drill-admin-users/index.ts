import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,"Content-Type":"application/json"}});

async function findByEmail(admin:any,email:string){
  const target=email.toLowerCase();
  for(let page=1;page<=20;page++){
    const {data,error}=await admin.auth.admin.listUsers({page,perPage:1000});
    if(error)throw error;
    const found=data.users.find((u:any)=>(u.email||"").toLowerCase()===target);
    if(found)return found;
    if(data.users.length<1000)break;
  }
  return null;
}

serve(async req=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  try{
    const url=Deno.env.get("SUPABASE_URL")!;
    const anon=Deno.env.get("SUPABASE_ANON_KEY")!;
    const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const auth=req.headers.get("Authorization")||"";
    if(!auth.startsWith("Bearer "))return reply({error:"Authentication required"},401);

    const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}}});
    const admin=createClient(url,service,{auth:{autoRefreshToken:false,persistSession:false}});
    const {data:me,error:meErr}=await userClient.auth.getUser();
    if(meErr||!me.user)return reply({error:"Invalid session"},401);
    const caller=me.user.id;
    const body=await req.json();
    const action=String(body.action||"");

    const {data:global}=await admin.from("drill_global_permissions").select("is_app_admin").eq("user_id",caller).maybeSingle();
    const appAdmin=!!global?.is_app_admin;
    const {data:myPerms}=await admin.from("drill_unit_permissions").select("unit_id,unit_admin,revoked_at,expires_at").eq("user_id",caller);
    const activeAdminUnits=(myPerms||[]).filter((p:any)=>p.unit_admin&&!p.revoked_at&&(!p.expires_at||new Date(p.expires_at)>=new Date())).map((p:any)=>p.unit_id);

    if(action==="lookup_user"){
      if(!appAdmin&&!activeAdminUnits.length)return reply({error:"Unit Admin or Application Admin required"},403);
      const email=String(body.email||"").trim().toLowerCase();
      const u=await findByEmail(admin,email);
      if(!u)return reply({found:false});
      const {data:p}=await admin.from("profiles").select("id,display_name,member_id").eq("id",u.id).maybeSingle();
      let homeUnitId=null,capid=null,firstName=null,lastName=null;
      if(p?.member_id){
        const {data:m}=await admin.from("members").select("capid,first_name,last_name").eq("id",p.member_id).maybeSingle();
        capid=m?.capid||null;firstName=m?.first_name||null;lastName=m?.last_name||null;
        const {data:a}=await admin.from("member_unit_assignments").select("unit_id").eq("member_id",p.member_id).eq("active",true).eq("is_primary",true).order("start_date",{ascending:false}).limit(1).maybeSingle();
        homeUnitId=a?.unit_id||null;
      }
      return reply({found:true,userId:u.id,email:u.email,displayName:p?.display_name||[firstName,lastName].filter(Boolean).join(" ")||u.email,memberId:p?.member_id||null,capid,firstName,lastName,homeUnitId});
    }

    if(action==="ensure_user"){
      const email=String(body.email||"").trim().toLowerCase();
      const memberId=body.memberId?String(body.memberId):null;
      const displayName=String(body.displayName||"").trim();
      const password=String(body.password||"");
      if(!email||!memberId)return reply({error:"Email and memberId are required"},400);

      const {data:a}=await admin.from("member_unit_assignments").select("unit_id").eq("member_id",memberId).eq("active",true).eq("is_primary",true).order("start_date",{ascending:false}).limit(1).maybeSingle();
      const home=a?.unit_id||null;
      if(!home)return reply({error:"Target member has no active primary home unit"},400);
      if(!appAdmin&&!activeAdminUnits.includes(home))return reply({error:"Only App Admin or the member's home Unit Admin may create/link this login"},403);

      let u=await findByEmail(admin,email),created=false;
      if(!u){
        if(!password)return reply({error:"Initial password required for a new account"},400);
        const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{display_name:displayName||email}});
        if(error)throw error;u=data.user;created=true;
      } else {
        const {data:existingProfile,error:existingProfileError}=await admin.from("profiles").select("member_id").eq("id",u.id).maybeSingle();
        if(existingProfileError)throw existingProfileError;
        if(existingProfile?.member_id && existingProfile.member_id!==memberId){
          return reply({error:"That login is already linked to a different CAP member. An Application Admin must resolve the existing account link before it can be reassigned."},409);
        }
      }
      const profile:any={id:u.id,member_id:memberId}; if(displayName)profile.display_name=displayName;
      const {error:pe}=await admin.from("profiles").upsert(profile,{onConflict:"id"}); if(pe)throw pe;
      await admin.from("drill_global_permissions").upsert({user_id:u.id},{onConflict:"user_id"});
      await admin.from("drill_audit_log").insert({actor_user_id:caller,action:created?"CREATE_AUTH_USER":"LINK_AUTH_USER",entity_type:"user",entity_id:u.id,target_user_id:u.id,unit_id:home,details:{email,member_id:memberId}});
      return reply({ok:true,userId:u.id,created,email});
    }

    return reply({error:"Unsupported action"},400);
  }catch(e){console.error(e);return reply({error:e instanceof Error?e.message:String(e)},500)}
});
