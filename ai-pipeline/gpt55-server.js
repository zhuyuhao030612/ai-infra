// gpt55-server.js v9 — SSE streaming + non-streaming, 会话上下文, 纯HTTP API
'use strict';
const {chromium}=require('playwright'),fs=require('fs/promises'),fss=require('fs'),path=require('path'),crypto=require('crypto'),http=require('http');

const DATA=process.env.GPT55_DATA||path.join(__dirname,'data');
const PROFILE=process.env.GPT55_PROFILE||path.join(DATA,'profile');
const TOKEN_FILE=path.join(DATA,'session-tokens.json');
const CHAT_URL=(process.env.GPT55_URL||'https://ai.nbai88.top/').replace(/\/$/,'');
const PORT=+process.env.PORT||3000;
const HEADLESS=process.env.GPT55_HEADLESS==='1';
const MODEL=process.env.GPT55_MODEL||'gpt-5-5-thinking';

let ctx,page,cookies=[],alive=false,sessionConvId=null;

const iso=()=>new Date().toISOString();
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const cookieHeader=()=>cookies.map(c=>`${c.name}=${c.value}`).join('; ');

// ── 浏览器 ──
async function startBrowser(){
  await fs.mkdir(PROFILE,{recursive:true});
  ctx=await chromium.launchPersistentContext(PROFILE,{headless:HEADLESS,viewport:null,args:['--no-sandbox','--disable-dev-shm-usage']});
  ctx.setDefaultTimeout(60000);
  page=ctx.pages()[0]||await ctx.newPage();
  await page.goto(CHAT_URL,{waitUntil:'domcontentloaded',timeout:60000}).catch(()=>{});
  sessionConvId=null;
  console.log('[browser] started');
}
async function refreshCookies(){
  if(!ctx||!page||page.isClosed())return;
  try{cookies=await ctx.cookies();fss.writeFileSync(TOKEN_FILE,JSON.stringify({cookies,updated:iso()},null,2));console.log('[cookies]',cookies.length)}catch(e){}
}
function loadSavedCookies(){try{let s=JSON.parse(fss.readFileSync(TOKEN_FILE,'utf8'));if(s.cookies?.length)cookies=s.cookies}catch{}}

// ── API ──
async function apiCall(endpoint,method,body){
  let url=CHAT_URL+endpoint;
  let headers={'Cookie':cookieHeader(),'Content-Type':'application/json; charset=utf-8','Accept':'*/*','Origin':CHAT_URL,'Referer':CHAT_URL};
  let bodyBytes=body?Buffer.from(JSON.stringify(body),'utf8'):undefined;
  let resp=await fetch(url,{method,headers,body:bodyBytes});
  let buf=await resp.arrayBuffer();
  let text=Buffer.from(buf).toString('utf8');
  if(!resp.ok)throw Error(`${resp.status}: ${text.substring(0,200)}`);
  try{return JSON.parse(text)}catch{return text}
}

// ── 统一 SSE 解析：按事件边界分块，提取 assistant 文本 ──
function parseSSE(text){
  let result='',convId=null;
  for(let event of text.split(/\n\n+/)){
    let lines=event.split(/\r?\n/);
    for(let line of lines){
      if(!line||!line.startsWith('data:'))continue;
      let json=line.startsWith('data: ')?line.slice(6):line.slice(5);
      if(!json||json==='[DONE]')continue;
      try{let d=JSON.parse(json);
        if(d.conversation_id)convId=d.conversation_id;
        // 流式追加
        if(d.o==='append'&&typeof d.v==='string'&&d.p?.includes('parts'))result+=d.v;
        // 完整 assistant 消息（add/replace/patch）
        let msg=d.v?.message||d.message;
        if(msg&&msg.author?.role==='assistant'&&msg.content?.parts&&msg.status!=='finished_successfully')continue;
        if(msg&&msg.author?.role==='assistant'&&msg.content?.parts){
          let p=msg.content.parts.filter(x=>typeof x==='string');if(p.length)result=p.join('');
        }
      }catch{}
    }
  }
  return{text:result.trim()||null,conversationId:convId};
}

