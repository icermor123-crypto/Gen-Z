-- Gen Z tienda multi-gestor (Supabase / PostgreSQL)
-- Ejecuta este archivo una sola vez en Supabase > SQL Editor.
-- Todos los flujos públicos sensibles se ejecutan como funciones transaccionales.

create extension if not exists pgcrypto;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('gz-product-images','gz-product-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

create table if not exists public.gz_stores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,39}$'),
  name text not null,
  description text not null default '',
  whatsapp text not null default '',
  pickup_address text not null default '',
  opening_hours text not null default '',
  delivery_enabled boolean not null default false,
  delivery_fee numeric(12,2) not null default 0 check (delivery_fee >= 0),
  delivery_zones text not null default '',
  delivery_eta text not null default '',
  currency text not null default 'USD' check (currency in ('USD','CUP')),
  created_at timestamptz not null default now()
);
drop policy if exists gz_product_images_public_read on storage.objects;
create policy gz_product_images_public_read on storage.objects for select to public using(bucket_id='gz-product-images');
drop policy if exists gz_product_images_owner_insert on storage.objects;
create policy gz_product_images_owner_insert on storage.objects for insert to authenticated with check(bucket_id='gz-product-images' and exists(select 1 from public.gz_stores s where s.id::text=split_part(storage.objects.name,'/',1) and s.owner_id=auth.uid()));
drop policy if exists gz_product_images_owner_update on storage.objects;
create policy gz_product_images_owner_update on storage.objects for update to authenticated using(bucket_id='gz-product-images' and exists(select 1 from public.gz_stores s where s.id::text=split_part(storage.objects.name,'/',1) and s.owner_id=auth.uid())) with check(bucket_id='gz-product-images' and exists(select 1 from public.gz_stores s where s.id::text=split_part(storage.objects.name,'/',1) and s.owner_id=auth.uid()));
drop policy if exists gz_product_images_owner_delete on storage.objects;
create policy gz_product_images_owner_delete on storage.objects for delete to authenticated using(bucket_id='gz-product-images' and exists(select 1 from public.gz_stores s where s.id::text=split_part(storage.objects.name,'/',1) and s.owner_id=auth.uid()));
create table if not exists public.gz_products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.gz_stores(id) on delete cascade,
  sku text not null default '',
  category text not null default '',
  name text not null,
  description text not null default '',
  image_url text not null default '',
  base_price numeric(12,2) not null check (base_price >= 0),
  unit_cost numeric(12,2) not null check (unit_cost >= 0),
  manager_floor numeric(12,2) not null default 0 check (manager_floor >= 0),
  stock integer not null default 0 check (stock >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.gz_products add column if not exists category text not null default '';
alter table public.gz_products add column if not exists manager_floor numeric(12,2) not null default 0;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='gz_products_manager_floor_nonnegative') then
  alter table public.gz_products add constraint gz_products_manager_floor_nonnegative check(manager_floor>=0);
 end if;
end $$;
create or replace function public.gz_guard_stock_mutation()
returns trigger language plpgsql set search_path=public,pg_temp
as $$ begin
 if TG_OP='INSERT' and new.stock=0 then return new; end if;
 if current_user<>pg_get_userbyid((select relowner from pg_class where oid='public.gz_products'::regclass)) then raise exception 'El stock solo se modifica mediante movimientos auditados'; end if;
 return new;
end $$;
revoke all on function public.gz_guard_stock_mutation() from public;
drop trigger if exists gz_stock_write_guard on public.gz_products;
create trigger gz_stock_write_guard before insert or update of stock on public.gz_products for each row execute function public.gz_guard_stock_mutation();
alter table public.gz_stores add column if not exists pickup_address text not null default '';
alter table public.gz_stores add column if not exists opening_hours text not null default '';
alter table public.gz_stores add column if not exists delivery_enabled boolean not null default false;
alter table public.gz_stores add column if not exists delivery_fee numeric(12,2) not null default 0;
alter table public.gz_stores add column if not exists delivery_zones text not null default '';
alter table public.gz_stores add column if not exists delivery_eta text not null default '';
do $$ begin
 if not exists(select 1 from pg_constraint where conname='gz_stores_delivery_fee_nonnegative') then
  alter table public.gz_stores add constraint gz_stores_delivery_fee_nonnegative check (delivery_fee>=0);
 end if;
