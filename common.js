/* Shared browser helpers. Never put a Supabase service-role key here. */
const cfg=window.GENZ_CONFIG||{};
if('serviceWorker' in navigator)navigator.serviceWorker.register('./sw.js').catch(()=>{});
const ready=cfg.supabaseUrl&&cfg.supabaseAnonKey&&!cfg.supabaseUrl.includes('PEGA_AQUI')&&!cfg.supabaseAnonKey.includes('PEGA_AQUI');
const db=ready?window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
const $=(s,r=document)=>r.querySelector(s);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=(n,c='USD')=>new Intl.NumberFormat('es',{style:'currency',currency:c,maximumFractionDigits:2}).format(Number(n||0));
const msg=(s,kind='')=>{const n=$('#notice');if(n){n.textContent=s;n.className='notice '+kind;n.hidden=false;}};
const clearMsg=()=>{const n=$('#notice');if(n){n.textContent='';n.hidden=true;}};
const errorText=e=>e?.message||'Ocurrió un error. Comprueba la conexión y vuelve a intentarlo.';
const authForm=()=>`<section class="panel narrow"><h1>Acceso al panel</h1><p>Entra con tu cuenta. No compartas tu contraseña.</p><form id="loginForm"><label>Correo<input name="email" type="email" autocomplete="username" required></label><label>Contraseña<input name="password" type="password" autocomplete="current-password" required></label><button class="primary">Entrar</button></form><p class="muted">¿Aún no tienes cuenta? <a href="manager.html">Gestores: crea tu cuenta aquí</a></p></section>`;
const signOut=async()=>{await db.auth.signOut();location.reload();};
const header=(subtitle='')=>`<header class="top"><a class="brand" href="./">Gen Z <span>TIENDA</span></a><div>${subtitle?`<span class="muted">${esc(subtitle)}</span>`:''}</div></header>`;
const moneyHint='Precios y saldos en la moneda configurada para la tienda.';
