// Runs supabase/migrations against PGlite (Postgres in WASM) with a minimal
// stand-in for Supabase's auth schema and roles, then checks the sign-up
// trigger and every RLS policy/guard as each role. Replaces firestore.rules'
// (untested) guarantees with tested ones. Run: cd supabase && npm test

import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';

const db = new PGlite();
// Minimal stand-in for the parts of Supabase the migration depends on.
await db.exec(`
  create role anon nologin; create role authenticated nologin;
  create role service_role nologin bypassrls;
  create schema auth;
  create table auth.users (id uuid primary key, email text,
    raw_user_meta_data jsonb, raw_app_meta_data jsonb);
  create table auth.sessions (id uuid default gen_random_uuid(), user_id uuid);
  create function auth.jwt() returns jsonb language sql stable as $$
    select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(auth.jwt() ->> 'sub', '')::uuid $$;
  create publication supabase_realtime;
  -- Just enough of Supabase Storage for the store-media policies.
  create schema storage;
  create table storage.buckets (id text primary key, name text not null, public boolean default false,
    file_size_limit bigint, allowed_mime_types text[]);
  create table storage.objects (id uuid primary key default gen_random_uuid(),
    bucket_id text references storage.buckets (id), name text not null, owner uuid default auth.uid());
  alter table storage.objects enable row level security;
  create function storage.foldername(name text) returns text[] language sql immutable as $$
    select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
  grant usage on schema storage to anon, authenticated, service_role;
  grant all on storage.objects to anon, authenticated, service_role;
  grant select on storage.buckets to anon, authenticated, service_role;
  grant usage on schema public, auth to anon, authenticated, service_role;
  grant execute on all functions in schema auth to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
`);
// Every migration, in order, exactly as `supabase db push` would apply them.
const dir = new URL('../migrations/', import.meta.url);
for (const file of fs.readdirSync(dir).sort()) {
  await db.exec(fs.readFileSync(new URL(file, dir), 'utf8'));
}

let pass = 0, fail = 0;
const ok = (name, cond, extra = '') => {
  if (cond) { pass++; console.log('  ok   ' + name); }
  else { fail++; console.log('  FAIL ' + name + ' ' + extra); }
};
const as = async (who, sql, params) => {
  await db.exec('reset role');
  if (who === 'postgres') {
    await db.query(`select set_config('request.jwt.claims', '', false)`);
    return db.query(sql, params);
  }
  const role = who === 'anon' ? 'anon' : 'authenticated';
  const claims = who === 'anon' ? {} : { sub: who.id, role, app_metadata: who.app ?? {} };
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify(claims)]);
  await db.exec(`set role ${role}`);
  try { return await db.query(sql, params); } finally { await db.exec('reset role'); }
};
const throws = async (fn) => { try { await fn(); return null; } catch (e) { return e; } };
const signUp = (id, email, meta, app = {}) => as('postgres',
  'insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values ($1,$2,$3,$4)',
  [id, email, meta, app]);

const S1 = '11111111-1111-1111-1111-111111111111';
const S2 = '22222222-2222-2222-2222-222222222222';
const B1 = '33333333-3333-3333-3333-333333333333';
const A1 = '44444444-4444-4444-4444-444444444444';
const X1 = '55555555-5555-5555-5555-555555555555';
const seller1 = { id: S1 }, seller2 = { id: S2 }, buyer = { id: B1 };
const admin = { id: A1, app: { role: 'admin' } };

console.log('slugify');
const slug = (s) => as('postgres', 'select public.slugify($1) s', [s]).then((r) => r.rows[0].s);
ok('apostrophes dropped', await slug("Amina's Curated Picks!") === 'aminas-curated-picks');
ok('empty -> store', await slug('!!!') === 'store');
ok('60-char cap trims trailing hyphen', !(await slug('a'.repeat(59) + ' bbb')).endsWith('-'));