end $$;
create index if not exists gz_products_store_idx on public.gz_products(store_id, active);
create table if not exists public.gz_stock_movements (
 id uuid primary key default gen_random_uuid(),store_id uuid not null references public.gz_stores(id) on delete cascade,
 product_id uuid references public.gz_products(id) on delete set null,product_name text not null,
 movement_type text not null check(movement_type in ('adjustment','restock','waste','correction','sale')),
 delta integer not null,stock_before integer not null,stock_after integer not null,reason text not null default '',
 actor_id uuid references auth.users(id),created_at timestamptz not null default now()
);
alter table public.gz_stock_movements drop constraint if exists gz_stock_movements_movement_type_check;
alter table public.gz_stock_movements add constraint gz_stock_movements_movement_type_check check(movement_type in ('adjustment','restock','waste','correction','sale'));
create index if not exists gz_stock_movements_store_date_idx on public.gz_stock_movements(store_id,created_at desc);
create table if not exists public.gz_purchases (
 id uuid primary key default gen_random_uuid(),store_id uuid not null references public.gz_stores(id) on delete cascade,
 purchase_code text not null unique,supplier text not null default '',note text not null default '',
 currency text not null,goods_total numeric(12,2) not null,shared_expenses numeric(12,2) not null default 0,
 total_cost numeric(12,2) not null,request_key text,actor_id uuid references auth.users(id),created_at timestamptz not null default now()
);
create table if not exists public.gz_purchase_items (
 id uuid primary key default gen_random_uuid(),purchase_id uuid not null references public.gz_purchases(id) on delete cascade,
 product_id uuid references public.gz_products(id) on delete set null,product_name text not null,
 quantity integer not null check(quantity>0),unit_price numeric(12,2) not null,
 shared_cost numeric(12,2) not null,landed_unit_cost numeric(12,2) not null,line_total numeric(12,2) not null
);
create unique index if not exists gz_purchases_request_key_idx on public.gz_purchases(store_id,request_key) where request_key is not null;
create index if not exists gz_purchases_store_date_idx on public.gz_purchases(store_id,created_at desc);
create table if not exists public.gz_cash_sessions (
 id uuid primary key default gen_random_uuid(),store_id uuid not null references public.gz_stores(id) on delete cascade,
 opened_by uuid references auth.users(id),closed_by uuid references auth.users(id),
 status text not null default 'open' check(status in ('open','closed')),
 opening_amount numeric(12,2) not null default 0 check(opening_amount>=0),
 expected_cash numeric(12,2) not null default 0,counted_cash numeric(12,2),difference numeric(12,2),
 opened_at timestamptz not null default now(),closed_at timestamptz
);
create unique index if not exists gz_cash_one_open_session on public.gz_cash_sessions(store_id) where status='open';
create index if not exists gz_cash_sessions_store_date_idx on public.gz_cash_sessions(store_id,opened_at desc);
create table if not exists public.gz_cash_movements (
 id uuid primary key default gen_random_uuid(),session_id uuid not null references public.gz_cash_sessions(id) on delete cascade,
 amount numeric(12,2) not null check(amount<>0),reason text not null,actor_id uuid references auth.users(id),created_at timestamptz not null default now()
);
create table if not exists public.gz_managers (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.gz_stores(id) on delete cascade,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  name text not null,
  email text not null,
  slug text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(store_id,slug),
  unique(store_id,email)
);
create table if not exists public.gz_manager_prices (
  manager_id uuid not null references public.gz_managers(id) on delete cascade,
  product_id uuid not null references public.gz_products(id) on delete cascade,
  price numeric(12,2) not null check (price >= 0),
  updated_at timestamptz not null default now(),
  primary key(manager_id,product_id)
);
create table if not exists public.gz_orders (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.gz_stores(id),
  manager_id uuid references public.gz_managers(id) on delete set null,
  manager_name text not null default 'Venta propia',
  manager_slug text not null default '',
  fulfillment text not null default 'online_pickup' check (fulfillment in ('online_pickup','delivery','local_sale')),
  delivery_address text not null default '',
  delivery_fee numeric(12,2) not null default 0,
  client_request_key text,
  order_code text not null unique,
  buyer_name text not null,
  buyer_phone text not null,
  buyer_note text not null default '',
  currency text not null,
  status text not null default 'pending',
  stock_committed boolean not null default false,
  cash_session_id uuid references public.gz_cash_sessions(id) on delete set null,
  payment_method text not null default 'pending',
  payment_status text not null default 'pending',
  cash_received numeric(12,2) not null default 0,
  change_due numeric(12,2) not null default 0,
  base_revenue numeric(12,2) not null,
  customer_total numeric(12,2) not null,
  manager_commission numeric(12,2) not null,
  cost_total numeric(12,2) not null,
  business_gross_profit numeric(12,2) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.gz_orders add column if not exists fulfillment text not null default 'online_pickup';
alter table public.gz_orders add column if not exists delivery_address text not null default '';
alter table public.gz_orders add column if not exists delivery_fee numeric(12,2) not null default 0;
alter table public.gz_orders add column if not exists client_request_key text;
alter table public.gz_orders add column if not exists cash_session_id uuid references public.gz_cash_sessions(id) on delete set null;
alter table public.gz_orders add column if not exists payment_method text not null default 'pending';
alter table public.gz_orders add column if not exists payment_status text not null default 'pending';
alter table public.gz_orders add column if not exists cash_received numeric(12,2) not null default 0;
alter table public.gz_orders add column if not exists change_due numeric(12,2) not null default 0;
alter table public.gz_orders drop constraint if exists gz_orders_payment_method_check;
alter table public.gz_orders add constraint gz_orders_payment_method_check check(payment_method in ('pending','cash','transfer','other'));
alter table public.gz_orders drop constraint if exists gz_orders_payment_status_check;
alter table public.gz_orders add constraint gz_orders_payment_status_check check(payment_status in ('pending','paid','refunded'));
do $$ begin
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='gz_orders' and column_name='stock_committed') then
  -- La versión anterior de esta app descontaba el inventario al crear el pedido.
  alter table public.gz_orders add column stock_committed boolean not null default true;
  update public.gz_orders set stock_committed=false where status='cancelled';
 end if;
end $$;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='gz_orders_delivery_fee_nonnegative') then
  alter table public.gz_orders add constraint gz_orders_delivery_fee_nonnegative check (delivery_fee>=0);
 end if;
end $$;
create unique index if not exists gz_orders_request_key_idx on public.gz_orders(store_id,client_request_key) where client_request_key is not null;
alter table public.gz_orders drop constraint if exists gz_orders_status_check;
alter table public.gz_orders add constraint gz_orders_status_check check(status in ('pending','confirmed','preparing','ready','in_delivery','delivered','cancelled'));
create index if not exists gz_orders_store_date_idx on public.gz_orders(store_id,created_at desc);

create or replace function public.gz_lock_store_currency()
returns trigger language plpgsql set search_path=public,pg_temp
as $$ begin
 if new.currency<>old.currency and (exists(select 1 from public.gz_orders o where o.store_id=old.id) or exists(select 1 from public.gz_purchases p where p.store_id=old.id)) then
   raise exception 'La moneda no se puede cambiar después del primer pedido; conserva el historial y crea otra tienda si necesitas otra moneda.';
 end if;
 return new;
end $$;
drop trigger if exists gz_store_currency_guard on public.gz_stores;
create trigger gz_store_currency_guard before update of currency on public.gz_stores for each row execute function public.gz_lock_store_currency();
revoke all on function public.gz_lock_store_currency() from public;
create table if not exists public.gz_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.gz_orders(id) on delete cascade,
  product_id uuid references public.gz_products(id) on delete set null,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_base_price numeric(12,2) not null,
  unit_customer_price numeric(12,2) not null,
  unit_cost numeric(12,2) not null,
  line_commission numeric(12,2) not null,
  line_customer_total numeric(12,2) not null
);

