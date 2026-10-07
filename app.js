const CFG = window.CAP_DRILL_CONFIG || {};
const configured = !!(CFG.supabaseUrl && CFG.supabaseAnonKey && !String(CFG.supabaseAnonKey).includes('PASTE_'));
const sb = configured ? window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey) : null;

let me = null;
let ctx = null;
let units = [];
let activities = [];
let tests = [];
let view = 'entry';
let testId = null;
let adminTab = 'members';
let editingRecord = null;
let recordLimit = 50;
let reportMember = 'all';
let reportTest = 'all';
let reportResult = 'all';
let reportStart = '';
let reportEnd = '';
let statsMode = 'officer';
const MAX_ROWS = 250;
const ANALYTICS_MAX = 5000;

const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const dateText = s => s ? new Date(s + 'T00:00:00').toLocaleDateString(undefined,{year:'numeric',month:'short',day:'numeric'}) : '';
const today = () => new Date().toISOString().slice(0,10);

function toast(message, bad=false){
  const t = $('#toast');
  t.textContent = message;
  t.style.background = bad ? '#852f2f' : '#173a56';
  t.classList.remove('hidden');
  clearTimeout(window.__toastTimer);
  window.__toastTimer = setTimeout(() => t.classList.add('hidden'), 3500);
}
function openModal(title, body, foot=''){
  $('#modalTitle').textContent = title;
  $('#modalBody').innerHTML = body;
  $('#modalFoot').innerHTML = foot || '<button class="btn btn-secondary" onclick="closeModal()">Close</button>';
  $('#modal').showModal();
}
function closeModal(){ try { $('#modal').close(); } catch {} }
function err(e){ console.error(e); toast(e?.message || String(e), true); }
async function rpc(name, args={}){
  const {data,error} = await sb.rpc(name,args);
  if(error) throw error;
  return data;
}

function uPerm(id){ return (ctx?.unitPermissions || []).find(p => p.unitId === id); }
function aPerm(id){ return (ctx?.activityPermissions || []).find(p => p.activityId === id); }
function canUnit(id, admin=false){
  const p=uPerm(id);
  return !!ctx?.appAdmin || (!!p && (admin ? p.unitAdmin : (p.dataEntry || p.unitAdmin)));
}
function canActivity(id, admin=false){
  const p=aPerm(id);
  return !!ctx?.appAdmin || (!!p && (admin ? p.activityAdmin : (p.dataEntry || p.activityAdmin)));
}
function unitAdminIds(){
  return ctx?.appAdmin ? units.map(u=>u.id) : (ctx?.unitPermissions || []).filter(p=>p.unitAdmin).map(p=>p.unitId);
}
function activityAdminIds(){
  return ctx?.appAdmin ? activities.map(a=>a.id) : (ctx?.activityPermissions || []).filter(p=>p.activityAdmin).map(p=>p.activityId);
}
function canAdmin(){
  return !!ctx && (ctx.appAdmin || ctx.manageActivities || unitAdminIds().length || activityAdminIds().length);
}
function scopeLabel(type,id){
  if(type==='unit'){
    const x=units.find(u=>u.id===id);
    return x ? `${x.charter_number || ''} — ${x.name}` : 'Unknown Unit';
  }
  const x=activities.find(a=>a.id===id);
  return x ? `${x.activity_type || 'Activity'} — ${x.name}` : 'Unknown Activity';
}
function scopes(){
  const out=[];
  if(ctx?.appAdmin){
    units.filter(x=>x.active).forEach(x=>out.push({type:'unit',id:x.id,label:scopeLabel('unit',x.id)}));
    activities.filter(x=>x.active).forEach(x=>out.push({type:'activity',id:x.id,label:scopeLabel('activity',x.id)}));
    return out.sort((a,b)=>a.label.localeCompare(b.label));
  }
  (ctx?.unitPermissions || []).filter(p=>p.dataEntry||p.unitAdmin).forEach(p=>{
    const x=units.find(u=>u.id===p.unitId); if(x?.active) out.push({type:'unit',id:x.id,label:scopeLabel('unit',x.id)});
  });
  (ctx?.activityPermissions || []).filter(p=>p.dataEntry||p.activityAdmin).forEach(p=>{
    const x=activities.find(a=>a.id===p.activityId); if(x?.active) out.push({type:'activity',id:x.id,label:scopeLabel('activity',x.id)});
  });
  return out.sort((a,b)=>a.label.localeCompare(b.label));
}
function currentScope(){
  const all=scopes();
  let type=ctx?.defaultScopeType;
  let id=type==='unit'?ctx?.defaultUnitId:ctx?.defaultActivityId;
  if(!all.some(x=>x.type===type&&x.id===id)){ type=all[0]?.type; id=all[0]?.id; }
  return {type,id};
}

async function publicSequences(){
  if(!configured){
    $('#configWarn').textContent='Before deployment, put your existing Supabase public/anon/publishable key in config.js.';
    $('#configWarn').classList.remove('hidden');
    $('#publicSeq').innerHTML='<div class="loading">Waiting for configuration.</div>';
    return;
  }
  const {data,error}=await sb.from('drill_public_sequences').select('*').order('display_order');
  if(error){ $('#publicSeq').innerHTML=`<div class="alert alert-danger">${esc(error.message)}</div>`; return; }
  const sel=$('#publicTest');
  sel.innerHTML=(data||[]).map(x=>`<option value="${x.id}">${esc(x.label)} — ${esc(x.topic)}</option>`).join('');
  const render=()=>{
    const t=(data||[]).find(x=>x.id===sel.value);
    $('#publicSeq').innerHTML=t
      ? `<div class="public-sequence-meta"><b>${esc(t.label)} — ${esc(t.topic)}</b><br>${esc(t.conditions||'')}</div>${(t.sequence||[]).map(s=>`<div class="public-seq-row ${/^\s*(--|—)/.test(String(s))?'ungraded':''}">${esc(s)}</div>`).join('')}`
      : '<div class="empty">No active sequences.</div>';
  };
  sel.onchange=render; render();
}

async function login(){
  try{
    $('#loginError').classList.add('hidden');
    if(!configured) throw new Error('Configure config.js first.');
    const {error}=await sb.auth.signInWithPassword({email:$('#loginEmail').value.trim(),password:$('#loginPassword').value});
    if(error) throw error;
  }catch(e){ $('#loginError').textContent=e.message; $('#loginError').classList.remove('hidden'); }
}
async function logout(){ if(sb) await sb.auth.signOut(); }

async function loadCore(){
  const {data:{user}}=await sb.auth.getUser();
  me=user; if(!user) return;
  ctx=await rpc('drill_get_my_context');
  let q=await sb.from('units').select('id,charter_number,name,active').order('charter_number');
  if(q.error) throw q.error; units=q.data||[];
  q=await sb.from('drill_activities').select('*').order('start_date',{ascending:false});
  if(q.error) throw q.error; activities=q.data||[];
  const td=await sb.from('drill_test_definitions').select('*').order('display_order');
  if(td.error) throw td.error;
  const ti=await sb.from('drill_test_items').select('*').eq('active',true).order('item_order');
  if(ti.error) throw ti.error;
  tests=(td.data||[]).map(t=>({...t,items:(ti.data||[]).filter(i=>i.test_id===t.id).map(i=>({id:i.item_key,command:i.command,standards:i.standards||[],points:i.points,group:i.group_label||''}))}));
  if(!tests.some(t=>t.id===testId)) testId=tests.find(t=>t.active)?.id||tests[0]?.id;
}
function renderHeader(){
  const cur=currentScope();
  $('#appName').textContent=CFG.appName||'CAP Drill Test Manager';
  $('#userName').textContent=ctx.displayName||me.email;
  $('#rolePill').textContent=ctx.appAdmin?'Application Admin':unitAdminIds().length?'Unit Admin':ctx.manageActivities?'Activity Manager':'Data Entry';
  $('#defaultScope').innerHTML=scopes().map(s=>`<option value="${s.type}:${s.id}" ${cur.type===s.type&&cur.id===s.id?'selected':''}>${esc(s.label)}</option>`).join('');
}
async function changeScope(v){
  const [type,id]=v.split(':');
  try{
    await rpc('drill_set_user_preference',{p_scope:type,p_id:id});
    ctx.defaultScopeType=type; ctx.defaultUnitId=type==='unit'?id:null; ctx.defaultActivityId=type==='activity'?id:null;
    recordLimit=50; reportMember='all'; reportTest='all'; reportResult='all'; reportStart=''; reportEnd=''; editingRecord=null;
    renderHeader(); navigate(view);
  }catch(e){err(e)}
}
function renderNav(){
  const n=[['entry','New Drill Test'],['dashboard','Dashboard'],['records','Records'],['reports','Reports'],['statistics','Statistics']];
  if(canAdmin()) n.push(['admin','Administration']);
  $('#mainnav').innerHTML=n.map(([id,l])=>`<button class="navbtn ${view===id?'active':''}" onclick="navigate('${id}')">${l}</button>`).join('');
}
function showApp(){
  $('#loginScreen').classList.add('hidden'); $('#app').classList.remove('hidden');
  renderHeader(); renderNav(); navigate('entry');
}
function navigate(v){
  view=v; renderNav();
  if(v!=='entry') editingRecord=null;
  if(v==='entry') renderEntry();
  else if(v==='dashboard') renderDashboard();
  else if(v==='records') renderRecords();
  else if(v==='reports') renderReports();
  else if(v==='statistics') renderStatistics();
  else if(v==='admin') renderAdmin();
}

