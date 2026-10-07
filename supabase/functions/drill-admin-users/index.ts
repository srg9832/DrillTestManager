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

    const {data:global,error:globalError}=await admin.from("drill_global_permissions")
      .select("is_app_admin").eq("user_id",caller).maybeSingle();
    if(globalError)throw globalError;
    const appAdmin=!!global?.is_app_admin;

    const {data:myPerms,error:myPermsError}=await admin.from("drill_unit_permissions")
      .select("unit_id,unit_admin,revoked_at,expires_at").eq("user_id",caller);
    if(myPermsError)throw myPermsError;
    const activeAdminUnits=(myPerms||[])
      .filter((p:any)=>p.unit_admin&&!p.revoked_at&&(!p.expires_at||new Date(p.expires_at)>=new Date()))
      .map((p:any)=>p.unit_id);

    if(action==="lookup_user"){
      if(!appAdmin&&!activeAdminUnits.length)return reply({error:"Unit Admin or Application Admin required"},403);
      const email=String(body.email||"").trim().toLowerCase();
      if(!email)return reply({error:"Email is required"},400);
      const u=await findByEmail(admin,email);
      if(!u)return reply({found:false});

      const [{data:p,error:pError},{data:s,error:sError}]=await Promise.all([
        admin.from("profiles").select("id,display_name").eq("id",u.id).maybeSingle(),
        admin.from("drill_user_settings").select("home_unit_id").eq("user_id",u.id).maybeSingle(),
      ]);
      if(pError)throw pError;
      if(sError)throw sError;

      return reply({
        found:true,
        userId:u.id,
        email:u.email,
        displayName:p?.display_name||u.email||"CAP User",
        homeUnitId:s?.home_unit_id||null,
      });
    }

    if(action==="ensure_user"){
      const email=String(body.email||"").trim().toLowerCase();
      const displayName=String(body.displayName||"").trim();
      const password=String(body.password||"");
      const homeUnitId=body.homeUnitId?String(body.homeUnitId):"";

      if(!email||!displayName||!homeUnitId){
        return reply({error:"Display name, email, and Drill home unit are required"},400);
      }

      const {data:homeUnit,error:homeUnitError}=await admin.from("units")
        .select("id,active").eq("id",homeUnitId).maybeSingle();
      if(homeUnitError)throw homeUnitError;
      if(!homeUnit?.active)return reply({error:"Valid active Drill home unit required"},400);

      if(!appAdmin&&!activeAdminUnits.includes(homeUnitId)){
        return reply({error:"You may create or authorize Drill users only for a unit you administer"},403);
      }

      let u=await findByEmail(admin,email),created=false;
      if(!u){
        if(!password)return reply({error:"Initial password required for a brand-new shared account"},400);
        const {data,error}=await admin.auth.admin.createUser({
          email,
          password,
          email_confirm:true,
          user_metadata:{display_name:displayName},
        });
        if(error)throw error;
        u=data.user;
        created=true;
      }

      const [{data:existingProfile,error:profileReadError},{data:setting,error:settingError}]=await Promise.all([
        admin.from("profiles").select("id,display_name").eq("id",u.id).maybeSingle(),
        admin.from("drill_user_settings").select("home_unit_id").eq("user_id",u.id).maybeSingle(),
      ]);
      if(profileReadError)throw profileReadError;
      if(settingError)throw settingError;

      if(setting?.home_unit_id && setting.home_unit_id!==homeUnitId && !appAdmin){
        return reply({error:"Only a Drill App Admin can move an existing Drill user to a different home unit"},409);
      }

      if(existingProfile){
        if(appAdmin||created){
          const {error}=await admin.from("profiles").update({display_name:displayName}).eq("id",u.id);
          if(error)throw error;
        }
      }else{
        const {error}=await admin.from("profiles").insert({
          id:u.id,
          display_name:displayName,
          is_app_admin:false,
        });
        if(error)throw error;
      }

      if(appAdmin && !created){
        const {error}=await admin.auth.admin.updateUserById(u.id,{
          user_metadata:{...(u.user_metadata||{}),display_name:displayName},
          ...(password?{password}:{})
        });
        if(error)throw error;
      }

      const {error:settingsError}=await admin.from("drill_user_settings").upsert({
        user_id:u.id,
        home_unit_id:homeUnitId,
        updated_at:new Date().toISOString(),
        updated_by:caller,
      },{onConflict:"user_id"});
      if(settingsError)throw settingsError;

      const {error:globalPermError}=await admin.from("drill_global_permissions")
        .upsert({user_id:u.id},{onConflict:"user_id"});
      if(globalPermError)throw globalPermError;

      const {error:auditError}=await admin.from("drill_audit_log").insert({
        actor_user_id:caller,
        action:created?"CREATE_AUTH_USER":"AUTHORIZE_DRILL_USER",
        entity_type:"user",
        entity_id:u.id,
        target_user_id:u.id,
        unit_id:homeUnitId,
        details:{email,drill_home_unit_id:homeUnitId},
      });
      if(auditError)throw auditError;

      return reply({ok:true,userId:u.id,created,email,homeUnitId});
    }

    return reply({error:"Unsupported action"},400);
  }catch(e){
    console.error(e);
    return reply({error:e instanceof Error?e.message:String(e)},500);
  }
});