create or replace function public.gz_is_store_owner(p_store uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp
as $$ select exists(select 1 from public.gz_stores s where s.id=p_store and s.owner_id=auth.uid()) $$;
create or replace function public.gz_manager_id()
returns uuid language sql stable security definer set search_path=public,pg_temp
as $$ select m.id from public.gz_managers m where m.auth_user_id=auth.uid() and m.active limit 1 $$;

create or replace function public.gz_open_cash_session(p_store_id uuid,p_opening_amount numeric default 0)
returns jsonb language plpgsql security definer set search_path=public,pg_temp
as $$ declare v public.gz_cash_sessions;
begin
 if not public.gz_is_store_owner(p_store_id) then raise exception 'No autorizado';end if;
 if p_opening_amount<0 or p_opening_amount>100000000 then raise exception 'Fondo inicial no válido';end if;
 if exists(select 1 from public.gz_cash_sessions where store_id=p_store_id and status='open') then raise exception 'Ya existe un turno de caja abierto';end if;
 insert into public.gz_cash_sessions(store_id,opened_by,opening_amount,expected_cash) values(p_store_id,auth.uid(),p_opening_amount,p_opening_amount) returning * into v;
 return jsonb_build_object('id',v.id,'opening_amount',v.opening_amount,'expected_cash',v.expected_cash,'opened_at',v.opened_at);
end $$;
revoke all on function public.gz_open_cash_session(uuid,numeric) from public,anon;
grant execute on function public.gz_open_cash_session(uuid,numeric) to authenticated;

create or replace function public.gz_cash_status(p_store_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp
as $$ declare v public.gz_cash_sessions; sales numeric; moves numeric;
begin
 if not public.gz_is_store_owner(p_store_id) then raise exception 'No autorizado';end if;
 select * into v from public.gz_cash_sessions where store_id=p_store_id and status='open' order by opened_at desc limit 1;
 if not found then return jsonb_build_object('open',false);end if;
 select coalesce(sum(o.customer_total),0) into sales from public.gz_orders o where o.cash_session_id=v.id and o.payment_method='cash' and o.payment_status='paid' and o.status='delivered';
 select coalesce(sum(m.amount),0) into moves from public.gz_cash_movements m where m.session_id=v.id;
 return jsonb_build_object('open',true,'id',v.id,'opened_at',v.opened_at,'opening_amount',v.opening_amount,'expected_cash',v.opening_amount+sales+moves,'sales_total',sales,'adjustments_total',moves);
end $$;
revoke all on function public.gz_cash_status(uuid) from public,anon;
grant execute on function public.gz_cash_status(uuid) to authenticated;

create or replace function public.gz_add_cash_movement(p_session_id uuid,p_amount numeric,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp
as $$ declare v public.gz_cash_sessions;
begin
 select * into v from public.gz_cash_sessions where id=p_session_id for update;
 if not found or v.status<>'open' or not public.gz_is_store_owner(v.store_id) then raise exception 'No hay un turno abierto autorizado';end if;
 if p_amount=0 or abs(p_amount)>10000000 then raise exception 'Monto no válido';end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Escribe el motivo del movimiento';end if;
 insert into public.gz_cash_movements(session_id,amount,reason,actor_id) values(v.id,p_amount,left(trim(p_reason),500),auth.uid());
 return jsonb_build_object('id',v.id,'amount',p_amount);
end $$;
revoke all on function public.gz_add_cash_movement(uuid,numeric,text) from public,anon;
grant execute on function public.gz_add_cash_movement(uuid,numeric,text) to authenticated;

create or replace function public.gz_close_cash_session(p_session_id uuid,p_counted_cash numeric)
returns jsonb language plpgsql security definer set search_path=public,pg_temp
as $$ declare v public.gz_cash_sessions;sales numeric;moves numeric;expected numeric;
begin
 select * into v from public.gz_cash_sessions where id=p_session_id for update;
 if not found or v.status<>'open' or not public.gz_is_store_owner(v.store_id) then raise exception 'No hay un turno abierto autorizado';end if;
 if p_counted_cash<0 or p_counted_cash>100000000 then raise exception 'Conteo no válido';end if;
 select coalesce(sum(o.customer_total),0) into sales from public.gz_orders o where o.cash_session_id=v.id and o.payment_method='cash' and o.payment_status='paid' and o.status='delivered';
 select coalesce(sum(m.amount),0) into moves from public.gz_cash_movements m where m.session_id=v.id;
 expected:=v.opening_amount+sales+moves;
 update public.gz_cash_sessions set status='closed',closed_by=auth.uid(),closed_at=now(),expected_cash=expected,counted_cash=p_counted_cash,difference=p_counted_cash-expected where id=v.id;
 return jsonb_build_object('expected_cash',expected,'counted_cash',p_counted_cash,'difference',p_counted_cash-expected);
end $$;
revoke all on function public.gz_close_cash_session(uuid,numeric) from public,anon;
grant execute on function public.gz_close_cash_session(uuid,numeric) to authenticated;

create or replace function public.gz_receive_purchase(p_store_id uuid,p_supplier text,p_note text,p_items jsonb,p_shared_expenses numeric default 0,p_request_key text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp
as $$
declare s public.gz_stores;it jsonb;p public.gz_products;q integer;unit numeric;goods numeric:=0;qty_all integer:=0;v_code text;v_id uuid;existing public.gz_purchases;extra numeric;landed numeric;new_cost numeric;
begin
 if not public.gz_is_store_owner(p_store_id) then raise exception 'No autorizado'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>100 then raise exception 'La compra debe tener entre 1 y 100 líneas'; end if;
 if coalesce(p_shared_expenses,0)<0 or p_shared_expenses>100000000 then raise exception 'Gastos compartidos no válidos'; end if;
 select * into s from public.gz_stores where id=p_store_id;
 if p_request_key is not null then
  perform pg_advisory_xact_lock(hashtextextended(s.id::text||p_request_key,0));
  select * into existing from public.gz_purchases where store_id=s.id and request_key=p_request_key;
  if found then return jsonb_build_object('purchase_code',existing.purchase_code,'total_cost',existing.total_cost,'already_recorded',true); end if;
 end if;
 for p in select gp.* from public.gz_products gp where gp.store_id=s.id and gp.id in(select (x->>'product_id')::uuid from jsonb_array_elements(p_items)x) order by gp.id for update loop null;end loop;
 for it in select value from jsonb_array_elements(p_items) loop
  begin q:=(it->>'quantity')::integer;unit:=(it->>'unit_cost')::numeric;exception when others then raise exception 'Cantidad o costo no válido';end;
  if q<1 or q>10000 or unit<0 or unit>10000000 then raise exception 'Cantidad o costo no válido';end if;
  select * into p from public.gz_products where id=(it->>'product_id')::uuid and store_id=s.id;
  if not found then raise exception 'Producto no válido para esta tienda';end if;
  goods:=goods+q*unit;qty_all:=qty_all+q;
 end loop;
 if goods+p_shared_expenses<=0 then raise exception 'El costo total debe ser mayor que cero';end if;
 v_id:=gen_random_uuid();v_code:=upper(substr(replace(v_id::text,'-',''),1,8));
 insert into public.gz_purchases(id,store_id,purchase_code,supplier,note,currency,goods_total,shared_expenses,total_cost,request_key,actor_id)
 values(v_id,s.id,v_code,left(trim(coalesce(p_supplier,'')),150),left(trim(coalesce(p_note,'')),800),s.currency,goods,p_shared_expenses,goods+p_shared_expenses,p_request_key,auth.uid());
 for it in select value from jsonb_array_elements(p_items) loop
  q:=(it->>'quantity')::integer;unit:=(it->>'unit_cost')::numeric;
  select * into p from public.gz_products where id=(it->>'product_id')::uuid and store_id=s.id for update;
  extra:=case when goods>0 then p_shared_expenses*(q*unit)/goods else p_shared_expenses*q/qty_all end;
  landed:=unit+(extra/q);
  new_cost:=case when (p.stock+q)>0 then ((p.stock*p.unit_cost)+(q*landed))/(p.stock+q) else landed end;
  insert into public.gz_purchase_items(purchase_id,product_id,product_name,quantity,unit_price,shared_cost,landed_unit_cost,line_total)
  values(v_id,p.id,p.name,q,unit,extra,landed,q*landed);
  update public.gz_products set stock=p.stock+q,unit_cost=new_cost,updated_at=now() where id=p.id;
  insert into public.gz_stock_movements(store_id,product_id,product_name,movement_type,delta,stock_before,stock_after,reason,actor_id)
  values(s.id,p.id,p.name,'restock',q,p.stock,p.stock+q,'Compra #'||v_code||case when trim(coalesce(p_supplier,''))='' then '' else ' · '||left(trim(p_supplier),100) end,auth.uid());
 end loop;
 return jsonb_build_object('purchase_code',v_code,'goods_total',goods,'shared_expenses',p_shared_expenses,'total_cost',goods+p_shared_expenses,'already_recorded',false);
end $$;
revoke all on function public.gz_receive_purchase(uuid,text,text,jsonb,numeric,text) from public,anon;
grant execute on function public.gz_receive_purchase(uuid,text,text,jsonb,numeric,text) to authenticated;

alter table public.gz_purchases enable row level security;
alter table public.gz_purchase_items enable row level security;
drop policy if exists gz_purchase_owner_select on public.gz_purchases;
create policy gz_purchase_owner_select on public.gz_purchases for select to authenticated using(public.gz_is_store_owner(store_id));
drop policy if exists gz_purchase_item_owner_select on public.gz_purchase_items;
create policy gz_purchase_item_owner_select on public.gz_purchase_items for select to authenticated using(exists(select 1 from public.gz_purchases gp where gp.id=purchase_id and public.gz_is_store_owner(gp.store_id)));

-- Caja: venta presencial con turno abierto, forma de pago y descuento atómico.
drop function if exists public.gz_record_local_sale(uuid,text,jsonb);
drop function if exists public.gz_record_local_sale(uuid,uuid,text,text,jsonb);
drop function if exists public.gz_record_local_sale(uuid,uuid,text,text,jsonb,text);
create or replace function public.gz_record_local_sale(p_store_id uuid,p_cash_session_id uuid,p_buyer_name text,p_payment_method text,p_items jsonb,p_cash_received numeric default null,p_request_key text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp
as $$
declare s public.gz_stores;cs public.gz_cash_sessions;it jsonb;p public.gz_products;q integer;v_code text;v_order uuid;v_total numeric:=0;v_cost numeric:=0;v_cash_received numeric:=0;v_change numeric:=0;existing public.gz_orders;
begin
 if not public.gz_is_store_owner(p_store_id) then raise exception 'No autorizado'; end if;
 if p_payment_method not in ('cash','transfer','other') then raise exception 'Forma de pago no válida';end if;
 if p_request_key is not null then
  if length(p_request_key)<12 or length(p_request_key)>100 then raise exception 'Clave de solicitud no válida';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_store_id::text||p_request_key,0));
  select * into existing from public.gz_orders where store_id=p_store_id and client_request_key=p_request_key;
  if found then return jsonb_build_object('order_code',existing.order_code,'total',existing.customer_total,'currency',existing.currency,'already_recorded',true);end if;
 end if;
 select * into cs from public.gz_cash_sessions where id=p_cash_session_id and store_id=p_store_id and status='open' for update;
 if not found then raise exception 'Abre un turno de caja antes de registrar ventas';end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>40 then raise exception 'La venta no es válida'; end if;
 select * into s from public.gz_stores where id=p_store_id;
 for p in select gp.* from public.gz_products gp where gp.store_id=s.id and gp.active and gp.id in (select (x->>'product_id')::uuid from jsonb_array_elements(p_items) x) order by gp.id for update loop null; end loop;
 for it in select value from jsonb_array_elements(p_items) loop
   begin q:=(it->>'quantity')::integer; exception when others then raise exception 'Cantidad no válida'; end;
   if q<1 or q>100 then raise exception 'Cantidad no válida'; end if;
   select * into p from public.gz_products where id=(it->>'product_id')::uuid and store_id=s.id and active;
   if not found or p.stock<q then raise exception 'Producto no disponible o stock insuficiente'; end if;
   v_total:=v_total+p.base_price*q;v_cost:=v_cost+p.unit_cost*q;
 end loop;
 if p_payment_method='cash' then
  v_cash_received:=coalesce(p_cash_received,v_total);
  if v_cash_received<v_total then raise exception 'El efectivo recibido no cubre el total de la venta';end if;
  v_change:=v_cash_received-v_total;
 end if;
 v_order:=gen_random_uuid();v_code:=upper(substr(replace(v_order::text,'-',''),1,8));
 insert into public.gz_orders(id,store_id,manager_name,fulfillment,cash_session_id,payment_method,payment_status,cash_received,change_due,client_request_key,order_code,buyer_name,buyer_phone,buyer_note,currency,status,base_revenue,customer_total,manager_commission,cost_total,business_gross_profit)
 values(v_order,s.id,'Venta propia','local_sale',cs.id,p_payment_method,'paid',v_cash_received,v_change,p_request_key,v_code,coalesce(nullif(trim(p_buyer_name),''),'Venta presencial'),'','',s.currency,'delivered',v_total,v_total,0,v_cost,v_total-v_cost);
 for it in select value from jsonb_array_elements(p_items) loop
   q:=(it->>'quantity')::integer;select * into p from public.gz_products where id=(it->>'product_id')::uuid and store_id=s.id and active;
   insert into public.gz_order_items(order_id,product_id,product_name,quantity,unit_base_price,unit_customer_price,unit_cost,line_commission,line_customer_total)
   values(v_order,p.id,p.name,q,p.base_price,p.base_price,p.unit_cost,0,p.base_price*q);
   update public.gz_products set stock=stock-q,updated_at=now() where id=p.id;
   insert into public.gz_stock_movements(store_id,product_id,product_name,movement_type,delta,stock_before,stock_after,reason,actor_id)
   values(s.id,p.id,p.name,'sale',-q,p.stock,p.stock-q,'Venta presencial #'||v_code,auth.uid());
 end loop;
 return jsonb_build_object('order_code',v_code,'total',v_total,'currency',s.currency);
end $$;
revoke all on function public.gz_record_local_sale(uuid,uuid,text,text,jsonb,numeric,text) from public,anon;
grant execute on function public.gz_record_local_sale(uuid,uuid,text,text,jsonb,numeric,text) to authenticated;


alter table public.gz_stores enable row level security;
alter table public.gz_products enable row level security;
alter table public.gz_managers enable row level security;
alter table public.gz_manager_prices enable row level security;
alter table public.gz_orders enable row level security;
alter table public.gz_order_items enable row level security;
alter table public.gz_stock_movements enable row level security;
alter table public.gz_cash_sessions enable row level security;
alter table public.gz_cash_movements enable row level security;

drop policy if exists gz_store_owner_select on public.gz_stores;
create policy gz_store_owner_select on public.gz_stores for select to authenticated using(owner_id=auth.uid());
drop policy if exists gz_store_manager_select on public.gz_stores;
create policy gz_store_manager_select on public.gz_stores for select to authenticated using(exists(select 1 from public.gz_managers m where m.store_id=gz_stores.id and m.auth_user_id=auth.uid() and m.active));
drop policy if exists gz_store_owner_insert on public.gz_stores;
create policy gz_store_owner_insert on public.gz_stores for insert to authenticated with check(owner_id=auth.uid());
drop policy if exists gz_store_owner_update on public.gz_stores;
create policy gz_store_owner_update on public.gz_stores for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists gz_product_owner_all on public.gz_products;
create policy gz_product_owner_all on public.gz_products for all to authenticated using(public.gz_is_store_owner(store_id)) with check(public.gz_is_store_owner(store_id));
drop policy if exists gz_manager_owner_select on public.gz_managers;
create policy gz_manager_owner_select on public.gz_managers for select to authenticated using(public.gz_is_store_owner(store_id));
drop policy if exists gz_manager_owner_insert on public.gz_managers;
create policy gz_manager_owner_insert on public.gz_managers for insert to authenticated with check(public.gz_is_store_owner(store_id) and auth_user_id is null);
drop policy if exists gz_manager_owner_update on public.gz_managers;
create policy gz_manager_owner_update on public.gz_managers for update to authenticated using(public.gz_is_store_owner(store_id)) with check(public.gz_is_store_owner(store_id));
drop policy if exists gz_manager_self_select on public.gz_managers;
create policy gz_manager_self_select on public.gz_managers for select to authenticated using(auth_user_id=auth.uid() and active);
drop policy if exists gz_price_owner_all on public.gz_manager_prices;
create policy gz_price_owner_all on public.gz_manager_prices for all to authenticated using(exists(select 1 from public.gz_managers m where m.id=manager_id and public.gz_is_store_owner(m.store_id))) with check(exists(select 1 from public.gz_managers m where m.id=manager_id and public.gz_is_store_owner(m.store_id)));
drop policy if exists gz_price_manager_select on public.gz_manager_prices;
create policy gz_price_manager_select on public.gz_manager_prices for select to authenticated using(manager_id=public.gz_manager_id());
drop policy if exists gz_price_manager_write on public.gz_manager_prices;
create policy gz_price_manager_write on public.gz_manager_prices for all to authenticated using(manager_id=public.gz_manager_id()) with check(manager_id=public.gz_manager_id());
drop policy if exists gz_order_owner_select on public.gz_orders;
create policy gz_order_owner_select on public.gz_orders for select to authenticated using(public.gz_is_store_owner(store_id));
drop policy if exists gz_order_manager_select on public.gz_orders;
create policy gz_order_manager_select on public.gz_orders for select to authenticated using(manager_id=public.gz_manager_id());
drop policy if exists gz_order_owner_update on public.gz_orders;
create policy gz_order_owner_update on public.gz_orders for update to authenticated using(public.gz_is_store_owner(store_id)) with check(public.gz_is_store_owner(store_id));
drop policy if exists gz_item_manager_select on public.gz_order_items;
drop policy if exists gz_item_owner_select on public.gz_order_items;
create policy gz_item_owner_select on public.gz_order_items for select to authenticated using(exists(select 1 from public.gz_orders o where o.id=order_id and public.gz_is_store_owner(o.store_id)));
drop policy if exists gz_stock_owner_select on public.gz_stock_movements;
create policy gz_stock_owner_select on public.gz_stock_movements for select to authenticated using(public.gz_is_store_owner(store_id));
drop policy if exists gz_cash_session_owner_select on public.gz_cash_sessions;
create policy gz_cash_session_owner_select on public.gz_cash_sessions for select to authenticated using(public.gz_is_store_owner(store_id));
drop policy if exists gz_cash_movement_owner_select on public.gz_cash_movements;
create policy gz_cash_movement_owner_select on public.gz_cash_movements for select to authenticated using(exists(select 1 from public.gz_cash_sessions c where c.id=session_id and public.gz_is_store_owner(c.store_id)));

-- Ajustes de inventario auditables y autorizados solo al propietario.
create or replace function public.gz_adjust_stock(p_product_id uuid,p_delta integer,p_movement_type text,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=public,pg_temp
as $$
declare p public.gz_products; v_after integer;
begin
 if p_delta=0 or abs(p_delta)>10000 then raise exception 'El ajuste debe ser distinto de cero y razonable'; end if;
 if p_movement_type not in ('adjustment','restock','waste','correction') then raise exception 'Tipo de movimiento no válido'; end if;
 if (p_movement_type='restock' and p_delta<0) or (p_movement_type='waste' and p_delta>0) then raise exception 'El signo del ajuste no corresponde al tipo de movimiento'; end if;
 select * into p from public.gz_products where id=p_product_id for update;
 if not found or not public.gz_is_store_owner(p.store_id) then raise exception 'No autorizado'; end if;
 v_after:=p.stock+p_delta;if v_after<0 then raise exception 'El ajuste no puede dejar existencias negativas'; end if;
 update public.gz_products set stock=v_after,updated_at=now() where id=p.id;
 insert into public.gz_stock_movements(store_id,product_id,product_name,movement_type,delta,stock_before,stock_after,reason,actor_id)
 values(p.store_id,p.id,p.name,p_movement_type,p_delta,p.stock,v_after,left(trim(coalesce(p_reason,'')),500),auth.uid());
 return jsonb_build_object('stock_before',p.stock,'stock_after',v_after,'product_name',p.name);
end $$;
revoke all on function public.gz_adjust_stock(uuid,integer,text,text) from public,anon;
grant execute on function public.gz_adjust_stock(uuid,integer,text,text) to authenticated;

-- Evita que un gestor altere referencias o ponga un precio inferior al precio base.
create or replace function public.gz_check_manager_price()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_store uuid; v_base numeric; v_floor numeric; v_cost numeric;
begin
 select m.store_id into v_store from public.gz_managers m where m.id=new.manager_id and m.active for update;
 select p.base_price,p.manager_floor,p.unit_cost into v_base,v_floor,v_cost from public.gz_products p where p.id=new.product_id and p.store_id=v_store and p.active for share;
 if v_store is null or v_base is null then raise exception 'Gestor o producto no válido'; end if;
 if new.price < greatest(v_base,v_floor,v_cost) then raise exception 'El precio está por debajo del mínimo autorizado (%).',greatest(v_base,v_floor,v_cost); end if;
 new.updated_at=now(); return new;
end $$;
drop trigger if exists gz_manager_price_guard on public.gz_manager_prices;
create trigger gz_manager_price_guard before insert or update on public.gz_manager_prices for each row execute function public.gz_check_manager_price();

-- Administrador vincula el registro preparado por él al usuario autenticado del gestor.
create or replace function public.gz_attach_manager(p_manager_id uuid,p_email text)
returns void language plpgsql security definer set search_path=public,auth,pg_temp
as $$
declare m public.gz_managers; u uuid;
begin
 select * into m from public.gz_managers where id=p_manager_id for update;
 if not found or not public.gz_is_store_owner(m.store_id) then raise exception 'No autorizado'; end if;
 select id into u from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null limit 1;
 if u is null then raise exception 'No existe una cuenta verificada con ese correo. El gestor debe registrarse y verificar su correo primero.'; end if;
 update public.gz_managers set auth_user_id=u,email=lower(trim(p_email)) where id=p_manager_id;
end $$;
revoke all on function public.gz_attach_manager(uuid,text) from public,anon;
grant execute on function public.gz_attach_manager(uuid,text) to authenticated;

-- Consulta pública de una tienda y catálogo. Solo publica productos activos con stock.
create or replace function public.gz_public_catalog(p_slug text,p_manager_slug text default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp
as $$
declare s public.gz_stores; m public.gz_managers; result jsonb;
begin
 select * into s from public.gz_stores where slug=lower(trim(p_slug));
 if not found then raise exception 'Tienda no encontrada'; end if;
 if p_manager_slug is not null and trim(p_manager_slug)<>'' then
   select * into m from public.gz_managers where store_id=s.id and slug=lower(trim(p_manager_slug)) and active;
   if not found then raise exception 'Enlace de gestor no válido'; end if;
 end if;
 select jsonb_build_object('store',jsonb_build_object('name',s.name,'description',s.description,'whatsapp',s.whatsapp,'currency',s.currency,'slug',s.slug,'pickup_address',s.pickup_address,'opening_hours',s.opening_hours,'delivery_enabled',(s.delivery_enabled and length(trim(s.delivery_zones))>0 and length(trim(s.delivery_eta))>0),'delivery_fee',s.delivery_fee,'delivery_zones',s.delivery_zones,'delivery_eta',s.delivery_eta),
 'manager',case when m.id is null then null else jsonb_build_object('name',m.name,'slug',m.slug) end,
 'products',coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'image_url',p.image_url,'sku',p.sku,'category',p.category,'stock',p.stock,'manager_floor',case when (m.auth_user_id is not null and m.auth_user_id=auth.uid()) or public.gz_is_store_owner(s.id) then greatest(p.manager_floor,p.unit_cost,p.base_price) else null end,'base_price',case when (m.auth_user_id is not null and m.auth_user_id=auth.uid()) or public.gz_is_store_owner(s.id) then p.base_price else null end,'price',greatest(coalesce(mp.price,p.base_price),p.base_price,p.manager_floor,p.unit_cost)) order by p.name) filter(where p.id is not null), '[]'::jsonb))
 into result
 from public.gz_stores x left join public.gz_products p on p.store_id=x.id and p.active and p.stock>0
 left join public.gz_manager_prices mp on mp.product_id=p.id and mp.manager_id=m.id
where x.id=s.id;
 return result;
end $$;
grant execute on function public.gz_public_catalog(text,text) to anon,authenticated;

-- Crea pedido, fija precios y márgenes como snapshots, y descuenta inventario de forma atómica.
drop function if exists public.gz_place_order(text,text,text,text,text,jsonb);
create or replace function public.gz_place_order(p_store_slug text,p_manager_slug text,p_buyer_name text,p_buyer_phone text,p_buyer_note text,p_items jsonb,p_fulfillment text default 'online_pickup',p_delivery_address text default '',p_client_request_key text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp
as $$
declare s public.gz_stores; m public.gz_managers; it jsonb; p public.gz_products; q integer; v_unit numeric; v_base numeric; existing public.gz_orders;
 v_code text; v_order uuid; v_base_total numeric:=0; v_customer_total numeric:=0; v_cost_total numeric:=0; v_comm numeric:=0; v_delivery_fee numeric:=0;
begin
 if length(trim(coalesce(p_buyer_name,'')))<2 then raise exception 'Escribe tu nombre'; end if;
 if length(regexp_replace(coalesce(p_buyer_phone,''),'\D','','g'))<6 then raise exception 'Revisa el teléfono de contacto'; end if;
 if p_fulfillment not in ('online_pickup','delivery') then raise exception 'Modalidad de entrega no válida'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>30 then raise exception 'El pedido no es válido'; end if;
 select * into s from public.gz_stores where slug=lower(trim(p_store_slug)); if not found then raise exception 'Tienda no encontrada'; end if;
 if length(regexp_replace(coalesce(s.whatsapp,''),'\\D','','g'))<6 then raise exception 'La tienda aún no configuró un contacto WhatsApp válido'; end if;
 if p_client_request_key is not null then
   if length(p_client_request_key)<12 or length(p_client_request_key)>100 then raise exception 'Identificador de solicitud no válido'; end if;
   perform pg_advisory_xact_lock(hashtextextended(s.id::text||p_client_request_key,0));
   select * into existing from public.gz_orders where store_id=s.id and client_request_key=p_client_request_key;
   if found then return jsonb_build_object('order_code',existing.order_code,'customer_total',existing.customer_total,'products_total',existing.customer_total-existing.delivery_fee,'delivery_fee',existing.delivery_fee,'currency',existing.currency,'manager_name',existing.manager_name,'whatsapp',s.whatsapp); end if;
 end if;
 if p_fulfillment='delivery' then
   if not s.delivery_enabled or length(trim(s.delivery_zones))=0 or length(trim(s.delivery_eta))=0 then raise exception 'La entrega a domicilio no está completamente configurada'; end if;
   if length(trim(coalesce(p_delivery_address,'')))<6 then raise exception 'Escribe una dirección de entrega completa'; end if;
   v_delivery_fee:=s.delivery_fee;
 end if;
 if p_manager_slug is not null and trim(p_manager_slug)<>'' then
   select * into m from public.gz_managers where store_id=s.id and slug=lower(trim(p_manager_slug)) and active for share;
   if not found then raise exception 'Gestor no válido'; end if;
 end if;
 -- Ordenar IDs al bloquear filas para reducir el riesgo de deadlocks.
 for p in select gp.* from public.gz_products gp where gp.store_id=s.id and gp.active and gp.id in (select (x->>'product_id')::uuid from jsonb_array_elements(p_items) x) order by gp.id for update loop
   null;
 end loop;
 -- Validar el total por producto, incluso si el cliente envía líneas duplicadas.
 for p in select gp.* from public.gz_products gp where gp.store_id=s.id and gp.active and gp.id in (select (x->>'product_id')::uuid from jsonb_array_elements(p_items) x) loop
   select coalesce(sum((x->>'quantity')::integer),0) into q from jsonb_array_elements(p_items) x where (x->>'product_id')::uuid=p.id;
   if q<1 or q>100 then raise exception 'Cantidad total no válida para %',p.name; end if;
   if p.stock<q then raise exception 'No hay suficiente existencia de %',p.name; end if;
 end loop;
 for it in select value from jsonb_array_elements(p_items) loop
   begin q:=(it->>'quantity')::integer; exception when others then raise exception 'Cantidad no válida'; end;
   if q<1 or q>100 then raise exception 'La cantidad debe estar entre 1 y 100'; end if;
   select * into p from public.gz_products where id=(it->>'product_id')::uuid and store_id=s.id and active;
   if not found then raise exception 'Un producto ya no está disponible'; end if;
   v_base:=p.base_price;
   if m.id is null then v_unit:=v_base;
   else select price into v_unit from public.gz_manager_prices where manager_id=m.id and product_id=p.id; v_unit:=greatest(coalesce(v_unit,v_base),v_base,p.manager_floor,p.unit_cost); end if;
   v_base_total:=v_base_total+v_base*q; v_customer_total:=v_customer_total+v_unit*q;
   v_cost_total:=v_cost_total+p.unit_cost*q; v_comm:=v_comm+(v_unit-v_base)*q;
 end loop;
 v_order:=gen_random_uuid(); v_code:=upper(substr(replace(v_order::text,'-',''),1,8));
 insert into public.gz_orders(id,store_id,manager_id,manager_name,manager_slug,fulfillment,delivery_address,delivery_fee,client_request_key,order_code,buyer_name,buyer_phone,buyer_note,currency,status,base_revenue,customer_total,manager_commission,cost_total,business_gross_profit)
 values(v_order,s.id,m.id,coalesce(m.name,'Venta propia'),coalesce(m.slug,''),p_fulfillment,left(coalesce(p_delivery_address,''),800),v_delivery_fee,p_client_request_key,v_code,trim(p_buyer_name),trim(p_buyer_phone),left(coalesce(p_buyer_note,''),1000),s.currency,'pending',v_base_total,v_customer_total+v_delivery_fee,v_comm,v_cost_total,v_base_total-v_cost_total);
 for it in select value from jsonb_array_elements(p_items) loop
   q:=(it->>'quantity')::integer;
   select * into p from public.gz_products where id=(it->>'product_id')::uuid and store_id=s.id and active;
   v_base:=p.base_price;
   if m.id is null then v_unit:=v_base; else select price into v_unit from public.gz_manager_prices where manager_id=m.id and product_id=p.id; v_unit:=greatest(coalesce(v_unit,v_base),v_base,p.manager_floor,p.unit_cost); end if;
   insert into public.gz_order_items(order_id,product_id,product_name,quantity,unit_base_price,unit_customer_price,unit_cost,line_commission,line_customer_total)
   values(v_order,p.id,p.name,q,v_base,v_unit,p.unit_cost,(v_unit-v_base)*q,v_unit*q);
   -- La solicitud pendiente no descuenta existencias. El stock se bloquea y descuenta
   -- al confirmar; así un cliente que no envía WhatsApp no retiene unidades.
 end loop;
 return jsonb_build_object('order_code',v_code,'customer_total',v_customer_total+v_delivery_fee,'products_total',v_customer_total,'delivery_fee',v_delivery_fee,'currency',s.currency,'manager_name',coalesce(m.name,'Venta propia'),'whatsapp',s.whatsapp);
end $$;
drop function if exists public.gz_place_order(text,text,text,text,text,jsonb,text,text);
revoke all on function public.gz_place_order(text,text,text,text,text,jsonb,text,text,text) from public,anon,authenticated;
grant execute on function public.gz_place_order(text,text,text,text,text,jsonb,text,text,text) to anon,authenticated;

-- Cambia estados desde el panel de dueño; al cancelar se devuelve stock una vez.
create or replace function public.gz_set_order_status(p_order_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
declare o public.gz_orders; li record; p public.gz_products;
begin
 if p_status not in ('confirmed','preparing','ready','in_delivery','delivered','cancelled') then raise exception 'Estado no válido'; end if;
 select * into o from public.gz_orders where id=p_order_id for update;
 if not found or not public.gz_is_store_owner(o.store_id) then raise exception 'No autorizado'; end if;
 if o.status=p_status then return; end if;
 if o.status in ('cancelled','delivered') then raise exception 'Un pedido cancelado o entregado no se puede modificar'; end if;
 if not ((o.status='pending' and p_status in ('confirmed','cancelled')) or
         (o.status='confirmed' and p_status in ('preparing','cancelled')) or
         (o.status='preparing' and p_status in ('ready','cancelled')) or
         (o.status='ready' and p_status in ('in_delivery','delivered','cancelled')) or
         (o.status='in_delivery' and p_status in ('delivered','cancelled'))) then
   raise exception 'Transición de estado no permitida: % → %',o.status,p_status;
 end if;
 if o.status='pending' and p_status='confirmed' then
     for li in select product_id,sum(quantity)::integer as quantity from public.gz_order_items where order_id=o.id and product_id is not null group by product_id order by product_id loop
     select * into p from public.gz_products where id=li.product_id and store_id=o.store_id and active for update;
     if not found or p.stock<li.quantity then raise exception 'Stock insuficiente para confirmar: %',coalesce(p.name,'producto'); end if;
     update public.gz_products set stock=stock-li.quantity,updated_at=now() where id=p.id;
     insert into public.gz_stock_movements(store_id,product_id,product_name,movement_type,delta,stock_before,stock_after,reason,actor_id)
     values(o.store_id,p.id,p.name,'sale',-li.quantity,p.stock,p.stock-li.quantity,'Confirmación pedido #'||o.order_code,auth.uid());
   end loop;
   update public.gz_orders set stock_committed=true where id=o.id;
 end if;
 if p_status='cancelled' and o.stock_committed then
     for li in select product_id,sum(quantity)::integer as quantity from public.gz_order_items where order_id=o.id and product_id is not null group by product_id order by product_id loop
     select * into p from public.gz_products where id=li.product_id for update;
     if found then
       update public.gz_products set stock=stock+li.quantity,updated_at=now() where id=li.product_id;
       insert into public.gz_stock_movements(store_id,product_id,product_name,movement_type,delta,stock_before,stock_after,reason,actor_id)
       values(o.store_id,p.id,p.name,'correction',li.quantity,p.stock,p.stock+li.quantity,'Cancelación pedido #'||o.order_code,auth.uid());
     end if;
   end loop;
   update public.gz_orders set stock_committed=false where id=o.id;
 end if;
 update public.gz_orders set status=p_status,updated_at=now() where id=o.id;
end $$;
revoke all on function public.gz_set_order_status(uuid,text) from public,anon;
grant execute on function public.gz_set_order_status(uuid,text) to authenticated;

-- El dueño puede leer pedidos y artículos completos; los gestores no reciben el costo por artículo.
create or replace function public.gz_owner_orders(p_store_id uuid,p_limit integer default 500)
returns setof public.gz_orders language plpgsql stable security definer set search_path=public,pg_temp
as $$ begin
 if not public.gz_is_store_owner(p_store_id) then raise exception 'No autorizado'; end if;
 return query select * from public.gz_orders where store_id=p_store_id order by created_at desc limit greatest(1,least(coalesce(p_limit,500),2000));
end $$;
revoke all on function public.gz_owner_orders(uuid,integer) from public,anon;
grant execute on function public.gz_owner_orders(uuid,integer) to authenticated;

-- No permitir que la tienda pública explore tablas directamente; gestores no reciben PII de clientes ni costos unitarios.
revoke all on public.gz_stores,public.gz_products,public.gz_managers,public.gz_manager_prices,public.gz_orders,public.gz_order_items,public.gz_stock_movements,public.gz_purchases,public.gz_purchase_items,public.gz_cash_sessions,public.gz_cash_movements from anon,authenticated;
grant select,insert,update on public.gz_stores to authenticated;
grant select,insert,update,delete on public.gz_products to authenticated;
grant select,insert,update on public.gz_managers to authenticated;
grant select,insert,update,delete on public.gz_manager_prices to authenticated;
grant select (id,store_id,manager_id,manager_name,manager_slug,fulfillment,delivery_fee,order_code,currency,status,base_revenue,customer_total,manager_commission,cost_total,business_gross_profit,created_at,updated_at) on public.gz_orders to authenticated;
grant select on public.gz_order_items to authenticated;
grant select on public.gz_stock_movements to authenticated;
grant select on public.gz_purchases to authenticated;
grant select on public.gz_purchase_items to authenticated;
grant select on public.gz_cash_sessions to authenticated;
grant select on public.gz_cash_movements to authenticated;
revoke all on function public.gz_is_store_owner(uuid) from public;
revoke all on function public.gz_manager_id() from public;
grant execute on function public.gz_is_store_owner(uuid) to authenticated;
grant execute on function public.gz_manager_id() to authenticated;