console.log('sign-up trigger');
const terms = { seller_terms_version: '2026-09-17' };
await signUp(S1, 'amina@x.com', { role: 'seller', name: 'Amina', store_name: "Amina's Store", phone: '0712', ...terms });
await signUp(S2, 'amina2@x.com', { role: 'seller', name: 'Amina 2', store_name: 'Aminas Store', ...terms });
let r = await as('postgres', 'select id, slug, seller_id from stores order by slug');
ok('seller gets store-{uid}', r.rows[0].id === 'store-' + S1);
ok('slug de-duplicated', r.rows.map((x) => x.slug).join() === 'aminas-store,aminas-store-2', JSON.stringify(r.rows));
r = await as('postgres', 'select * from profiles where uid = $1', [S1]);
ok('seller profile pendingApproval + terms', r.rows[0].seller_status === 'pendingApproval' && r.rows[0].seller_terms_accepted_at);
await signUp(B1, 'buyer@x.com', { role: 'buyer', name: 'Bob', store_id: 'store-' + S1 });
r = await as('postgres', 'select * from store_customers');
ok('buyer gets store membership', r.rows.length === 1 && r.rows[0].uid === B1);
ok('self-assigned admin refused', await throws(() => signUp(X1, 'x@x.com', { role: 'admin' })));
ok('seller without terms refused', await throws(() => signUp(X1, 'x@x.com', { role: 'seller', store_name: 'X' })));
ok('buyer of unknown store refused', await throws(() => signUp(X1, 'x@x.com', { role: 'buyer', store_id: 'nope' })));
r = await as('postgres', 'select count(*)::int n from auth.users where id = $1', [X1]);
ok('refused sign-up leaves no auth user', r.rows[0].n === 0);
await signUp(A1, 'admin@x.com', { name: 'Ops' }, { role: 'admin' });
r = await as('postgres', 'select role from profiles where uid = $1', [A1]);
ok('app_metadata admin gets admin profile', r.rows[0]?.role === 'admin');

console.log('profiles RLS');
r = await as(seller1, 'select uid from profiles');
ok('seller sees only own profile', r.rows.length === 1 && r.rows[0].uid === S1);
r = await as(admin, 'select uid from profiles');
ok('admin sees all profiles', r.rows.length === 4);
r = await as(seller1, "update profiles set name = 'New', currency_code = 'KES' where uid = $1 returning uid", [S1]);
ok('seller edits own name', r.rows.length === 1);
ok('seller cannot change role', await throws(() => as(seller1, "update profiles set role = 'admin' where uid = $1", [S1])));
ok('seller cannot self-activate subscription', await throws(() => as(seller1, "update profiles set subscription_active_until = now() + interval '1 year' where uid = $1", [S1])));
ok('seller cannot self-approve', await throws(() => as(seller1, "update profiles set seller_status = 'active' where uid = $1", [S1])));
ok('buyer cannot change store', await throws(() => as(buyer, "update profiles set store_id = $2 where uid = $1", [B1, 'store-' + S2])));
r = await as(seller1, "update profiles set name = 'Hacked' where uid = $1 returning uid", [S2]);
ok('seller cannot edit another profile', r.rows.length === 0);
r = await as(admin, "update profiles set seller_status = 'active' where uid = $1 returning uid", [S1]);
ok('admin approves seller', r.rows.length === 1);
ok('admin cannot mint admin', await throws(() => as(admin, "update profiles set role = 'admin' where uid = $1", [S1])));
ok('no client insert on profiles', await throws(() => as(seller1, "insert into profiles (uid, email, role) values ($1, 'e', 'admin')", [X1])));

console.log('stores RLS');
r = await as('anon', 'select id from stores');
ok('anon reads stores', r.rows.length === 2);
r = await as(seller1, "update stores set tagline = 'hi' where id = $1 returning id", ['store-' + S1]);
ok('owner updates store', r.rows.length === 1);
ok('owner cannot change slug', await throws(() => as(seller1, "update stores set slug = 'taken' where id = $1", ['store-' + S1])));
r = await as(seller1, "update stores set name = 'x' where id = $1 returning id", ['store-' + S2]);
ok('seller cannot update another store', r.rows.length === 0);
ok('buyer cannot create a store', await throws(() => as(buyer, "insert into stores (id, slug, seller_id, name) values ('s', 'bs', $1, 'B')", [B1])));