function integratedRows(t,existing={}){
  const by=new Map(t.items.map((x,i)=>[String(x.id),[x,i]])),used=new Set(),rows=[];
  const graded=(it,idx)=>{
    if(t.scoring_mode==='points') return `<tr><td class="numcol">${esc(it.id)}</td><td class="command">${esc(it.command)}</td><td>${(it.standards||[]).map(x=>`<div class="standards">${esc(x)}</div>`).join('')}</td><td class="gradecell"><label class="points-check"><input class="scoreInput" data-id="${esc(it.id)}" type="checkbox" ${existing[it.id]===true?'checked':''} onchange="updateScore()"> Earn ${it.points||1} pt</label></td></tr>`;
    const val=existing[it.id];
    return `<tr><td class="numcol">${esc(it.id)}</td><td class="command">${esc(it.command)}</td><td>${(it.standards||[]).map(x=>`<div class="standards">${esc(x)}</div>`).join('')}</td><td class="gradecell"><div class="choice-row"><span class="choice"><input class="scoreInput" id="s_${idx}" name="g_${idx}" data-id="${esc(it.id)}" type="radio" value="S" ${val==='S'?'checked':''} onchange="updateScore()"><label class="good" for="s_${idx}">Satisfactory</label></span><span class="choice"><input class="scoreInput" id="u_${idx}" name="g_${idx}" data-id="${esc(it.id)}" type="radio" value="U" ${val==='U'?'checked':''} onchange="updateScore()"><label class="bad" for="u_${idx}">Unsatisfactory</label></span></div></td></tr>`;
  };
  const ungraded=line=>{
    let txt=String(line).replace(/^\s*(--|—)\s*/,'');
    let note='Sequence / setup command; not graded.';
    const m=txt.match(/\s*\[([^\]]+)\]\s*$/);
    if(m){ note=m[1]; txt=txt.slice(0,m.index).trim(); }
    return `<tr class="ungraded-row"><td class="numcol">--</td><td class="command">${esc(txt)}</td><td>${esc(note)}</td><td><span class="not-graded-label">Not graded</span></td></tr>`;
  };
  for(const line of (t.sequence||[])){
    if(/^\s*(--|—)/.test(String(line))){rows.push(ungraded(line));continue;}
    const m=String(line).match(/^\s*(\d+)\./);
    if(m&&by.has(m[1])&&!used.has(m[1])){const [it,i]=by.get(m[1]);rows.push(graded(it,i));used.add(m[1]);}
  }
  t.items.forEach((it,i)=>{if(!used.has(String(it.id)))rows.push(graded(it,i));});
  return rows.join('');
}

async function renderEntry(){
  const baseScope=currentScope();
  const editScope=editingRecord ? {type:editingRecord.evaluation_scope_type,id:editingRecord.evaluation_scope_type==='unit'?editingRecord.evaluation_unit_id:editingRecord.activity_id} : baseScope;
  if(!editScope.id) return $('#mainContent').innerHTML='<div class="panel"><div class="empty">You do not yet have a Drill unit/activity permission.</div></div>';
  if(editingRecord && tests.some(x=>x.id===editingRecord.test_definition_id)) testId=editingRecord.test_definition_id;
  const t=tests.find(x=>x.id===testId)||tests[0];
  let sug=[];
  if(editScope.type==='unit') try{sug=await rpc('drill_member_suggestions',{p_unit_id:editScope.id});}catch{}
  const availableScopes=scopes();
  if(!availableScopes.some(s=>s.type===editScope.type&&s.id===editScope.id) && editingRecord) availableScopes.push({type:editScope.type,id:editScope.id,label:scopeLabel(editScope.type,editScope.id)});
  $('#mainContent').innerHTML=`<div class="panel"><h2>${editingRecord?'Edit':'New'} Drill Test</h2>${editingRecord?'<div class="alert alert-warn">You are editing an existing historical record. Changes are audited.</div>':''}<div class="grid grid-3"><div class="field"><label>Evaluation Unit / Activity</label><select id="entryScope">${availableScopes.map(x=>`<option value="${x.type}:${x.id}" ${x.type===editScope.type&&x.id===editScope.id?'selected':''}>${esc(x.label)}</option>`).join('')}</select></div><div class="field"><label>Date</label><input id="entryDate" type="date" value="${esc(editingRecord?.test_date||today())}"></div><div class="field"><label>Testing Officer</label><input id="entryOfficer" value="${esc(editingRecord?.testing_officer_name||ctx.displayName||'')}"></div></div><div class="grid grid-3"><div class="field"><label>CAPID</label><input id="entryCapid" list="capids" inputmode="numeric" value="${esc(editingRecord?.capid_snapshot||'')}"><datalist id="capids">${sug.map(m=>`<option value="${esc(m.capid)}">${esc(m.last_name)}, ${esc(m.first_name)}</option>`).join('')}</datalist><div id="lookupStatus" class="lookup-status"></div></div><div class="field"><label>First Name</label><input id="entryFirst" value="${esc(editingRecord?.first_name_snapshot||'')}" disabled></div><div class="field"><label>Last Name</label><input id="entryLast" value="${esc(editingRecord?.last_name_snapshot||'')}" disabled></div></div><div id="newMember" class="hidden"><div class="grid grid-2"><div class="field"><label>New Cadet Home Unit</label><select id="entryHome">${units.filter(u=>u.active).map(u=>`<option value="${u.id}">${esc(u.charter_number)} — ${esc(u.name)}</option>`).join('')}</select></div><div class="alert alert-info">CAPID was not found. Enter the name and home unit; saving creates the shared member record.</div></div></div><div class="field"><label>Drill Test</label><select id="entryTest">${tests.filter(x=>x.active||x.id===editingRecord?.test_definition_id).map(x=>`<option value="${x.id}" ${x.id===t.id?'selected':''}>${esc(x.label)} — ${esc(x.topic)}</option>`).join('')}</select></div></div><div class="panel" id="scoreArea"></div>`;
  $('#entryCapid').onblur=lookupMember; $('#entryCapid').onchange=lookupMember;
  $('#entryTest').onchange=e=>{testId=e.target.value;scorecard();};
  $('#entryScope').onchange=e=>{ if(editingRecord){ const [ty,id]=e.target.value.split(':'); editingRecord.evaluation_scope_type=ty; editingRecord.evaluation_unit_id=ty==='unit'?id:null; editingRecord.activity_id=ty==='activity'?id:null; } else changeScope(e.target.value); };
  if(editingRecord) scorecard(editingRecord.results||{}); else scorecard();
}
async function lookupMember(){
  const capid=$('#entryCapid').value.trim(); if(!capid)return;
  try{
    const d=await rpc('drill_lookup_member',{p_capid:capid}); const m=Array.isArray(d)?d[0]:d;
    if(m){
      $('#entryFirst').value=m.first_name; $('#entryLast').value=m.last_name; $('#entryFirst').disabled=true; $('#entryLast').disabled=true; $('#newMember').classList.add('hidden');
      $('#lookupStatus').textContent=m.active?'Member found.':'Inactive member found — direct CAPID entry is still allowed.'; $('#lookupStatus').className='lookup-status lookup-ok';
      if($('#entryHome') && m.home_unit_id) $('#entryHome').value=m.home_unit_id;
    }else{
      $('#entryFirst').disabled=false; $('#entryLast').disabled=false; $('#entryFirst').value=''; $('#entryLast').value=''; $('#newMember').classList.remove('hidden');
      const sc=currentScope(); if(sc.type==='unit'&&$('#entryHome')) $('#entryHome').value=sc.id;
      $('#lookupStatus').textContent='CAPID not found. Enter name/home unit to create the member.'; $('#lookupStatus').className='lookup-status lookup-warn';
    }
  }catch(e){err(e)}
}
function scorecard(existing={}){
  const t=tests.find(x=>x.id===testId); if(!t)return;
  $('#scoreArea').innerHTML=`<div class="test-summary"><strong>${esc(t.label)} — ${esc(t.topic)}</strong><div class="meta"><div><b>Passing:</b> ${t.pass_required}/${t.max_score}</div><div><b>Source:</b> CAPP 60-34 pp. ${esc(t.source_page||'')}</div><div class="full"><b>Conditions:</b> ${esc(t.conditions||'')}</div></div></div><div class="alert alert-info">Ungraded drill sequence steps appear inline as <b>--</b> and intentionally have no Satisfactory/Unsatisfactory buttons.</div><div class="scorebar"><div><div id="scoreText" class="scorebig"></div><div id="completeText" class="small muted"></div></div><div id="scoreState" class="scorestatus"></div></div><div class="table-wrap"><table class="score-table"><thead><tr><th>#</th><th>Command / Item</th><th>Acceptable Standards / Sequence Note</th><th>Grade</th></tr></thead><tbody>${integratedRows(t,existing)}</tbody></table></div><div class="field"><label>Notes (optional)</label><textarea id="entryNotes">${esc(editingRecord?.notes||'')}</textarea></div><div class="form-actions">${editingRecord?'<button class="btn btn-ghost" onclick="editingRecord=null;navigate(\'records\')">Cancel Edit</button>':''}<button class="btn btn-secondary" onclick="saveRecord('draft')">Save Draft</button><button class="btn btn-primary" onclick="saveRecord('submitted')">Submit Test</button></div>`;
  updateScore();
}
function results(){
  const t=tests.find(x=>x.id===testId),o={};
  if(t.scoring_mode==='points') $$('.scoreInput[type=checkbox]').forEach(x=>o[x.dataset.id]=x.checked);
  else $$('.scoreInput[type=radio]:checked').forEach(x=>o[x.dataset.id]=x.value);
  return o;
}
function score(){
  const t=tests.find(x=>x.id===testId),r=results();
  if(t.scoring_mode==='points'){
    const n=t.items.reduce((s,i)=>s+(r[i.id]?Number(i.points||1):0),0);
    return {n,done:t.items.length,total:t.items.length,pass:n>=t.pass_required};
  }
  const n=t.items.filter(i=>r[i.id]==='S').length,done=t.items.filter(i=>r[i.id]==='S'||r[i.id]==='U').length;
  return {n,done,total:t.items.length,pass:n>=t.pass_required};
}
function updateScore(){
  const t=tests.find(x=>x.id===testId),s=score(); if(!$('#scoreText'))return;
  $('#scoreText').textContent=`${s.n} / ${t.max_score}`;
  $('#completeText').textContent=t.scoring_mode==='points'?`${s.n} points earned`:`${s.done} of ${s.total} graded items scored`;
  const complete=t.scoring_mode==='points'||s.done===s.total;
  $('#scoreState').textContent=s.pass?'Passing':complete?'Not Passing':'Incomplete';
  $('#scoreState').className='scorestatus '+(s.pass?'pass':complete?'fail':'');
}
async function saveRecord(status){
  const capid=$('#entryCapid').value.trim(),t=tests.find(x=>x.id===testId),s=score(),[scopeType,scopeId]=$('#entryScope').value.split(':');
  if(!capid)return toast('CAPID is required.',true);
  if(!$('#entryOfficer').value.trim())return toast('Testing Officer is required.',true);
  if(status==='submitted'&&t.scoring_mode==='su'&&s.done<s.total)return toast('Score every graded item before submitting.',true);
  try{
    await rpc('drill_save_record',{p:{recordId:editingRecord?.id||'',scopeType,unitId:scopeType==='unit'?scopeId:'',activityId:scopeType==='activity'?scopeId:'',capid,firstName:$('#entryFirst').value.trim(),lastName:$('#entryLast').value.trim(),homeUnitId:$('#entryHome')?.value||'',testId:t.id,testDate:$('#entryDate').value,testingOfficerName:$('#entryOfficer').value.trim(),testingOfficerUserId:'',status,score:s.n,results:results(),notes:$('#entryNotes').value.trim()}});
    editingRecord=null; toast(status==='submitted'?'Drill test submitted.':'Draft saved.'); navigate('records');
  }catch(e){err(e)}
}