// ── 流式发送（/ask/stream）──
async function streamChat(prompt,model,write){
  model=model||MODEL;
  prompt+='\n【重要：回复完成后必须在最后一行单独输出【完成】，否则我不会认为你回复完了】';
  let convId=null,fullText='',lastSent='';

  let prepBody={action:'next',fork_from_shared_post:false,parent_message_id:sessionConvId?'':('client-created-root'),model,client_prepare_state:'none',timezone_offset_min:-480,timezone:'Asia/Shanghai'};
  if(sessionConvId)prepBody.conversation_id=sessionConvId;
  try{let p=await apiCall('/backend-api/f/conversation/prepare','POST',prepBody);if(p?.conversation_id){sessionConvId=p.conversation_id;convId=p.conversation_id}}catch(e){console.log('[api] prepare:',e.message.substring(0,80))}

  let msgBody={action:'next',messages:[{id:crypto.randomUUID(),author:{role:'user'},create_time:Date.now()/1000,content:{content_type:'text',parts:[prompt]}}],model,timezone_offset_min:-480,timezone:'Asia/Shanghai'};
  if(sessionConvId)msgBody.conversation_id=sessionConvId;

  write({type:'status',state:'sending'});

  let url=CHAT_URL+'/backend-api/f/conversation';
  let headers={'Cookie':cookieHeader(),'Content-Type':'application/json; charset=utf-8','Accept':'text/event-stream','Origin':CHAT_URL,'Referer':CHAT_URL};
  let resp=await fetch(url,{method:'POST',headers,body:Buffer.from(JSON.stringify(msgBody),'utf8')});
  if(!resp.ok)throw Error(`${resp.status}: backend error`);

  let reader=resp.body.getReader();
  let decoder=new TextDecoder('utf-8');
  let buffer='',streamEnded=false;

  while(true){
    let{value,done}=await reader.read();
    if(value)buffer+=decoder.decode(value,{stream:!done});
    if(done)streamEnded=true;

    let events=buffer.split(/\n\n+/);
    buffer=events.pop()||'';

    for(let event of events){
      if(!event.trim())continue;
      let isDone=false;
      for(let line of event.split(/\r?\n/)){
        if(!line||!line.startsWith('data:'))continue;
        let json=line.startsWith('data: ')?line.slice(6):line.slice(5);
        if(!json||json==='[DONE]'){isDone=true;continue}
        try{let d=JSON.parse(json);
          if(d.conversation_id)convId=d.conversation_id;
          if(d.o==='append'&&typeof d.v==='string'&&d.p?.includes('parts'))fullText+=d.v;
          let msg=d.v?.message||d.message;
          if(msg&&msg.author?.role==='assistant'&&msg.content?.parts){let p=msg.content.parts.filter(x=>typeof x==='string');if(p.length)fullText=p.join('')}
        }catch{}
      }
      if(isDone){streamEnded=true;break}
    }

    if(fullText!==lastSent){
      let delta=fullText.slice(lastSent.length);
      if(delta)write({type:'token',text:delta});
      lastSent=fullText;
    }
    if(streamEnded)break;
  }

  if(convId)sessionConvId=convId;
  let final=(fullText||'').replace(/【完成】/g,'').replace(/【完$/,'').replace(/【$/,'').replace(/【成】/g,'').trim()||null;
  write({type:'done',text:final,conversationId:convId||sessionConvId});
  console.log('[api] streaming done:',(final||'').length,'chars');
  return{text:final,conversationId:convId||sessionConvId};
}

// ── 非流式 ──
async function chat(prompt,model){
  model=model||MODEL;
  prompt+='\n【重要：回复完成后必须在最后一行单独输出【完成】，否则我不会认为你回复完了】';
  let prepBody={action:'next',fork_from_shared_post:false,parent_message_id:sessionConvId?'':('client-created-root'),model,client_prepare_state:'none',timezone_offset_min:-480,timezone:'Asia/Shanghai'};
  if(sessionConvId)prepBody.conversation_id=sessionConvId;
  try{let p=await apiCall('/backend-api/f/conversation/prepare','POST',prepBody);if(p?.conversation_id)sessionConvId=p.conversation_id}catch(e){console.log('[api] prepare:',e.message.substring(0,80))}
  let msgBody={action:'next',messages:[{id:crypto.randomUUID(),author:{role:'user'},create_time:Date.now()/1000,content:{content_type:'text',parts:[prompt]}}],model,timezone_offset_min:-480,timezone:'Asia/Shanghai'};
  if(sessionConvId)msgBody.conversation_id=sessionConvId;
  let raw=await apiCall('/backend-api/f/conversation','POST',msgBody);
  let parsed=typeof raw==='string'?parseSSE(raw):{text:(raw?.message?.content?.parts?.filter(p=>typeof p==='string').join('')||null),conversationId:raw?.conversation_id||null};
  let text=parsed.text||(typeof raw==='string'?raw.substring(0,2000):JSON.stringify(raw).substring(0,2000));
  if(parsed.conversationId)sessionConvId=parsed.conversationId;
  console.log('[api]',text.length,'chars, conv:',sessionConvId||'new');
  return{text,conversationId:sessionConvId};
}