console.log('products RLS');
r = await as(seller1, "insert into products (store_id, id, seller_id, title, is_listed) values ($1, 'p1', $2, 'Lamp', true) returning id", ['store-' + S1, S1]);
ok('seller lists in own store', r.rows.length === 1);
ok('seller cannot list in another store', await throws(() => as(seller1, "insert into products (store_id, id, seller_id) values ($1, 'p2', $2)", ['store-' + S2, S1])));
r = await as('anon', 'select id from products');
ok('anon reads products', r.rows.length === 1);
await as(seller1, "insert into products (store_id, id, seller_id, title, is_listed) values ($1, 'draft1', $2, 'Draft', false)", ['store-' + S1, S1]);
ok('anon cannot read a draft', (await as('anon', "select id from products where id = 'draft1'")).rows.length === 0);
ok('another seller cannot read a draft', (await as(seller2, "select id from products where id = 'draft1'")).rows.length === 0);
ok('owner reads own draft', (await as(seller1, "select id from products where id = 'draft1'")).rows.length === 1);
ok('admin reads a draft', (await as(admin, "select id from products where id = 'draft1'")).rows.length === 1);
r = await as(seller2, "update products set sell_price = 1 where id = 'p1' returning id");
ok('seller cannot edit another store listing', r.rows.length === 0);

console.log('orders RLS');
await as('postgres', "insert into orders (id, code, buyer_id, seller_id, store_id, total) values ('o1', 'o1', $1, $2, $3, 100)", [B1, S1, 'store-' + S1]);
ok('client cannot create orders', await throws(() => as(buyer, "insert into orders (code, buyer_id, seller_id) values ('x', $1, $2)", [B1, S1])));
r = await as(buyer, 'select id from orders');
ok('buyer reads own order', r.rows.length === 1);
r = await as(seller2, 'select id from orders');
ok('other seller cannot read order', r.rows.length === 0);
r = await as(seller1, "update orders set status = 'shipped', updated_at = now() where id = 'o1' returning status");
ok('seller advances status', r.rows[0]?.status === 'shipped');
ok('seller cannot change total', await throws(() => as(seller1, "update orders set total = 1 where id = 'o1'")));
ok('seller cannot mark paid', await throws(() => as(seller1, "update orders set payment_status = 'paid' where id = 'o1'")));
ok('invalid status rejected', await throws(() => as(seller1, "update orders set status = 'bogus' where id = 'o1'")));
r = await as(buyer, "update orders set status = 'delivered' where id = 'o1' returning id");
ok('buyer cannot update order', r.rows.length === 0);

console.log('notifications RLS');
r = await as(buyer, "insert into notifications (recipient_id, title, message, order_id) values ($1, 't', 'm', 'o1'), ($2, 't', 'm', 'o1')", [B1, S1]);
ok('buyer alerts self + order seller', r.affectedRows === 2);
ok('buyer cannot alert a stranger', await throws(() => as(buyer, "insert into notifications (recipient_id, title, message, order_id) values ($1, 't', 'm', 'o1')", [S2])));
r = await as(seller1, 'select id from notifications');
ok('seller sees only own alerts', r.rows.length === 1);
r = await as(seller1, 'update notifications set read_at = now() returning id');
ok('recipient marks read', r.rows.length === 1);
ok('recipient cannot rewrite message', await throws(() => as(seller1, "update notifications set message = 'x'")));

console.log('plans, billing, fx');
await db.exec(`insert into subscription_plans (id, name) values ('basic', 'Basic'); insert into fx_rates (rates) values ('{"KES":129}')`);
r = await as('anon', 'select id from subscription_plans');
ok('anon reads plans', r.rows.length === 1);
ok('seller cannot edit plans', (await as(seller1, "update subscription_plans set price_usd = 0 returning id")).rows.length === 0);
r = await as(admin, "insert into subscription_plans (id, name) values ('pro', 'Pro') on conflict (id) do update set name = excluded.name returning id");
ok('admin upserts plans', r.rows.length === 1);
ok('seller cannot add plans', await throws(() => as(seller1, "insert into subscription_plans (id, name) values ('free', 'Free')")));
ok('seller cannot delete plans', (await as(seller1, "delete from subscription_plans where id = 'pro' returning id")).rows.length === 0);
ok('admin deletes plans', (await as(admin, "delete from subscription_plans where id = 'pro' returning id")).rows.length === 1);
ok('client cannot write billing history', await throws(() => as(seller1, "insert into billing_history (seller_id, plan_id) values ($1, 'basic')", [S1])));
r = await as('anon', "select rates from fx_rates where id = 'current'");
ok('anon reads fx', r.rows[0]?.rates?.KES === 129);