function queryRecords(sc,submitted=false){
  let q=sb.from('drill_records').select('*',{count:'exact'}).order('test_date',{ascending:false}).order('submitted_at',{ascending:false,nullsFirst:false}).order('id',{ascending:false});
  if(submitted)q=q.eq('status','submitted');
  if(sc.type==='activity')q=q.eq('activity_id',sc.id); else q=q.or(`home_unit_id_at_evaluation.eq.${sc.id},evaluation_unit_id.eq.${sc.id}`);
  return q;
}

function querySubmittedQueue(sc){
  let q=sb.from('drill_records').select('*',{count:'exact'}).eq('status','submitted')
    .order('test_date',{ascending:true}).order('submitted_at',{ascending:true,nullsFirst:false}).order('id',{ascending:true});
  if(sc.type==='activity')q=q.eq('activity_id',sc.id); else q=q.or(`home_unit_id_at_evaluation.eq.${sc.id},evaluation_unit_id.eq.${sc.id}`);
  return q;
}
async function loadSubmittedForAnalysis(sc,max=ANALYTICS_MAX){
  const out=[],pageSize=500;
  for(let start=0;start<max;start+=pageSize){
    const end=Math.min(max-1,start+pageSize-1);
    const {data,error}=await queryRecords(sc,true).range(start,end);
    if(error)throw error;
    out.push(...(data||[]));
    if(!data||data.length<pageSize)break;
  }
  return out;
}
function recordMemberKey(r){return r.subject_member_id||('capid:'+String(r.capid_snapshot||''));}
function recordScorePct(r){return r.max_score?100*Number(r.raw_score||0)/Number(r.max_score):0;}
function passingStandard(r){
  const need=Number(r.pass_required_snapshot||0),max=Number(r.max_score||0);
  return max?`${need}/${max} (${Math.round(100*need/max)}%)`:`${need}`;
}
function reportMisses(rows){
  const map=new Map();
  for(const r of rows){
    const items=new Map((r.test_items_snapshot||[]).map(i=>[String(i.id??i.item_key??''),i]));
    for(const [itemId,value] of Object.entries(r.results||{})){
      const attempted=value==='S'||value==='U'||value===true||value===false;
      if(!attempted)continue;
      const item=items.get(String(itemId))||{};
      const command=item.command||('Item '+itemId);
      const key=[r.test_definition_id,itemId,command].join('|');
      const x=map.get(key)||{testId:r.test_definition_id,test:r.test_label_snapshot||r.test_code_snapshot||'Drill Test',itemId,command,attempts:0,misses:0};
      x.attempts++;
      if(value==='U'||value===false)x.misses++;
      map.set(key,x);
    }
  }
  return [...map.values()].filter(x=>x.misses>0).map(x=>({...x,rate:100*x.misses/x.attempts}))
    .sort((a,b)=>b.misses-a.misses||b.rate-a.rate||a.test.localeCompare(b.test));
}
function achievementReport(rows){
  const groups=new Map();
  for(const r of rows){
    const key=r.test_definition_id||r.test_label_snapshot;
    const g=groups.get(key)||{id:key,label:r.test_label_snapshot||r.test_code_snapshot||'Drill Test',rows:[]};
    g.rows.push(r);groups.set(key,g);
  }
  return [...groups.values()].map(g=>{
    const scores=g.rows.map(recordScorePct);
    const passes=g.rows.filter(r=>r.passed).length;
    const misses=reportMisses(g.rows);
    const first=g.rows[0];
    return {
      id:g.id,label:g.label,attempts:g.rows.length,passRate:g.rows.length?100*passes/g.rows.length:0,
      avg:mean(scores),min:scores.length?Math.min(...scores):0,max:scores.length?Math.max(...scores):0,
      standard:passingStandard(first),mostMissed:misses[0]?.command||'—',missCount:misses[0]?.misses||0
    };
  }).sort((a,b)=>a.label.localeCompare(b.label));
}
function monthlyTrend(rows,months=6){
  const now=new Date(),keys=[];
  for(let i=months-1;i>=0;i--){
    const d=new Date(now.getFullYear(),now.getMonth()-i,1);
    keys.push({key:`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`,label:d.toLocaleDateString(undefined,{month:'short',year:'2-digit'}),count:0,passes:0});
  }
  const by=new Map(keys.map(x=>[x.key,x]));
  for(const r of rows){
    const k=String(r.test_date||'').slice(0,7),x=by.get(k);
    if(x){x.count++;if(r.passed)x.passes++;}
  }
  return keys;
}
function trendBars(points){
  if(!points.some(x=>x.count))return '<div class="empty">No submitted drill tests in this period.</div>';
  const max=Math.max(1,...points.map(x=>x.count));
  return '<div class="trend-chart">'+points.map(x=>{
    const width=Math.max(2,Math.round(100*x.count/max));
    const rate=x.count?Math.round(100*x.passes/x.count):0;
    return '<div class="trend-row"><div class="trend-label">'+esc(x.label)+'</div><div class="trend-track"><div class="trend-fill" style="width:'+width+'%"></div></div><div class="trend-value"><b>'+x.count+'</b> <span class="small muted">'+rate+'% pass</span></div></div>';
  }).join('')+'</div>';
}
function queueTable(rows,startIndex=0){
  return `<div class="table-wrap"><table class="data-table mobile-card-table"><thead><tr><th>#</th><th>Date</th><th>Cadet</th><th>Drill Test</th><th>Score</th><th>Result</th><th>Testing Officer</th><th></th></tr></thead><tbody>${rows.map((r,i)=>`<tr><td data-label="#">${startIndex+i+1}</td><td data-label="Date">${dateText(r.test_date)}</td><td data-label="Cadet"><b>${esc(r.last_name_snapshot)}, ${esc(r.first_name_snapshot)}</b><br><span class="small muted">CAPID ${esc(r.capid_snapshot)}</span></td><td data-label="Drill Test">${esc(r.test_label_snapshot)}</td><td data-label="Score"><b>${r.raw_score}/${r.max_score}</b></td><td data-label="Result">${r.passed?'<span class="tag pass">PASS</span>':'<span class="tag fail">FAIL</span>'}</td><td data-label="Testing Officer">${esc(r.testing_officer_name)}</td><td><button class="btn btn-secondary btn-sm" onclick="viewRecord('${r.id}')">View</button></td></tr>`).join('')}</tbody></table></div>`;
}