// ── Jobs ──
const jobs=new Map();
async function processJob(jobId,prompt,model){
  try{
    let result=await chat(prompt,model);
    jobs.set(jobId,{state:'succeeded',result:result.text,conversationId:result.conversationId,updated_at:iso()});
    if(result.conversationId&&page&&!page.isClosed())page.goto(CHAT_URL+'/c/'+result.conversationId,{waitUntil:'domcontentloaded',timeout:15000}).catch(()=>{});
  }catch(e){
    console.error('[job]',jobId,'failed:',e.message.substring(0,150));
    await refreshCookies();
    try{
      let result=await chat(prompt,model);
      jobs.set(jobId,{state:'succeeded',result:result.text,conversationId:result.conversationId,updated_at:iso()});
    }catch(e2){
      jobs.set(jobId,{state:'retryable_failed',error:{type:'api_error',message:e2.message},updated_at:iso()});
    }
  }
}
setInterval(()=>{let cutoff=Date.now()-600000;for(let[k,v]of jobs){if(new Date(v.updated_at).getTime()<cutoff)jobs.delete(k)}},300000);

// ── Server ──
const send=(res,c,o)=>{let data=Buffer.from(JSON.stringify(o),'utf8');res.writeHead(c,{'content-type':'application/json; charset=utf-8','content-length':data.length});res.end(data)};
const bodyParser=req=>new Promise((res,rej)=>{
  let chunks=[],len=0;
  req.on('data',d=>{chunks.push(d);len+=d.length;if(len>2e6)rej(Error('body_too_large'))});
  req.on('end',()=>{try{let s=Buffer.concat(chunks).toString('utf8');res(s?JSON.parse(s):{})}catch(e){rej(e)}});
  req.on('error',rej);
});

http.createServer(async(req,res)=>{
  try{
    let u=new URL(req.url,'http://x');
    if(req.method==='POST'&&u.pathname==='/ask/stream'){
      let b=await bodyParser(req),prompt=String(b.prompt||'').trim();
      if(!prompt)return send(res,400,{error:'missing prompt'});
      res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-cache','Connection':'keep-alive','X-Accel-Buffering':'no'});
      let write=(data)=>{res.write(`event: ${data.type}\ndata: ${JSON.stringify(data)}\n\n`)};
      try{let result=await streamChat(prompt,b.model||null,write);let jid=crypto.randomBytes(12).toString('hex');jobs.set(jid,{id:jid,state:'succeeded',result:result.text,updated_at:iso()})}catch(e){write({type:'error',message:e.message})}
      res.end();
      return;
    }
    if(req.method==='POST'&&u.pathname==='/ask'){
      let b=await bodyParser(req),prompt=String(b.prompt||'').trim();
      if(!prompt)return send(res,400,{error:'missing prompt'});
      let jobId=crypto.randomBytes(12).toString('hex');
      jobs.set(jobId,{id:jobId,state:'pending',created_at:iso()});
      processJob(jobId,prompt,b.model||null);
      return send(res,200,{id:jobId,state:'pending'});
    }
    if(req.method==='GET'&&u.pathname.startsWith('/job/')){
      let jid=u.pathname.split('/').pop(),j=jobs.get(jid);
      return send(res,j?200:404,j||{error:'not_found'});
    }
    if(req.method==='GET'&&u.pathname==='/health'){
      return send(res,200,{alive,busy:false,hasCookies:!!cookies.length,model:MODEL,sessionConvId:sessionConvId||null,activeJobs:jobs.size});
    }
    if(req.method==='GET'&&u.pathname==='/queue'){let m={};for(let[,v]of jobs){m[v.state]=(m[v.state]||0)+1}return send(res,200,{counts:m,total:jobs.size})}
    if(req.method==='POST'&&u.pathname==='/new-chat'){sessionConvId=null;if(page&&!page.isClosed())page.goto(CHAT_URL,{waitUntil:'domcontentloaded',timeout:15000}).catch(()=>{});return send(res,200,{ok:true})}
    if(req.method==='POST'&&u.pathname==='/refresh'){await refreshCookies();return send(res,200,{cookies:cookies.length})}
    send(res,404,{error:'not_found'});
  }catch(e){send(res,500,{error:e.message})}
}).listen(PORT,()=>console.log('[server] listening on',PORT));

(async()=>{
  loadSavedCookies();
  await startBrowser();
  await wait(3000);
  await refreshCookies();
  alive=true;
  setInterval(async()=>{try{await refreshCookies()}catch{}},1800000);
  console.log('[server] ready — model:',MODEL);
})();