console.log('session revocation');
ok('client cannot revoke sessions', await throws(() => as(seller1, 'select public.revoke_user_sessions($1)', [S2])));

// ---- Phase 2 (20260927000000_backend.sql): what the api Edge Function uses.
// It connects as the service role, so that's who calls the SQL functions.
const asService = async (sql, params) => {
  await db.exec('reset role');
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ role: 'service_role' })]);
  await db.exec('set role service_role');
  try { return await db.query(sql, params); } finally { await db.exec('reset role'); }
};

console.log('orders: server-only columns');
ok('client select * on orders refused', await throws(() => as(buyer, 'select * from orders')));
r = await as(buyer, 'select id, total, payment_status, tracking, refunded_amount, payment_provider from orders');
ok('buyer reads the client columns', r.rows.length === 1);
ok('buyer cannot read the supplier cost', await throws(() => as(buyer, 'select supplier_subtotal_usd from orders')));
ok('seller cannot read payment refs', await throws(() => as(seller1, 'select payment_ref from orders')));
ok('seller cannot touch CJ state', await throws(() => as(seller1, "update orders set cj_order_status = 'PUSHED' where id = 'o1'")));
r = await asService("select cj_order_status, cj_push_attempts, refund_status from orders where id = 'o1'");
ok('service role reads everything, with state-machine defaults',
  r.rows[0]?.cj_order_status === 'NOT_PUSHED' && r.rows[0]?.cj_push_attempts === 0 && r.rows[0]?.refund_status === 'NONE');
ok('unknown CJ state rejected', await throws(() => asService("update orders set cj_order_status = 'SHIPPED' where id = 'o1'")));

console.log('orders: payment attempts');
ok('client cannot record a payment attempt', await throws(() => as(buyer, `select public.attach_order_payment_attempt('o1', 'MPESA', 'INTASEND', '{}')`)));
r = await asService(`select public.attach_order_payment_attempt('o1', 'MPESA', 'INTASEND', '{"invoiceId":"I1"}') a`);
ok('service records an attempt', r.rows[0].a === true);
await asService(`select public.attach_order_payment_attempt('o1', 'CARD', 'INTASEND', '{"checkoutId":"C1"}')`);
r = await as('postgres', "select payment_status, payment_ref, payment_attempts from orders where id = 'o1'");
ok('latest attempt on payment_ref, every attempt kept',
  r.rows[0].payment_status === 'awaiting_confirmation' && r.rows[0].payment_ref.checkoutId === 'C1' &&
  r.rows[0].payment_attempts.length === 2 && r.rows[0].payment_attempts[0].paymentRef.invoiceId === 'I1');
await as('postgres', "update orders set payment_status = 'paid' where id = 'o1'");
r = await asService(`select public.attach_order_payment_attempt('o1', 'MPESA', 'INTASEND', '{"invoiceId":"I2"}') a`);
const afterPaid = await as('postgres', "select payment_status from orders where id = 'o1'");
ok('a paid order is not reopened by a late attempt', r.rows[0].a === false && afterPaid.rows[0].payment_status === 'paid');

console.log('subscriptions: activation');
await as('postgres', "insert into billing_history (id, seller_id, plan_id, amount_kes, billing_period_days) values ('bh1', $1, 'basic', 999, 30)", [S2]);
ok('client cannot activate a subscription', await throws(() => as(seller2, "select public.activate_subscription('bh1', 'x')")));
r = await asService("select public.activate_subscription('bh1', 'INV-1') r");
ok('first confirmation activates', r.rows[0].r.alreadyHandled === false && r.rows[0].r.planId === 'basic');
r = await as('postgres', "select s.plan_id, s.status, p.subscription_plan_id, p.seller_status, p.subscription_active_until > now() + interval '29 days' as ahead from subscriptions s join profiles p on p.uid = s.seller_id where s.seller_id = $1", [S2]);
ok('subscription row + profile mirror written together',
  r.rows[0]?.plan_id === 'basic' && r.rows[0].status === 'active' &&
  r.rows[0].subscription_plan_id === 'basic' && r.rows[0].seller_status === 'active' && r.rows[0].ahead);
r = await as('postgres', "select status, payment_reference from billing_history where id = 'bh1'");
ok('entry marked paid with its reference', r.rows[0].status === 'paid' && r.rows[0].payment_reference === 'INV-1');
r = await asService("select public.activate_subscription('bh1', 'INV-1') r");
ok('a retried confirmation is a no-op', r.rows[0].r.alreadyHandled === true);
ok('an unknown entry raises', await throws(() => asService("select public.activate_subscription('nope', null)")));

