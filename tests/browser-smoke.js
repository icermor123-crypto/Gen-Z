// Pruebas de interacción con DOM mínimo y Supabase simulado. No prueban la base real.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const file=fs.readFileSync('store.html','utf8');
const scripts=[...file.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(x=>x[1]).filter(x=>x.trim());
assert.equal(scripts.length,1);
let html='',handlers={},calls=[];const session=new Map();
let product={id:'123',name:'Micrófono',description:'Prueba',category:'Audio',sku:'A1',stock:3,price:13,base_price:null,image_url:''};
const app={set innerHTML(v){html=v},get innerHTML(){return html},addEventListener(type,fn){handlers[type]=fn}};
const elements={'#app':app,'meta[name="description"]':{},'#searchProducts':{focus(){},setSelectionRange(){}}};
const store={slug:'demo',name:'Gen Z',description:'Tienda',whatsapp:'5355000000',currency:'USD',pickup_address:'Dirección',opening_hours:'9-5',delivery_enabled:true,delivery_fee:2,delivery_zones:'Marianao',delivery_eta:'24 horas'};
const db={async rpc(name,p){calls.push({name,p});if(name==='gz_public_catalog')return{data:{store,manager:{name:'Ana',slug:'ana'},products:[product]},error:null};if(name==='gz_place_order')return{data:{order_code:'PRUEBA01',customer_total:15,products_total:13,delivery_fee:2,currency:'USD',whatsapp:'5355000000'},error:null};throw Error(name)}};
const sandbox={console,Map,Set,Number,String,JSON,Math,Date,URLSearchParams,encodeURIComponent,crypto:{randomUUID:()=> 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'},location:{search:'?store=demo&ref=ana'},window:{GENZ_CONFIG:{}},sessionStorage:{getItem:k=>session.get(k)||null,setItem:(k,v)=>session.set(k,v),removeItem:k=>session.delete(k)},FormData:class{constructor(form){this.data=form.data} get(k){return this.data[k]??null}},document:{title:'',createElement(){return {}}},ready:true,db,header:()=>'<header>Gen Z</header>',errorText:e=>e.message,$:selector=>elements[selector]||null,esc:x=>String(x??''),money:(x,c)=>`${c} ${Number(x).toFixed(2)}`,globalThis:null};sandbox.globalThis=sandbox;
(async()=>{vm.runInNewContext(scripts[0],sandbox,{timeout:1000});await new Promise(r=>setTimeout(r,10));assert(html.includes('Micrófono'),'muestra producto');assert(html.includes('Ana'),'muestra gestor');
handlers.click({target:{closest:()=>({dataset:{add:'123'}})}});assert(html.includes('Tu pedido'),'agregar muestra carrito');assert(html.includes('USD 13.00'),'subtotal');
handlers.change({target:{name:'fulfillment',value:'delivery'}});assert(html.includes('Dirección de entrega'),'domicilio pide dirección');assert(html.includes('USD 15.00'),'incluye costo de entrega');
const checkout={id:'checkout',data:{name:'Cliente prueba',phone:'5355112233',address:'Calle 1 número 2',note:''}};
await handlers.submit({target:checkout,preventDefault(){}});const c=calls.find(x=>x.name==='gz_place_order');assert.equal(c.p.p_manager_slug,'ana');assert.equal(c.p.p_fulfillment,'delivery');assert.equal(c.p.p_items[0].quantity,1);assert(html.includes('PRUEBA01'),'muestra código');assert(html.includes('Avisar por WhatsApp'),'muestra enlace');
console.log('OK: catálogo, gestor, carrito, domicilio y solicitud con enlace de WhatsApp (servicio simulado).');
})().catch(e=>{console.error(e);process.exitCode=1});