function recordRow(r,actions=false){
  return `<tr><td data-label="Date">${dateText(r.test_date)}</td><td data-label="Cadet"><b>${esc(r.last_name_snapshot)}, ${esc(r.first_name_snapshot)}</b><br><span class="small muted">CAPID ${esc(r.capid_snapshot)}</span></td><td data-label="Test">${esc(r.test_label_snapshot)}</td><td data-label="Score"><b>${r.raw_score}/${r.max_score}</b></td><td data-label="Status">${r.status==='draft'?'<span class="tag draft">DRAFT</span>':r.passed?'<span class="tag pass">PASS</span>':'<span class="tag fail">FAIL</span>'}</td><td data-label="Testing Officer">${esc(r.testing_officer_name)}</td><td data-label="Evaluation Unit / Activity">${esc(r.evaluation_scope_type==='unit'?scopeLabel('unit',r.evaluation_unit_id):scopeLabel('activity',r.activity_id))}</td>${actions?`<td data-label="Actions"><button class="btn btn-secondary btn-sm" onclick="viewRecord('${r.id}')">View</button></td>`:''}</tr>`;
}
function table(rows,actions=false){
  return `<div class="table-wrap"><table class="data-table mobile-card-table"><thead><tr><th>Date</th><th>Cadet</th><th>Test</th><th>Score</th><th>Status</th><th>Testing Officer</th><th>Evaluation Unit / Activity</th>${actions?'<th></th>':''}</tr></thead><tbody>${rows.map(r=>recordRow(r,actions)).join('')}</tbody></table></div>`;
}
function controls(kind,shown,total,limit){
  if(total<=10)return'';
  return `<div class="list-controls"><div class="list-controls-left"><button class="btn btn-secondary btn-sm" onclick="${kind}More()" ${shown>=total?'disabled':''}>Show 10 More</button><button class="btn btn-ghost btn-sm" onclick="${kind}Reset()">Show First 10</button></div><div class="list-controls-right"><div class="field"><label>Rows to show</label><input id="${kind}Limit" type="number" min="1" max="${MAX_ROWS}" value="${limit}"></div><button class="btn btn-secondary btn-sm" onclick="${kind}Apply()">Apply</button></div></div>`;
}
async function renderDashboard(){
  const sc=currentScope(); $('#mainContent').innerHTML='<div class="panel loading">Loading dashboard…</div>';
  try{
    const [rawSummary,submitted]=await Promise.all([
      rpc('drill_dashboard_summary',{p_scope:sc.type,p_id:sc.id}),
      loadSubmittedForAnalysis(sc)
    ]);
    const sum=Array.isArray(rawSummary)?rawSummary[0]:rawSummary;
    const total=Number(sum?.submitted_count||submitted.length||0);
    const passing=Number(sum?.passing_count||submitted.filter(r=>r.passed).length||0);
    const passRate=total?Math.round(100*passing/total):0;
    const cutoff=new Date();cutoff.setDate(cutoff.getDate()-30);
    const recent30=submitted.filter(r=>r.test_date&&new Date(r.test_date+'T00:00:00')>=cutoff).length;
    const ach=achievementReport(submitted).sort((a,b)=>b.attempts-a.attempts).slice(0,6);
    const recent=submitted.slice(0,5);
    const drafts=Number(sum?.draft_count||0);

    $('#mainContent').innerHTML=`
      <div class="panel">
        <h2>Dashboard — ${esc(scopeLabel(sc.type,sc.id))}</h2>
        <p class="sub">Quick operational picture of drill testing. Use Records for the eServices work list and Reports for detailed analysis.</p>
        <div class="cards">
          <div class="metric"><div class="num">${total}</div><div class="label">Submitted Tests</div></div>
          <div class="metric"><div class="num">${recent30}</div><div class="label">Tests in Last 30 Days</div></div>
          <div class="metric"><div class="num">${passRate}%</div><div class="label">Overall Pass Rate</div></div>
          <div class="metric"><div class="num">${sum?.cadets_tested||0}</div><div class="label">Cadets Tested</div></div>
        </div>
        ${drafts?`<div class="alert alert-warn" style="margin-top:14px"><b>${drafts} draft${drafts===1?'':'s'}</b> currently exist in this scope and have not been submitted.</div>`:''}
      </div>
      <div class="grid grid-2">
        <div class="panel">
          <h2>Tests Given — Last 6 Months</h2>
          <p class="sub">Submitted drill tests by test date.</p>
          ${trendBars(monthlyTrend(submitted,6))}
        </div>
        <div class="panel">
          <h2>Achievement Snapshot</h2>
          <p class="sub">Most frequently tested achievements in the selected scope.</p>
          ${ach.length?`<div class="table-wrap"><table class="data-table" style="min-width:520px"><thead><tr><th>Achievement</th><th>Tests</th><th>Pass Rate</th><th>Avg Score</th></tr></thead><tbody>${ach.map(a=>`<tr><td><b>${esc(a.label)}</b></td><td>${a.attempts}</td><td>${a.passRate.toFixed(0)}%</td><td>${a.avg.toFixed(1)}%</td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">No submitted drill tests yet.</div>'}
        </div>
      </div>
      <div class="panel">
        <h2>Most Recent Submitted Tests</h2>
        ${recent.length?table(recent,false):'<div class="empty">No submitted drill tests yet.</div>'}
      </div>`;
  }catch(e){err(e)}
}
async function renderRecords(){
  const sc=currentScope(); $('#mainContent').innerHTML='<div class="panel loading">Loading eServices work list…</div>';
  try{
    const {data,error,count}=await querySubmittedQueue(sc).range(0,Math.min(recordLimit,ANALYTICS_MAX)-1); if(error)throw error;
    const rows=data||[];
    $('#mainContent').innerHTML=`
      <div class="panel">
        <h2>Records — eServices Entry List</h2>
        <p class="sub">Submitted drill tests for ${esc(scopeLabel(sc.type,sc.id))}, in chronological order (oldest first). This is the work list for entering completed drill tests into eServices. Drafts are not shown.</p>
        <div class="alert alert-info"><b>${count||0} submitted test${count===1?'':'s'}</b> in this list. Work from top to bottom for a simple sequential entry workflow.</div>
        ${rows.length?queueTable(rows):'<div class="empty">No submitted drill tests yet.</div>'}
        ${(count||0)>rows.length?`<div class="form-actions"><button class="btn btn-secondary" onclick="recordLimit=Math.min(${ANALYTICS_MAX},recordLimit+50);renderRecords()">Show 50 More</button></div>`:''}
      </div>`;
  }catch(e){err(e)}
}
async function renderReports(){
  const sc=currentScope(); $('#mainContent').innerHTML='<div class="panel loading">Building reports…</div>';
  try{
    const all=await loadSubmittedForAnalysis(sc);
    const members=new Map();
    for(const r of all){
      const key=recordMemberKey(r);
      if(!members.has(key))members.set(key,{key,capid:r.capid_snapshot||'',first:r.first_name_snapshot||'',last:r.last_name_snapshot||''});
    }
    const memberList=[...members.values()].sort((a,b)=>(a.last+', '+a.first).localeCompare(b.last+', '+b.first));
    const testList=[...new Map(all.map(r=>[r.test_definition_id,{id:r.test_definition_id,label:r.test_label_snapshot||r.test_code_snapshot||'Drill Test'}])).values()].sort((a,b)=>a.label.localeCompare(b.label));

    let rows=all.slice();
    if(reportMember!=='all')rows=rows.filter(r=>recordMemberKey(r)===reportMember);
    if(reportTest!=='all')rows=rows.filter(r=>r.test_definition_id===reportTest);
    if(reportResult==='pass')rows=rows.filter(r=>r.passed);
    if(reportResult==='fail')rows=rows.filter(r=>!r.passed);
    if(reportStart)rows=rows.filter(r=>r.test_date>=reportStart);
    if(reportEnd)rows=rows.filter(r=>r.test_date<=reportEnd);

    const passes=rows.filter(r=>r.passed).length;
    const uniqueMembers=new Set(rows.map(recordMemberKey)).size;
    const avg=rows.length?mean(rows.map(recordScorePct)):0;
    const ach=achievementReport(rows);
    const misses=reportMisses(rows).slice(0,15);

    const memberGroups=new Map();
    for(const r of rows){
      const k=recordMemberKey(r),g=memberGroups.get(k)||{key:k,capid:r.capid_snapshot||'',first:r.first_name_snapshot||'',last:r.last_name_snapshot||'',rows:[]};
      g.rows.push(r);memberGroups.set(k,g);
    }
    const memberSummary=[...memberGroups.values()].map(g=>{
      const p=g.rows.filter(r=>r.passed).length;
      return {...g,count:g.rows.length,passRate:g.rows.length?100*p/g.rows.length:0,last:g.rows.map(r=>r.test_date).sort().reverse()[0]||''};
    }).sort((a,b)=>(a.last+', '+a.first).localeCompare(b.last+', '+b.first));

    const selectedMember=reportMember!=='all'?members.get(reportMember):null;
    const historyHtml=selectedMember
      ? (rows.length?table(rows,true):'<div class="empty">No records match the selected filters for this member.</div>')
      : (memberSummary.length?`<div class="table-wrap"><table class="data-table"><thead><tr><th>Member</th><th>CAPID</th><th>Tests</th><th>Pass Rate</th><th>Most Recent</th></tr></thead><tbody>${memberSummary.map(m=>`<tr><td><b>${esc(m.last)}, ${esc(m.first)}</b></td><td>${esc(m.capid)}</td><td>${m.count}</td><td>${m.passRate.toFixed(1)}%</td><td>${dateText(m.last)}</td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">No member history matches these filters.</div>');

    $('#mainContent').innerHTML=`
      <div class="panel">
        <h2>Reports & Drill Analysis — ${esc(scopeLabel(sc.type,sc.id))}</h2>
        <p class="sub">Review individual member history, achievement performance, scoring trends, and commands that are most often marked unsatisfactory.</p>
        <div class="grid grid-3">
          <div class="field"><label>Member</label><select id="reportMember"><option value="all">All members</option>${memberList.map(m=>`<option value="${esc(m.key)}" ${reportMember===m.key?'selected':''}>${esc(m.last)}, ${esc(m.first)} — ${esc(m.capid)}</option>`).join('')}</select></div>
          <div class="field"><label>Achievement / Drill Test</label><select id="reportTest"><option value="all">All drill tests</option>${testList.map(t=>`<option value="${t.id}" ${reportTest===t.id?'selected':''}>${esc(t.label)}</option>`).join('')}</select></div>
          <div class="field"><label>Result</label><select id="reportResult"><option value="all" ${reportResult==='all'?'selected':''}>All results</option><option value="pass" ${reportResult==='pass'?'selected':''}>Passing only</option><option value="fail" ${reportResult==='fail'?'selected':''}>Not passing only</option></select></div>
        </div>
        <div class="grid grid-3">
          <div class="field"><label>From Date</label><input id="reportStart" type="date" value="${esc(reportStart)}"></div>
          <div class="field"><label>Through Date</label><input id="reportEnd" type="date" value="${esc(reportEnd)}"></div>
          <div class="form-actions" style="justify-content:flex-start;align-items:end"><button class="btn btn-primary" onclick="applyReportFilters()">Run Report</button><button class="btn btn-secondary" onclick="clearReportFilters()">Clear</button></div>
        </div>
        <div class="cards">
          <div class="metric"><div class="num">${rows.length}</div><div class="label">Tests in Report</div></div>
          <div class="metric"><div class="num">${rows.length?(100*passes/rows.length).toFixed(1):'0.0'}%</div><div class="label">Pass Rate</div></div>
          <div class="metric"><div class="num">${uniqueMembers}</div><div class="label">Members Tested</div></div>
          <div class="metric"><div class="num">${avg.toFixed(1)}%</div><div class="label">Average Score</div></div>
        </div>
      </div>

      <div class="panel">
        <h2>${selectedMember?`Drill History — ${esc(selectedMember.first)} ${esc(selectedMember.last)}`:'Member Drill History'}</h2>
        <p class="sub">${selectedMember?'Chronological record of this member’s submitted drill tests within the selected filters.':'Select a member above for their detailed drill history, or use this summary to compare activity across members.'}</p>
        ${historyHtml}
      </div>

      <div class="panel">
        <h2>Achievement Performance</h2>
        <p class="sub">Passing standard, observed score range, pass rate, and the command most often missed for each drill test.</p>
        ${ach.length?`<div class="table-wrap"><table class="data-table"><thead><tr><th>Achievement</th><th>Tests</th><th>Passing Standard</th><th>Pass Rate</th><th>Average Score</th><th>Observed Range</th><th>Most Missed Command</th></tr></thead><tbody>${ach.map(a=>`<tr><td><b>${esc(a.label)}</b></td><td>${a.attempts}</td><td>${esc(a.standard)}</td><td>${a.passRate.toFixed(1)}%</td><td>${a.avg.toFixed(1)}%</td><td>${a.min.toFixed(1)}–${a.max.toFixed(1)}%</td><td>${esc(a.mostMissed)}${a.missCount?` <span class="small muted">(${a.missCount} miss${a.missCount===1?'':'es'})</span>`:''}</td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">No achievement data matches these filters.</div>'}
      </div>

      <div class="panel">
        <h2>Most Missed Commands</h2>
        <p class="sub">Unsatisfactory S/U items and unearned point items, ranked by number of misses. Attempt count is shown so a high percentage from a tiny sample is easy to spot.</p>
        ${misses.length?`<div class="table-wrap"><table class="data-table"><thead><tr><th>Achievement</th><th>Command / Item</th><th>Misses</th><th>Attempts</th><th>Miss Rate</th></tr></thead><tbody>${misses.map(m=>`<tr><td>${esc(m.test)}</td><td><b>${esc(m.command)}</b></td><td>${m.misses}</td><td>${m.attempts}</td><td>${m.rate.toFixed(1)}%</td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">No unsatisfactory / missed commands appear in the selected records.</div>'}
      </div>`;
  }catch(e){err(e)}
}
function applyReportFilters(){
  reportMember=$('#reportMember')?.value||'all';
  reportTest=$('#reportTest')?.value||'all';
  reportResult=$('#reportResult')?.value||'all';
  reportStart=$('#reportStart')?.value||'';
  reportEnd=$('#reportEnd')?.value||'';
  renderReports();
}
function clearReportFilters(){
  reportMember='all';reportTest='all';reportResult='all';reportStart='';reportEnd='';renderReports();
}
async function viewRecord(id){
  try{
    const {data,error}=await sb.from('drill_records').select('*').eq('id',id).single(); if(error)throw error;
    let canEdit=false; try{canEdit=!!(await rpc('can_edit_drill_record',{p_id:id}));}catch{}
    const itemMap=new Map((data.test_items_snapshot||[]).map(i=>[String(i.id),i]));
    const resultRows=Object.entries(data.results||{}).map(([k,v])=>{const it=itemMap.get(k);return `<tr><td>${esc(k)}</td><td>${esc(it?.command||'')}</td><td>${v===true?'Earned':v===false?'Not earned':esc(v)}</td></tr>`}).join('');
    openModal('Drill Test Record',`<div class="grid grid-3"><div><b>Cadet</b><br>${esc(data.first_name_snapshot)} ${esc(data.last_name_snapshot)}<br>CAPID ${esc(data.capid_snapshot)}</div><div><b>${esc(data.test_label_snapshot)}</b><br>${esc(data.test_topic_snapshot||'')}</div><div><b>${dateText(data.test_date)}</b><br>${data.passed?'PASS':'FAIL'} — ${data.raw_score}/${data.max_score}</div></div><div class="section-title">Testing Officer</div><div>${esc(data.testing_officer_name)}</div>${resultRows?`<div class="section-title">Scoring</div><div class="table-wrap"><table class="data-table"><thead><tr><th>#</th><th>Item</th><th>Result</th></tr></thead><tbody>${resultRows}</tbody></table></div>`:''}${data.notes?`<div class="section-title">Notes</div><div>${esc(data.notes)}</div>`:''}`,`${canEdit?`<button class="btn btn-primary" onclick="editRecord('${id}')">Edit Record</button>`:''}<button class="btn btn-secondary" onclick="closeModal()">Close</button>`);
  }catch(e){err(e)}
}
async function editRecord(id){
  try{
    const {data,error}=await sb.from('drill_records').select('*').eq('id',id).single(); if(error)throw error;
    const allowed=await rpc('can_edit_drill_record',{p_id:id}); if(!allowed)throw new Error('You are not authorized to edit this record.');
    editingRecord=data; testId=data.test_definition_id; closeModal(); view='entry'; renderNav(); renderEntry();
  }catch(e){err(e)}
}

function mean(a){return a.length?a.reduce((x,y)=>x+y,0)/a.length:0;}
function variance(a,m){return a.length<2?0:a.reduce((s,x)=>s+(x-m)**2,0)/(a.length-1);}
// Numerical Recipes-style incomplete beta implementation for the Student-t CDF.
function logGamma(z){const c=[676.5203681218851,-1259.1392167224028,771.3234287776531,-176.6150291621406,12.507343278686905,-0.13857109526572012,9.984369578019572e-6,1.5056327351493116e-7];if(z<0.5)return Math.log(Math.PI)-Math.log(Math.sin(Math.PI*z))-logGamma(1-z);z-=1;let x=0.9999999999998099;for(let i=0;i<c.length;i++)x+=c[i]/(z+i+1);const t=z+c.length-0.5;return 0.5*Math.log(2*Math.PI)+(z+0.5)*Math.log(t)-t+Math.log(x);}
function betaCf(a,b,x){const MAX=200,EPS=3e-12,FPMIN=1e-300;let qab=a+b,qap=a+1,qam=a-1,c=1,d=1-qab*x/qap;if(Math.abs(d)<FPMIN)d=FPMIN;d=1/d;let h=d;for(let m=1;m<=MAX;m++){const m2=2*m;let aa=m*(b-m)*x/((qam+m2)*(a+m2));d=1+aa*d;if(Math.abs(d)<FPMIN)d=FPMIN;c=1+aa/c;if(Math.abs(c)<FPMIN)c=FPMIN;d=1/d;h*=d*c;aa=-(a+m)*(qab+m)*x/((a+m2)*(qap+m2));d=1+aa*d;if(Math.abs(d)<FPMIN)d=FPMIN;c=1+aa/c;if(Math.abs(c)<FPMIN)c=FPMIN;d=1/d;const del=d*c;h*=del;if(Math.abs(del-1)<EPS)break;}return h;}
function betaI(a,b,x){if(x<=0)return 0;if(x>=1)return 1;const bt=Math.exp(logGamma(a+b)-logGamma(a)-logGamma(b)+a*Math.log(x)+b*Math.log(1-x));return x<(a+1)/(a+b+2)?bt*betaCf(a,b,x)/a:1-bt*betaCf(b,a,1-x)/b;}
function tTwoTailP(t,df){if(!Number.isFinite(t)||!Number.isFinite(df)||df<=0)return NaN;const x=df/(df+t*t);return Math.max(0,Math.min(1,betaI(df/2,0.5,x)));}
function welch(a,b){const ma=mean(a),mb=mean(b),va=variance(a,ma),vb=variance(b,mb),sa=va/a.length,sb=vb/b.length,se=Math.sqrt(sa+sb);if(!se)return 1;const t=Math.abs((ma-mb)/se),den=(sa*sa)/(a.length-1)+(sb*sb)/(b.length-1),df=den?((sa+sb)*(sa+sb))/den:Math.max(1,a.length+b.length-2);return tTwoTailP(t,df);}
function bh(ps){const a=ps.map((p,i)=>({p,i})).sort((x,y)=>x.p-y.p),q=Array(ps.length);let prev=1;for(let j=a.length-1;j>=0;j--){prev=Math.min(prev,a[j].p*a.length/(j+1));q[a[j].i]=prev;}return q;}
async function renderStatistics(){
  const sc=currentScope(); $('#mainContent').innerHTML='<div class="panel loading">Loading statistics…</div>';
  try{
    const {data,error,count}=await queryRecords(sc,true).range(0,4999); if(error)throw error;
    const names=await rpc('drill_user_names_for_visible_records'); const nameMap=new Map((names||[]).map(x=>[x.user_id,x.display_name]));
    const testGroups={};
    for(const r of data){const pct=r.max_score?100*r.raw_score/r.max_score:0;(testGroups[r.test_definition_id]??=[]).push(pct);}
    const testMean=Object.fromEntries(Object.entries(testGroups).map(([k,v])=>[k,mean(v)]));
    const map={};
    for(const r of data){
      const pct=r.max_score?100*r.raw_score/r.max_score:0;
      const key=statsMode==='submitter'?(nameMap.get(r.created_by_user_id)||'Unknown Submitter'):(r.testing_officer_name||'Unknown Testing Officer');
      (map[key]??=[]).push({pct,adj:pct-(testMean[r.test_definition_id]||0),pass:r.passed});
    }
    const groups=Object.entries(map).map(([name,vals])=>({name,n:vals.length,meanPct:mean(vals.map(v=>v.pct)),passRate:100*vals.filter(v=>v.pass).length/vals.length,meanAdj:mean(vals.map(v=>v.adj)),adj:vals.map(v=>v.adj)})).sort((a,b)=>a.meanAdj-b.meanAdj);
    const pairs=[];
    for(let i=0;i<groups.length;i++)for(let j=i+1;j<groups.length;j++){const A=groups[i],B=groups[j];pairs.push({A,B,p:A.n>=10&&B.n>=10?welch(A.adj,B.adj):NaN,d:A.meanAdj-B.meanAdj});}
    const qs=bh(pairs.map(x=>Number.isFinite(x.p)?x.p:1)); pairs.forEach((x,i)=>x.q=Number.isFinite(x.p)?qs[i]:NaN);
    $('#mainContent').innerHTML=`<div class="panel"><div style="display:flex;justify-content:space-between;gap:12px;align-items:end;flex-wrap:wrap"><div><h2>Fairness & Evaluator Statistics — ${esc(scopeLabel(sc.type,sc.id))}</h2><p class="sub">Exploratory comparisons intended to identify possible scoring patterns that deserve human review.</p></div><div class="field" style="margin:0;min-width:240px"><label>Analyze records by</label><select id="statsMode"><option value="officer" ${statsMode==='officer'?'selected':''}>Testing Officer</option><option value="submitter" ${statsMode==='submitter'?'selected':''}>Record Submitter</option></select></div></div><div class="alert alert-warn"><b>Oversight tool, not a misconduct finding.</b> Differences may reflect cadet experience, achievement mix, retests, scheduling, or assignment effects. Pairwise comparisons are suppressed below 10 records per person; samples below 30 are flagged small.</div>${count>5000?'<div class="alert alert-warn">More than 5,000 records exist; this screen analyzes the newest 5,000.</div>':''}<div class="alert alert-info"><b>Adjusted Score Difference</b> subtracts the selected unit/activity average for the same drill test before comparing people. This partially adjusts for different achievements and point scales.</div><div class="table-wrap"><table class="data-table"><thead><tr><th>${statsMode==='submitter'?'Submitter':'Testing Officer'}</th><th>Records</th><th>Mean Score</th><th>Pass Rate</th><th>Adjusted Difference</th><th>Sample</th></tr></thead><tbody>${groups.map(g=>`<tr><td>${esc(g.name)}</td><td>${g.n}</td><td>${g.meanPct.toFixed(1)}%</td><td>${g.passRate.toFixed(1)}%</td><td>${g.meanAdj>=0?'+':''}${g.meanAdj.toFixed(1)} pts</td><td>${g.n<10?'<span class="tag fail">TOO SMALL</span>':g.n<30?'<span class="tag draft">SMALL SAMPLE</span>':'<span class="tag pass">ADEQUATE</span>'}</td></tr>`).join('')}</tbody></table></div><div class="section-title">Pairwise Welch Tests + Benjamini-Hochberg False-Discovery-Rate Correction</div><div class="table-wrap"><table class="data-table"><thead><tr><th>A</th><th>B</th><th>N</th><th>Adjusted A − B</th><th>Interpretation</th></tr></thead><tbody>${pairs.map(p=>`<tr><td>${esc(p.A.name)}</td><td>${esc(p.B.name)}</td><td>${p.A.n}/${p.B.n}</td><td>${p.d>=0?'+':''}${p.d.toFixed(1)} pts</td><td>${Number.isFinite(p.q)?p.q<.05?`<span class="tag fail">STATISTICAL SIGNAL</span><br><span class="small">q=${p.q.toFixed(4)} — review underlying records and assignments manually.</span>`:`<span class="tag pass">NO SIGNAL</span><br><span class="small">q=${p.q.toFixed(4)}</span>`:'<span class="tag">NOT TESTED</span><br><span class="small">Need at least 10 records from each person.</span>'}</td></tr>`).join('')}</tbody></table></div></div>`;
    $('#statsMode').onchange=e=>{statsMode=e.target.value;renderStatistics();};
  }catch(e){err(e)}
}

async function renderAdmin(){
  if(!canAdmin()) return navigate('entry');
  const tabs=[];
  if(ctx.appAdmin||unitAdminIds().length) tabs.push(['members','Member List'],['users','Users & Permissions']);
  if(ctx.appAdmin) tabs.push(['units','Units']);
  if(ctx.appAdmin||ctx.manageActivities||activityAdminIds().length) tabs.push(['activities','Other Activities']);
  if(ctx.appAdmin) tabs.push(['tests','Drill Tests']);
  if(!tabs.some(x=>x[0]===adminTab)) adminTab=tabs[0]?.[0]||'';
  $('#mainContent').innerHTML=`<div class="panel"><h2>Administration</h2><p class="sub">Manage Drill Test Manager data and permissions without going into Supabase.</p><div class="admin-tabs">${tabs.map(([id,l])=>`<button class="admin-tab ${adminTab===id?'active':''}" onclick="adminTab='${id}';renderAdmin()">${l}</button>`).join('')}</div><div id="adminBody"><div class="loading">Loading…</div></div></div>`;
  if(adminTab==='members') adminMembers();
  else if(adminTab==='users') adminUsers();
  else if(adminTab==='units') adminUnits();
  else if(adminTab==='activities') adminActivities();
  else if(adminTab==='tests') adminTests();
}

async function adminMembers(){
  const ids=unitAdminIds(); if(!ids.length) return $('#adminBody').innerHTML='<div class="empty">No unit administration permissions.</div>';
  const unitId=(window.__memberAdminUnit&&ids.includes(window.__memberAdminUnit))?window.__memberAdminUnit:ids[0]; window.__memberAdminUnit=unitId;
  const status=window.__memberStatus||'active';
  const {data,error}=await sb.from('member_unit_assignments').select('member_id,unit_id,members(id,capid,first_name,last_name,active,member_type)').eq('unit_id',unitId).eq('active',true).eq('is_primary',true);
  if(error)return err(error);
  const rows=(data||[]).filter(x=>status==='all'||(status==='active'?x.members?.active:x.members?.active===false)).sort((a,b)=>(a.members?.last_name||'').localeCompare(b.members?.last_name||''));
  $('#adminBody').innerHTML=`<div class="grid grid-2"><div class="field"><label>Member List Unit</label><select id="memberAdminUnit">${ids.map(id=>`<option value="${id}" ${id===unitId?'selected':''}>${esc(scopeLabel('unit',id))}</option>`).join('')}</select></div><div class="field"><label>Member Status</label><select id="memberStatus"><option value="active" ${status==='active'?'selected':''}>Active</option><option value="inactive" ${status==='inactive'?'selected':''}>Inactive</option><option value="all" ${status==='all'?'selected':''}>All</option></select></div></div><div class="form-actions" style="justify-content:flex-start"><button class="btn btn-primary" onclick="editMember('', '${unitId}')">Add Member</button></div><div class="table-wrap"><table class="data-table"><thead><tr><th>CAPID</th><th>Name</th><th>Type</th><th>Status</th><th></th></tr></thead><tbody>${rows.map(x=>{const m=x.members;return `<tr><td>${esc(m.capid)}</td><td>${esc(m.last_name)}, ${esc(m.first_name)}</td><td>${esc(m.member_type)}</td><td>${m.active?'<span class="tag pass">ACTIVE</span>':'<span class="tag">INACTIVE</span>'}</td><td><button class="btn btn-secondary btn-sm" onclick="editMember('${m.id}','${unitId}')">Edit</button></td></tr>`}).join('')}</tbody></table></div>`;
  $('#memberAdminUnit').onchange=e=>{window.__memberAdminUnit=e.target.value;adminMembers();};
  $('#memberStatus').onchange=e=>{window.__memberStatus=e.target.value;adminMembers();};
}
async function editMember(id,unitId){
  let m={id:'',capid:'',first_name:'',last_name:'',active:true};
  if(id){const {data,error}=await sb.from('members').select('*').eq('id',id).single();if(error)return err(error);m=data;}
  openModal(id?'Edit Member':'Add Member',`<div class="grid grid-2"><div class="field"><label>CAPID</label><input id="mCapid" value="${esc(m.capid||'')}"></div><div class="field"><label>Home Unit</label><select id="mUnit">${unitAdminIds().map(x=>`<option value="${x}" ${x===unitId?'selected':''}>${esc(scopeLabel('unit',x))}</option>`).join('')}</select></div><div class="field"><label>First Name</label><input id="mFirst" value="${esc(m.first_name||'')}"></div><div class="field"><label>Last Name</label><input id="mLast" value="${esc(m.last_name||'')}"></div></div><div class="check-card"><label><input id="mActive" type="checkbox" ${m.active?'checked':''}> Active member</label><small>Inactive members remain in history and can still be evaluated by typing their CAPID.</small></div>`,`<button class="btn btn-primary" onclick="saveMemberAdmin('${id}')">Save Member</button>`);
}
async function saveMemberAdmin(id){
  try{await rpc('drill_upsert_member',{p_member:id||null,p_capid:$('#mCapid').value.trim(),p_first:$('#mFirst').value.trim(),p_last:$('#mLast').value.trim(),p_home:$('#mUnit').value,p_active:$('#mActive').checked});closeModal();adminMembers();toast('Member saved.');}catch(e){err(e)}
}


function drillAuditUser(id,rows){
  const u=(rows||[]).find(x=>x.user_id===id);
  if(u)return '<b>'+esc(u.display_name||u.email||'CAP User')+'</b>'+(u.email?'<br><span class="small muted">'+esc(u.email)+'</span>':'');
  return id?'<span class="small muted">User '+esc(String(id).slice(0,8))+'…</span>':'—';
}
function drillAuditWhen(value){
  return new Date(value).toLocaleString([],{month:'numeric',day:'numeric',year:'2-digit',hour:'numeric',minute:'2-digit'});
}
function drillAuditAction(a){
  if(a.action==='SET_HOME_UNIT')return 'Home unit set';
  if(a.action==='GRANT_OR_UPDATE'&&a.entity_type==='unit_permission')return 'Unit access updated';
  if(a.action==='GRANT_OR_UPDATE'&&a.entity_type==='activity_permission')return 'Activity access updated';
  if(a.action==='REVOKE'&&a.entity_type==='unit_permission')return 'Unit access revoked';
  if(a.action==='REVOKE'&&a.entity_type==='activity_permission')return 'Activity access revoked';
  if(a.action==='UPDATE'&&a.entity_type==='global_permission')return 'App permissions updated';
  if(a.action==='CREATE_AUTH_USER')return 'Shared account created';
  if(a.action==='AUTHORIZE_DRILL_USER'||a.action==='LINK_AUTH_USER')return 'Drill user authorized';
  return String(a.action||'Updated').replaceAll('_',' ').toLowerCase().replace(/^./,c=>c.toUpperCase());
}
function drillAuditScope(a){
  if(a.unit_id)return esc(scopeLabel('unit',a.unit_id));
  if(a.activity_id)return esc(scopeLabel('activity',a.activity_id));
  if(a.entity_type==='global_permission'||a.entity_type==='user')return 'Application';
  return '—';
}
function drillAuditDetails(a){
  const d=a.details||{};
  if(a.entity_type==='global_permission'){
    const parts=[];
    if(d.app_admin)parts.push('App Admin');
    if(d.manage_activities)parts.push('Manage Activities');
    return parts.length?parts.map(x=>'<span class="tag admin">'+esc(x)+'</span>').join(' '):'<span class="small muted">No application-wide permissions</span>';
  }
  if(a.entity_type==='unit_permission'){
    if(a.action==='REVOKE')return '<span class="small">'+esc(d.reason||'Unit access removed')+'</span>';
    const role=d.unit_admin?'Unit Admin':d.data_entry?'Data Entry':'No unit access';
    const exp=d.expires_at?' · Expires '+esc(new Date(d.expires_at).toLocaleDateString()):'';
    return '<span class="tag">'+esc(role)+'</span><span class="small muted">'+exp+'</span>';
  }
  if(a.entity_type==='activity_permission'){
    if(a.action==='REVOKE')return '<span class="small">'+esc(d.reason||'Activity access removed')+'</span>';
    const role=d.activity_admin?'Activity Admin':d.data_entry?'Data Entry':'No activity access';
    const exp=d.expires_at?' · Expires '+esc(new Date(d.expires_at).toLocaleDateString()):'';
    return '<span class="tag">'+esc(role)+'</span><span class="small muted">'+exp+'</span>';
  }
  if(a.entity_type==='drill_user_settings'){
    const oldLabel=d.old_home_unit?scopeLabel('unit',d.old_home_unit):'Not set';
    const newLabel=d.new_home_unit?scopeLabel('unit',d.new_home_unit):'Not set';
    return '<span class="small">'+esc(oldLabel)+' → <b>'+esc(newLabel)+'</b></span>';
  }
  if(a.entity_type==='user')return '<span class="small">Shared CAP Applications login authorized for Drill</span>';
  if(d.reason)return '<span class="small">'+esc(d.reason)+'</span>';
  return '<span class="small muted">—</span>';
}

async function adminUsers(){
  try{
    const rows=await rpc('drill_admin_directory');
    const audit=await rpc('drill_permission_audit');
    const {data:unitPerms,error:upe}=await sb.from('drill_unit_permissions').select('*'); if(upe)throw upe;
    $('#adminBody').innerHTML=`<div class="form-actions" style="justify-content:flex-start"><button class="btn btn-primary" onclick="newUser()">Add / Authorize User</button>${unitAdminIds().length?'<button class="btn btn-secondary" onclick="grantVisitor()">Grant Temporary Cross-Unit Access</button>':''}</div><div class="table-wrap"><table class="data-table"><thead><tr><th>User</th><th>Home Unit</th><th>Permissions</th><th></th></tr></thead><tbody>${rows.map(u=>{const ps=(unitPerms||[]).filter(p=>p.user_id===u.user_id&&!p.revoked_at&&(!p.expires_at||new Date(p.expires_at)>=new Date()));return `<tr><td><b>${esc(u.display_name)}</b><br><span class="small muted">${esc(u.email)}</span></td><td>${u.home_unit_id?esc(scopeLabel('unit',u.home_unit_id)):'<span class="tag draft">HOME UNIT NOT SET</span><br><span class="small muted">Assign a Drill Home Unit before adding unit permissions.</span>'}</td><td>${u.is_app_admin?'<span class="tag admin">APP ADMIN</span> ':''}${u.manage_activities?'<span class="tag admin">CREATE ACTIVITIES</span> ':''}${ps.map(p=>`<span class="tag">${esc(scopeLabel('unit',p.unit_id))}: ${p.unit_admin?'Unit Admin':'Data Entry'}${p.expires_at?` • exp ${new Date(p.expires_at).toLocaleDateString()}`:''}</span>`).join(' ')||'—'}</td><td><button class="btn btn-secondary btn-sm" onclick="manageUser('${u.user_id}','${u.home_unit_id||''}')">Manage</button></td></tr>`}).join('')}</tbody></table></div><div class="section-title">Recent Permission Audit</div><div class="table-wrap"><table class="data-table"><thead><tr><th>Time</th><th>User</th><th>Change</th><th>Scope</th><th>Details</th></tr></thead><tbody>${(audit||[]).slice(0,40).map(a=>'<tr><td style="white-space:nowrap">'+drillAuditWhen(a.created_at)+'</td><td>'+drillAuditUser(a.target_user_id,rows)+'</td><td><b>'+esc(drillAuditAction(a))+'</b></td><td>'+drillAuditScope(a)+'</td><td>'+drillAuditDetails(a)+'</td></tr>').join('')}</tbody></table></div>`;
  }catch(e){err(e)}
}
function newUser(){
  const allowed=ctx.appAdmin?units.filter(u=>u.active):units.filter(u=>u.active&&unitAdminIds().includes(u.id));
  openModal('Add / Authorize Drill User',`<div class="field"><label>Display Name</label><input id="nuName"></div><div class="field"><label>Email / Login</label><input id="nuEmail" type="email"></div><div class="field"><label>Initial Password</label><input id="nuPass" type="password"><div class="small muted">Required only when this email is a brand-new shared CAP Applications account.</div></div><div class="field"><label>Drill Home Unit</label><select id="nuHome">${allowed.map(u=>`<option value="${u.id}">${esc(u.charter_number)} — ${esc(u.name)}</option>`).join('')}</select></div><div class="alert alert-info">Drill Home Unit is permission metadata for this login. It is separate from the CAPID/member record used for people taking drill tests.</div>`,`<button class="btn btn-primary" onclick="saveNewUser()">Save Drill User</button>`);
}
async function saveNewUser(){
  try{
    const displayName=$('#nuName').value.trim(),email=$('#nuEmail').value.trim(),homeUnitId=$('#nuHome').value;
    if(!displayName||!email||!homeUnitId)return toast('Display name, email, and Drill Home Unit are required.',true);
    const {data,error}=await sb.functions.invoke(CFG.adminFunctionName||'drill-admin-users',{body:{action:'ensure_user',email,password:$('#nuPass').value,displayName,homeUnitId}});
    if(error)throw error;if(data?.error)throw new Error(data.error);closeModal();adminUsers();toast(data.created?'Shared account created and authorized for Drill.':'Existing shared account authorized for Drill.');
  }catch(e){err(e)}
}
async function manageUser(userId,homeUnit){
  try{
    const {data:unitPerms,error:e1}=await sb.from('drill_unit_permissions').select('*').eq('user_id',userId);if(e1)throw e1;
    let activityPerms=[]; if(ctx.appAdmin){const r=await sb.from('drill_activity_permissions').select('*').eq('user_id',userId);if(r.error)throw r.error;activityPerms=r.data||[];}
    const editable=unitAdminIds();
    window.__managedUser={userId,homeUnit,unitPerms:unitPerms||[],activityPerms};
    const localRows=editable.map(id=>{const p=(unitPerms||[]).find(x=>x.unit_id===id&&!x.revoked_at);return `<tr><td><b>${esc(scopeLabel('unit',id))}</b></td><td><input class="permEntry" data-unit="${id}" type="checkbox" ${p?.data_entry||p?.unit_admin?'checked':''}></td><td><input class="permAdmin" data-unit="${id}" type="checkbox" ${p?.unit_admin?'checked':''}></td></tr>`}).join('');
    const foreign=(unitPerms||[]).filter(p=>!editable.includes(p.unit_id)&&!p.revoked_at&&(!p.expires_at||new Date(p.expires_at)>=new Date()));
    const homeHtml=ctx.appAdmin?`<div class="field"><label>Drill Home Unit</label><select id="muHomeUnit"><option value="">Not set</option>${units.filter(u=>u.active).map(u=>`<option value="${u.id}" ${u.id===homeUnit?'selected':''}>${esc(u.charter_number)} — ${esc(u.name)}</option>`).join('')}</select><small>Used only for Drill permission ownership and borrowed-access rules.</small></div>`:`<div class="alert alert-info"><b>Drill Home Unit:</b> ${homeUnit?esc(scopeLabel('unit',homeUnit)):'Not set'}</div>`;
    const linkNotice=!homeUnit?`<div class="alert alert-warn"><b>Choose a Drill Home Unit before assigning unit permissions.</b> This is separate from CAPID/member records.</div>`:'';
    const globalHtml=ctx.appAdmin?`<div class="section-title">Application-Wide Permissions</div><div class="check-card"><label><input id="muAppAdmin" type="checkbox"> Drill Application Administrator</label><small>Full control of this Drill application.</small></div><div class="check-card"><label><input id="muManageActivities" type="checkbox"> Create / Manage Other Activities</label><small>Allows creation of encampments, wing drills, cadet-program activities, etc.</small></div>`:'';
    const activityHtml=ctx.appAdmin?`<div class="section-title">Other Activity Permissions</div><div class="table-wrap"><table class="data-table"><thead><tr><th>Activity</th><th>Data Entry</th><th>Activity Admin</th></tr></thead><tbody>${activities.map(a=>{const p=activityPerms.find(x=>x.activity_id===a.id&&!x.revoked_at);return `<tr><td>${esc(scopeLabel('activity',a.id))}</td><td><input class="actEntry" data-activity="${a.id}" type="checkbox" ${p?.data_entry||p?.activity_admin?'checked':''}></td><td><input class="actAdmin" data-activity="${a.id}" type="checkbox" ${p?.activity_admin?'checked':''}></td></tr>`}).join('')}</tbody></table></div>`:'';
    openModal('Manage User Permissions',`<div class="alert alert-info">You can grant or change permissions only for units you administer. A user's Drill Home Unit controls which home Unit Admin may revoke borrowed access.</div>${homeHtml}${linkNotice}${globalHtml}<div class="section-title">My Unit Permissions</div><div class="table-wrap"><table class="data-table"><thead><tr><th>Unit</th><th>Data Entry</th><th>Unit Admin</th></tr></thead><tbody>${localRows||'<tr><td colspan="3">No unit-admin scopes.</td></tr>'}</tbody></table></div>${foreign.length?`<div class="section-title">Foreign / Borrowed Permissions</div>${foreign.map(p=>`<div class="check-card"><b>${esc(scopeLabel('unit',p.unit_id))}</b> — ${p.unit_admin?'Unit Admin':'Data Entry'}${p.expires_at?` — expires ${new Date(p.expires_at).toLocaleString()}`:''}${homeUnit&&p.unit_id!==homeUnit?` <button class="btn btn-danger btn-sm" onclick="revokeBorrowed('${userId}','${p.unit_id}')">Revoke</button>`:''}</div>`).join('')}`:''}${activityHtml}`,`<button class="btn btn-primary" onclick="saveManagedUser()">Save Permissions</button>`);
    if(ctx.appAdmin){
      const row=(await rpc('drill_admin_directory')).find(x=>x.user_id===userId); if(row){$('#muAppAdmin').checked=!!row.is_app_admin;$('#muManageActivities').checked=!!row.manage_activities;}
    }
  }catch(e){err(e)}
}
async function saveManagedUser(){
  const m=window.__managedUser;if(!m)return;
  try{
    if(ctx.appAdmin){
      const selectedHome=$('#muHomeUnit')?.value||'';
      if(selectedHome!==(m.homeUnit||'')){
        await rpc('drill_set_user_home_unit',{p_user:m.userId,p_home:selectedHome||null});
        m.homeUnit=selectedHome;
      }
    }
    for(const id of unitAdminIds()){
      const entry=$(`.permEntry[data-unit="${id}"]`)?.checked||false,admin=$(`.permAdmin[data-unit="${id}"]`)?.checked||false;
      const old=m.unitPerms.find(x=>x.unit_id===id&&!x.revoked_at);
      if((entry||admin)&&!m.homeUnit)throw new Error('Choose a Drill Home Unit before assigning unit permissions.');
      if(entry||admin) await rpc('drill_set_unit_permission',{p_user:m.userId,p_unit:id,p_entry:entry,p_admin:admin,p_expires:null,p_note:'Managed through Drill Test Manager'});
      else if(old) await rpc('drill_revoke_unit_access',{p_user:m.userId,p_unit:id,p_reason:'Removed by Unit/Application Admin'});
    }
    if(ctx.appAdmin){
      // Save activity permissions before global roles so an App Admin who intentionally
      // removes their own App Admin flag does not lose authorization halfway through this save.
      for(const a of activities){
        const entry=$(`.actEntry[data-activity="${a.id}"]`)?.checked||false,admin=$(`.actAdmin[data-activity="${a.id}"]`)?.checked||false;
        const old=m.activityPerms.find(x=>x.activity_id===a.id&&!x.revoked_at);
        if(entry||admin) await rpc('drill_set_activity_permission',{p_user:m.userId,p_activity:a.id,p_entry:entry,p_admin:admin,p_expires:null,p_note:'Managed through Drill Test Manager'});
        else if(old) await rpc('drill_revoke_activity_access',{p_user:m.userId,p_activity:a.id,p_reason:'Removed by Application Admin'});
      }
      await rpc('drill_set_global_permissions',{p_user:m.userId,p_app:$('#muAppAdmin').checked,p_manage:$('#muManageActivities').checked});
    }
    closeModal();await loadCore();renderHeader();adminUsers();toast('Permissions saved.');
  }catch(e){err(e)}
}
function grantVisitor(){
  openModal('Grant Temporary Cross-Unit Access',`<div class="field"><label>Host Unit</label><select id="gvUnit">${unitAdminIds().map(id=>`<option value="${id}">${esc(scopeLabel('unit',id))}</option>`).join('')}</select></div><div class="field"><label>Visitor Email</label><input id="gvEmail" type="email"></div><div class="field"><label>Expiration</label><select id="gvDuration"><option value="tonight">Tonight</option><option value="7">7 days</option><option value="30">30 days</option><option value="custom">Custom Date / Time</option><option value="none">No expiration</option></select></div><div id="gvCustomWrap" class="field hidden"><label>Custom expiration</label><input id="gvCustom" type="datetime-local"></div><div class="field"><label>Note</label><input id="gvNote" value="Cross-unit drill testing"></div><div class="small muted">Cross-unit grants made by a Unit Admin are Data Entry only. The visitor's home Unit Admin can revoke them later.</div>`,`<button class="btn btn-primary" onclick="saveVisitorGrant()">Grant Data Entry</button>`);
  $('#gvDuration').onchange=e=>$('#gvCustomWrap').classList.toggle('hidden',e.target.value!=='custom');
}
async function saveVisitorGrant(){
  try{
    const host=$('#gvUnit').value,email=$('#gvEmail').value.trim();
    const rr=await rpc('drill_find_user_for_host_grant',{p_email:email,p_host_unit:host}),u=Array.isArray(rr)?rr[0]:rr;
    if(!u)return toast('No Drill user with a Home Unit was found for that email. Assign the shared login a Drill Home Unit first.',true);
    let exp=null,d=$('#gvDuration').value;
    if(d==='tonight'){const x=new Date();x.setHours(23,59,59,999);exp=x.toISOString();}
    else if(d==='7'||d==='30'){const x=new Date();x.setDate(x.getDate()+Number(d));exp=x.toISOString();}
    else if(d==='custom'){if(!$('#gvCustom').value)return toast('Choose the custom expiration date/time.',true);exp=new Date($('#gvCustom').value).toISOString();}
    await rpc('drill_grant_temporary_unit_access',{p_user:u.user_id,p_unit:host,p_expires:exp,p_note:$('#gvNote').value.trim()});
    closeModal();adminUsers();toast(`Temporary access granted to ${u.display_name}.`);
  }catch(e){err(e)}
}
async function revokeBorrowed(userId,unitId){
  if(!confirm('Revoke this borrowed permission?'))return;
  try{await rpc('drill_revoke_unit_access',{p_user:userId,p_unit:unitId,p_reason:'Revoked by home-unit administrator'});closeModal();adminUsers();toast('Borrowed permission revoked.');}catch(e){err(e)}
}

function adminUnits(){
  $('#adminBody').innerHTML=`<div class="form-actions" style="justify-content:flex-start"><button class="btn btn-primary" onclick="editUnit()">Add Unit</button></div><div class="table-wrap"><table class="data-table"><thead><tr><th>Charter</th><th>Name</th><th>Status</th><th></th></tr></thead><tbody>${units.map(u=>`<tr><td>${esc(u.charter_number)}</td><td>${esc(u.name)}</td><td>${u.active?'<span class="tag pass">ACTIVE</span>':'<span class="tag">INACTIVE</span>'}</td><td><button class="btn btn-secondary btn-sm" onclick="editUnit('${u.id}')">Edit</button></td></tr>`).join('')}</tbody></table></div>`;
}
function editUnit(id=''){
  const u=units.find(x=>x.id===id)||{charter_number:'',name:'',active:true};
  openModal(id?'Edit Unit':'Add Unit',`<div class="grid grid-2"><div class="field"><label>Charter</label><input id="euCharter" value="${esc(u.charter_number||'')}"></div><div class="field"><label>Name</label><input id="euName" value="${esc(u.name||'')}"></div></div><div class="check-card"><label><input id="euActive" type="checkbox" ${u.active?'checked':''}> Active</label></div>`,`<button class="btn btn-primary" onclick="saveUnit('${id}')">Save Unit</button>`);
}
async function saveUnit(id){
  try{await rpc('drill_upsert_unit',{p_id:id||null,p_charter:$('#euCharter').value,p_name:$('#euName').value,p_active:$('#euActive').checked});closeModal();await loadCore();renderHeader();adminUnits();toast('Unit saved.');}catch(e){err(e)}
}

function adminActivities(){
  const manageable=ctx.appAdmin||ctx.manageActivities?activities:activities.filter(a=>canActivity(a.id,true));
  $('#adminBody').innerHTML=`<div class="form-actions" style="justify-content:flex-start">${ctx.appAdmin||ctx.manageActivities?'<button class="btn btn-primary" onclick="editActivity()">Add Activity</button>':''}</div><div class="table-wrap"><table class="data-table"><thead><tr><th>Type</th><th>Name</th><th>Location</th><th>Dates</th><th>Status</th><th></th></tr></thead><tbody>${manageable.map(a=>`<tr><td>${esc(a.activity_type)}</td><td><b>${esc(a.name)}</b></td><td>${esc(a.location)}</td><td>${dateText(a.start_date)} – ${dateText(a.end_date)}</td><td>${a.active?'<span class="tag pass">ACTIVE</span>':'<span class="tag">INACTIVE</span>'}</td><td><button class="btn btn-secondary btn-sm" onclick="editActivity('${a.id}')">Edit</button></td></tr>`).join('')}</tbody></table></div>`;
}
function editActivity(id=''){
  const a=activities.find(x=>x.id===id)||{activity_type:'Cadet Program Activity',name:'',location:'',start_date:'',end_date:'',active:true};
  openModal(id?'Edit Activity':'Add Other Activity',`<div class="grid grid-2"><div class="field"><label>Type</label><input id="eaType" value="${esc(a.activity_type)}" list="actTypes"><datalist id="actTypes"><option value="Encampment"><option value="Wing Drill"><option value="Cadet Program Activity"><option value="Wing Conference"><option value="Training Activity"><option value="Other"></datalist></div><div class="field"><label>Name</label><input id="eaName" value="${esc(a.name)}"></div><div class="field"><label>Location</label><input id="eaLocation" value="${esc(a.location)}"></div><div class="field"><label>Start</label><input id="eaStart" type="date" value="${esc(a.start_date)}"></div><div class="field"><label>End</label><input id="eaEnd" type="date" value="${esc(a.end_date)}"></div></div><div class="check-card"><label><input id="eaActive" type="checkbox" ${a.active?'checked':''}> Active / available for new tests</label></div>`,`<button class="btn btn-primary" onclick="saveActivity('${id}')">Save Activity</button>`);
}
async function saveActivity(id){
  try{await rpc('drill_save_activity',{p_id:id||null,p_type:$('#eaType').value,p_name:$('#eaName').value,p_location:$('#eaLocation').value,p_start:$('#eaStart').value,p_end:$('#eaEnd').value,p_active:$('#eaActive').checked});closeModal();await loadCore();renderHeader();adminActivities();toast('Activity saved.');}catch(e){err(e)}
}

function adminTests(){
  $('#adminBody').innerHTML=`<div class="form-actions" style="justify-content:flex-start"><button class="btn btn-primary" onclick="editTest()">Add Test</button></div><div class="table-wrap"><table class="data-table"><thead><tr><th>Code</th><th>Test</th><th>Scoring</th><th>Pass</th><th>Status</th><th></th></tr></thead><tbody>${tests.map(t=>`<tr><td>${esc(t.code)}</td><td><b>${esc(t.label)}</b><br><span class="small muted">${esc(t.topic)}</span></td><td>${t.scoring_mode==='points'?'Points':'S/U'}</td><td>${t.pass_required}/${t.max_score}</td><td>${t.active?'<span class="tag pass">ACTIVE</span>':'<span class="tag">INACTIVE</span>'}</td><td><button class="btn btn-secondary btn-sm" onclick="editTest('${t.id}')">Edit</button></td></tr>`).join('')}</tbody></table></div>`;
}
function editTest(id=''){
  const t=id?tests.find(x=>x.id===id):{id:'',code:'',label:'',topic:'',conditions:'',scoring_mode:'su',pass_required:1,max_score:1,source_page:'',sequence:[],active:true,display_order:100,items:[]};
  window.__editTest=JSON.parse(JSON.stringify(t));
  openModal(id?'Edit Drill Test':'Add Drill Test',`<div class="grid grid-3"><div class="field"><label>Code</label><input id="etCode" value="${esc(t.code)}"></div><div class="field"><label>Label</label><input id="etLabel" value="${esc(t.label)}"></div><div class="field"><label>Source Pages</label><input id="etPage" value="${esc(t.source_page||'')}"></div></div><div class="field"><label>Topic</label><input id="etTopic" value="${esc(t.topic)}"></div><div class="field"><label>Conditions</label><textarea id="etConditions">${esc(t.conditions)}</textarea></div><div class="grid grid-3"><div class="field"><label>Mode</label><select id="etMode"><option value="su" ${t.scoring_mode==='su'?'selected':''}>S/U</option><option value="points" ${t.scoring_mode==='points'?'selected':''}>Points</option></select></div><div class="field"><label>Passing Score</label><input id="etPass" type="number" value="${t.pass_required}"></div><div class="field"><label>Maximum Score</label><input id="etMax" type="number" value="${t.max_score}"></div></div><div class="check-card"><label><input id="etActive" type="checkbox" ${t.active?'checked':''}> Active / available for new tests</label></div><div class="section-title">Graded Items</div><div class="small muted">Advanced editor: JSON array. Each item uses id, command, standards[], points, and optional group.</div><textarea id="etItems" style="min-height:260px">${esc(JSON.stringify(t.items,null,2))}</textarea><div class="section-title">Command Sequence / Reference</div><textarea id="etSequence" style="min-height:200px">${esc((t.sequence||[]).join('\n'))}</textarea><div class="small muted">One command per line. Prefix ungraded steps with an em dash (—) or two hyphens (--).</div>`,`<button class="btn btn-primary" onclick="saveTest('${id}')">Save Test Definition</button>`);
}
async function saveTest(id){
  try{
    const items=JSON.parse($('#etItems').value); if(!Array.isArray(items)||!items.length)throw new Error('At least one graded item is required.');
    const payload={id:id||null,code:$('#etCode').value.trim(),label:$('#etLabel').value.trim(),topic:$('#etTopic').value.trim(),conditions:$('#etConditions').value.trim(),scoringMode:$('#etMode').value,passRequired:Number($('#etPass').value),maxScore:Number($('#etMax').value),sourcePage:$('#etPage').value.trim(),sequence:$('#etSequence').value.split(/\n+/).map(x=>x.trim()).filter(Boolean),active:$('#etActive').checked,displayOrder:window.__editTest?.display_order||100,items};
    await rpc('drill_save_test_definition',{p:payload}); closeModal(); await loadCore(); adminTests(); toast('Drill test definition saved.');
  }catch(e){err(e)}
}

$('#loginBtn').onclick=login;
$('#loginPassword').onkeydown=e=>{if(e.key==='Enter')login();};
$('#logoutBtn').onclick=logout;
$('#defaultScope').onchange=e=>changeScope(e.target.value);

if(sb){
  sb.auth.onAuthStateChange(async (_event,session)=>{
    if(session?.user){
      try{await loadCore();showApp();}catch(e){err(e);}
    }else{
      me=null;ctx=null;$('#app').classList.add('hidden');$('#loginScreen').classList.remove('hidden');
    }
  });
}
publicSequences();
if('serviceWorker' in navigator && location.protocol==='https:') navigator.serviceWorker.register('./service-worker.js').catch(console.warn);