console.log('rate limits');
ok('client cannot spend a budget', await throws(() => as(buyer, "select * from public.consume_rate_limit('k', 1, 1000)")));
const consume = (key, limit, windowMs) =>
  asService('select * from public.consume_rate_limit($1, $2, $3)', [key, limit, windowMs]).then((x) => x.rows[0]);
const first = await consume('createOrder:u1', 2, 60000);
const second = await consume('createOrder:u1', 2, 60000);
const third = await consume('createOrder:u1', 2, 60000);
ok('allows up to the limit, then refuses', first.allowed && second.allowed && !third.allowed);
ok('refusal carries a retry-after inside the window', Number(third.retry_after_ms) > 0 && Number(third.retry_after_ms) <= 60000);
ok('budgets are per key', (await consume('createOrder:u2', 2, 60000)).allowed);
await consume('mpesaPush:u1', 1, 1);
await new Promise((done) => setTimeout(done, 20));
ok('a new window opens once the old one has passed', (await consume('mpesaPush:u1', 1, 1)).allowed);
r = await as('anon', 'select key from rate_limits');
ok('clients cannot read counters', r.rows.length === 0);

console.log('backend tables');
await as('postgres', "insert into catalog_products (id, title) values ('cj1', 'Lamp')");
await as('postgres', "insert into catalog_categories (id, name) values ('c1', 'Home')");
ok('anon reads the catalog', (await as('anon', 'select id from catalog_products')).rows.length === 1 &&
  (await as('anon', 'select id from catalog_categories')).rows.length === 1);
ok('seller cannot write the catalog', await throws(() => as(seller1, "insert into catalog_products (id) values ('cj2')")));
await as('postgres', `insert into app_config (key, value) values ('pricing', '{"targetNetMargin":0.25}')`);
ok('non-admin cannot read app config', (await as(seller1, 'select key from app_config')).rows.length === 0);
r = await as(admin, `insert into app_config (key, value) values ('catalog', '{"sources":[]}') returning key`);
ok('admin writes app config', r.rows.length === 1);
ok('unknown config key rejected', await throws(() => as(admin, "insert into app_config (key) values ('secrets')")));
await as('postgres', "insert into cj_auth_tokens (access_token) values ('live-token')");
ok('CJ tokens are invisible even to admin', (await as(admin, 'select access_token from cj_auth_tokens')).rows.length === 0);
const jobErr = await throws(() => as(admin, "select public.invoke_scheduled_job('syncCatalog')"));
console.log('storage: store-media');
r = await as('postgres', "select public, file_size_limit from storage.buckets where id = 'store-media'");
ok('store-media bucket is public with a 2MB cap', r.rows[0]?.public === true && Number(r.rows[0]?.file_size_limit) === 2097152);
r = await as(seller1, "insert into storage.objects (bucket_id, name) values ('store-media', $1) returning name", ['store-' + S1 + '/logo-1.png']);
ok('owner uploads into own store folder (and reads it back)', r.rows.length === 1);
ok('seller cannot upload into another store', await throws(() => as(seller1, "insert into storage.objects (bucket_id, name) values ('store-media', $1)", ['store-' + S2 + '/logo-1.png'])));
ok('buyer cannot upload', await throws(() => as(buyer, "insert into storage.objects (bucket_id, name) values ('store-media', $1)", ['store-' + S1 + '/x.png'])));
ok('anon cannot upload', await throws(() => as('anon', "insert into storage.objects (bucket_id, name) values ('store-media', $1)", ['store-' + S1 + '/x.png'])));
ok('a file outside any store folder is refused', await throws(() => as(seller1, "insert into storage.objects (bucket_id, name) values ('store-media', 'logo.png')")));
r = await as(seller2, 'delete from storage.objects returning name');
ok("seller cannot delete another store's images", r.rows.length === 0);

ok('client cannot invoke scheduled jobs', /permission denied/.test(jobErr?.message ?? ''), jobErr?.message);
const serviceJobErr = await throws(() => asService("select public.activate_subscription('bh1', 'x')"));
ok('service role may call its functions', serviceJobErr === null, serviceJobErr?.message);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
