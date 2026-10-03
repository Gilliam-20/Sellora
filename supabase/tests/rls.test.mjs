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
// Publishing needs a seller in good standing (H5): S1 was approved above;
// give them a live subscription.
await as('postgres', "insert into subscription_plans (id, name, listing_limit) values ('basic', 'Basic', 5)");
await as('postgres', "insert into subscriptions (seller_id, plan_id, current_period_start, current_period_end) values ($1, 'basic', now(), now() + interval '30 days')", [S1]);
r = await as(seller1, "insert into products (store_id, id, seller_id, title, is_listed) values ($1, 'p1', $2, 'Lamp', true) returning id", ['store-' + S1, S1]);
ok('seller lists in own store', r.rows.length === 1);
ok('seller cannot list in another store', await throws(() => as(seller1, "insert into products (store_id, id, seller_id) values ($1, 'p2', $2)", ['store-' + S2, S1])));
r = await as('anon', 'select id from storefront_products');
ok('anon reads listed products through the storefront view', r.rows.length === 1);
ok('anon cannot read the products table itself', (await as('anon', 'select id from products')).rows.length === 0);
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
ok('seller cannot ship an unpaid order', await throws(() => as(seller1, "update orders set status = 'shipped', updated_at = now() where id = 'o1'")));
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
await db.exec(`insert into subscription_plans (id, name) values ('basic', 'Basic') on conflict do nothing; insert into fx_rates (rates) values ('{"KES":129}')`);
r = await as('anon', 'select id from subscription_plans order by sort_order, price_kes');
ok('anon reads plans, the seeded launch plans included', r.rows.map((p) => p.id).join() === 'basic,starter,growth,pro', JSON.stringify(r.rows));
ok('seller cannot edit plans', (await as(seller1, "update subscription_plans set price_usd = 0 returning id")).rows.length === 0);
r = await as(admin, "insert into subscription_plans (id, name) values ('premium', 'Premium') on conflict (id) do update set name = excluded.name returning id");
ok('admin upserts plans', r.rows.length === 1);
ok('seller cannot add plans', await throws(() => as(seller1, "insert into subscription_plans (id, name) values ('free', 'Free')")));
ok('seller cannot delete plans', (await as(seller1, "delete from subscription_plans where id = 'premium' returning id")).rows.length === 0);
ok('admin deletes plans', (await as(admin, "delete from subscription_plans where id = 'premium' returning id")).rows.length === 1);
r = (await as('anon', "select price_kes, listing_limit, order_limit, store_limit, support_level, is_popular, is_active, features from subscription_plans where id = 'growth'")).rows[0];
ok('plans: Growth is seeded with the §16 terms', Number(r?.price_kes) === 4000 && r.listing_limit === 500 && r.order_limit === 1000 && r.store_limit === 3 && r.support_level === 'priority' && r.is_popular && r.is_active && r.features.advancedAnalytics === true, JSON.stringify(r));
r = (await as('anon', "select listing_limit, order_limit, store_limit from subscription_plans where id = 'starter'")).rows[0];
ok('plans: Starter is 25 listed products, 100 orders, 1 store', r?.listing_limit === 25 && r.order_limit === 100 && r.store_limit === 1, JSON.stringify(r));
r = (await as('anon', "select listing_limit, order_limit, store_limit from subscription_plans where id = 'pro'")).rows[0];
ok('plans: Pro is unlimited listings and orders, 10 stores', r?.listing_limit === -1 && r.order_limit === -1 && r.store_limit === 10, JSON.stringify(r));
r = await as(admin, `update subscription_plans set listing_limit = 75, support_level = 'dedicated', is_active = false, sort_order = 5,
  features = '{"customDomain": true, "betaThemes": false}' where id = 'starter' returning id`);
ok('plans: admin edits every field', r.rows.length === 1);
r = await as(admin, "select 1 from audit_logs where action = 'plan.update' and entity_id = 'starter'");
ok('plans: the edit is audited', r.rows.length >= 1);
ok('plans: a limit below -1 is refused', await throws(() => as(admin, "update subscription_plans set order_limit = -2 where id = 'starter'")));
ok('plans: zero stores is refused', await throws(() => as(admin, "update subscription_plans set store_limit = 0 where id = 'starter'")));
ok('plans: a negative price is refused', await throws(() => as(admin, "update subscription_plans set price_kes = -1 where id = 'starter'")));
ok('plans: a zero-day period is refused', await throws(() => as(admin, "update subscription_plans set billing_period_days = 0 where id = 'starter'")));
ok('plans: an unknown support level is refused', await throws(() => as(admin, "update subscription_plans set support_level = 'vip' where id = 'starter'")));
ok('plans: a non-boolean feature flag is refused', await throws(() => as(admin, `update subscription_plans set features = '{"customDomain": "yes"}' where id = 'starter'`)));
ok('plans: features must be an object', await throws(() => as(admin, "update subscription_plans set features = '[]' where id = 'starter'")));
ok('plans: a blank name is refused', await throws(() => as(admin, "update subscription_plans set name = '  ' where id = 'starter'")));
ok('plans: an id that is not a slug is refused', await throws(() => as(admin, "insert into subscription_plans (id, name) values ('Big Plan!', 'Big')")));
ok('plans: more than 12 perks are refused', await throws(() => as(admin, "update subscription_plans set perks = $1 where id = 'starter'", [Array.from({ length: 13 }, (_, i) => 'perk ' + i)])));
await as('postgres', `update subscription_plans set listing_limit = 25, support_level = 'standard', is_active = true, sort_order = 10,
  features = '{"customDomain": false, "advancedAnalytics": false}' where id = 'starter'`);
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

// ---- 20260928000000_security_hardening.sql: SELLORA_SECURITY_AUDIT.md's
// findings, each checked by the name it has there.
const B2 = '66666666-6666-6666-6666-666666666666';
const S3 = '77777777-7777-7777-7777-777777777777';
const buyer2 = { id: B2 };
const one = async (who, sql, params) => (await (who === 'service' ? asService(sql, params) : as(who, sql, params))).rows[0];

console.log('H3/H4/L7: subscription activation');
await as('postgres', "insert into billing_history (id, seller_id, plan_id, amount_kes) values ('bh-buyer', $1, 'basic', 999)", [B1]);
ok('H4: a buyer cannot be activated as a seller', await throws(() => asService("select public.activate_subscription('bh-buyer', 'INV-B')")));
r = await one('postgres', "select status from billing_history where id = 'bh-buyer'");
ok('H4: the refused entry is left pending, not half-applied', r.status === 'pending');
const endBefore = (await one('postgres', 'select current_period_end e from subscriptions where seller_id = $1', [S2])).e;
await as(admin, "update profiles set seller_status = 'suspended' where uid = $1", [S2]);
await as('postgres', "insert into billing_history (id, seller_id, plan_id, amount_kes, billing_period_days) values ('bh2', $1, 'basic', 999, 30)", [S2]);
r = await one('service', "select public.activate_subscription('bh2', 'INV-2') r");
ok('H3: paying records the payment but keeps a suspension', r.r.sellerStatus === 'suspended' &&
  (await one('postgres', 'select seller_status from profiles where uid = $1', [S2])).seller_status === 'suspended');
r = await one('postgres', 'select current_period_end e from subscriptions where seller_id = $1', [S2]);
ok('L7: an early renewal extends the period from its end',
  Math.abs(new Date(r.e) - new Date(endBefore) - 30 * 86400000) < 1000, `${endBefore} -> ${r.e}`);

console.log('H5: seller standing');
const gate = async (uid) => (await one('service', 'select public.seller_order_gate($1) g', [uid])).g;
ok('H5: an active, subscribed seller may take orders', await gate(S1) === 'ok');
ok('H5: a suspended seller may not', await gate(S2) === 'seller_inactive');
ok('H5: a buyer is not a seller', await gate(B1) === 'not_a_seller');
ok('H5: clients cannot call the order gate', await throws(() => as(seller1, 'select public.seller_order_gate($1)', [S1])));
await as('postgres', "update subscriptions set current_period_end = now() - interval '1 day' where seller_id = $1", [S1]);
ok('H5: a lapsed subscription stops orders', await gate(S1) === 'subscription_lapsed');
ok('H5: a lapsed seller cannot publish', await throws(() => as(seller1, "insert into products (store_id, id, seller_id, is_listed) values ($1, 'lapsed1', $2, true)", ['store-' + S1, S1])));
r = await as(seller1, "insert into products (store_id, id, seller_id, is_listed) values ($1, 'lapsed-draft', $2, false) returning id", ['store-' + S1, S1]);
ok('H5: a lapsed seller can still save drafts', r.rows.length === 1);
ok("H5: a lapsed seller's catalog leaves the storefront", (await as('anon', 'select id from storefront_products')).rows.length === 0);
r = await as(seller1, "update products set is_listed = false where id = 'p1' returning id");
ok('H5: a lapsed seller can still unlist', r.rows.length === 1);
await as('postgres', "update subscriptions set current_period_end = now() + interval '30 days' where seller_id = $1", [S1]);
await as('postgres', "update products set is_listed = true where id = 'p1'");

console.log('H6: plan limits');
await as('postgres', "update subscription_plans set listing_limit = 2 where id = 'basic'");
r = await as(seller1, "insert into products (store_id, id, seller_id, is_listed) values ($1, 'p2', $2, true) returning id", ['store-' + S1, S1]);
ok('H6: publishing up to the listing limit works', r.rows.length === 1);
const overLimit = await throws(() => as(seller1, "insert into products (store_id, id, seller_id, is_listed) values ($1, 'p3', $2, true)", ['store-' + S1, S1]));
ok('H6: publishing past the listing limit is refused', /listing limit/.test(overLimit?.message ?? ''), overLimit?.message);
ok('H6: publishing a draft past the limit is refused', await throws(() => as(seller1, "update products set is_listed = true where id = 'draft1'")));
r = await as(seller1, "insert into products (store_id, id, seller_id, is_listed) values ($1, 'p3', $2, false) returning id", ['store-' + S1, S1]);
ok('H6: drafts do not count', r.rows.length === 1);
r = await as(seller1, "insert into products (store_id, id, seller_id, title, is_listed) values ($1, 'p1', $2, 'Lamp v2', true) on conflict (store_id, id) do update set title = excluded.title returning id", ['store-' + S1, S1]);
ok('H6: re-saving an already listed product is not a new listing', r.rows.length === 1);
await as('postgres', "update subscription_plans set listing_limit = -1 where id = 'basic'");
ok('H6: a second store is refused on a one-store plan', await throws(() => as(seller1, "insert into stores (id, slug, seller_id, name) values ('s1b', 'second', $1, 'Second')", [S1])));
await as('postgres', "update subscription_plans set store_limit = 2 where id = 'basic'");
r = await as(seller1, "insert into stores (id, slug, seller_id, name) values ('s1b', 'second', $1, 'Second') returning id", [S1]);
ok('H6: a second store is allowed on a two-store plan', r.rows.length === 1);
await as('postgres', "insert into orders (id, code, buyer_id, seller_id, store_id, payment_status, status) values ('o-limit', 'L', $1, $2, $3, 'paid', 'processing')", [B1, S1, 'store-' + S1]);
await as('postgres', 'update subscriptions set order_limit = 1 where seller_id = $1', [S1]);
ok('H6: a spent order_limit stops orders', await gate(S1) === 'order_limit_reached');
await as('postgres', 'update subscriptions set order_limit = -1 where seller_id = $1', [S1]);

console.log('H1/H7: orders');
await as('postgres', "insert into orders (id, code, buyer_id, seller_id, store_id, payment_status, status, seller_revenue) values ('o2', 'o2', $1, $2, $3, 'paid', 'processing', 42)", [B1, S1, 'store-' + S1]);
r = await as(seller1, "update orders set status = 'shipped' where id = 'o2' returning status");
ok('H7: seller ships a paid order', r.rows[0]?.status === 'shipped');
ok('H7: seller cannot move an order backwards', await throws(() => as(seller1, "update orders set status = 'processing' where id = 'o2'")));
ok('H7: seller cannot cancel a paid order', await throws(() => as(seller1, "update orders set status = 'cancelled' where id = 'o2'")));
ok('H7: nor can an admin, outside the refund path', await throws(() => as(admin, "update orders set status = 'cancelled' where id = 'o2'")));
await as('postgres', "insert into orders (id, code, buyer_id, seller_id, store_id) values ('o3', 'o3', $1, $2, $3)", [B1, S1, 'store-' + S1]);
r = await as(admin, "update orders set status = 'cancelled' where id = 'o3' returning status");
ok('H7: an admin cancels an unpaid order', r.rows[0]?.status === 'cancelled');
ok('H1: a buyer cannot read seller_revenue', await throws(() => as(buyer, 'select seller_revenue from orders')));
r = await as(seller1, "select seller_revenue from seller_orders where id = 'o2'");
ok('H1: the seller reads it through seller_orders', Number(r.rows[0]?.seller_revenue) === 42);
ok('H1: a buyer sees nothing in seller_orders', (await as(buyer, 'select id from seller_orders')).rows.length === 0);
ok('H1: anon cannot read seller_orders', await throws(() => as('anon', 'select id from seller_orders')));
ok('H1: seller_orders cannot be written through', await throws(() => as(seller1, "update seller_orders set total = 1 where id = 'o2'")));

console.log('M7: order expiry');
await as('postgres', `insert into orders (id, code, buyer_id, seller_id, store_id, expires_at, payment_status, last_payment_attempt_at) values
  ('o-old', 'x', $1, $2, $3, now() - interval '1 minute', 'pending', null),
  ('o-trying', 'x', $1, $2, $3, now() - interval '1 minute', 'awaiting_confirmation', now() - interval '5 minutes'),
  ('o-fresh', 'x', $1, $2, $3, now() + interval '1 hour', 'pending', null)`, [B1, S1, 'store-' + S1]);
ok('M7: clients cannot run the sweep', await throws(() => as(admin, 'select public.expire_unpaid_orders()')));
r = await one('service', 'select public.expire_unpaid_orders() n');
const states = Object.fromEntries((await as('postgres', "select id, status from orders where id in ('o-old', 'o-trying', 'o-fresh')")).rows.map((x) => [x.id, x.status]));
ok('M7: an expired unpaid order is cancelled', r.n === 1 && states['o-old'] === 'cancelled');
ok('M7: one with a payment in flight gets its grace period', states['o-trying'] === 'pending');
ok('M7: one not yet expired is left alone', states['o-fresh'] === 'pending');

console.log('M8: storefront view and server-owned counters');
r = await as(seller1, `insert into products (store_id, id, seller_id, is_listed, sold_count, rating, variants) values ($1, 'p4', $2, true, 999, 5, '[{"vid":"v1","price":9,"costPrice":5}]') returning sold_count, rating`, ['store-' + S1, S1]);
ok('M8: a seller cannot seed sold_count/rating', r.rows[0]?.sold_count === 0 && Number(r.rows[0]?.rating) === 0);
await as(seller1, "update products set sold_count = 500 where id = 'p4'");
ok('M8: nor raise them later', (await one('postgres', "select sold_count from products where id = 'p4'")).sold_count === 0);
ok('M8: the storefront view has no cost_price', await throws(() => as('anon', 'select cost_price from storefront_products')));
r = await one('anon', "select variants from storefront_products where id = 'p4'");
ok("M8: variants lose their costPrice, keep the rest", r?.variants[0]?.costPrice === undefined && r?.variants[0]?.vid === 'v1' && r?.variants[0]?.price === 9);
ok('M8: the storefront view cannot be written through', await throws(() => as('anon', "update storefront_products set sell_price = 0")));
ok('M8: nor by a seller', await throws(() => as(seller1, "update storefront_products set sell_price = 0 where id = 'p4'")));
ok("M8: the owner still reads their own cost", (await as(seller1, "select cost_price from products where id = 'p4'")).rows.length === 1);
ok('H2: a negative price is refused', await throws(() => as(seller1, "update products set sell_price = -1 where id = 'p4'")));

console.log('M3: audit log');
r = await as('postgres', "select action, actor_role, details from audit_logs where entity_type = 'profile' and entity_id = $1 order by id", [S2]);
ok("M3: an admin's suspension is logged with its actor",
  r.rows.some((x) => x.action === 'profile.admin_update' && x.actor_role === 'admin' && x.details.changes.seller_status?.[1] === 'suspended'));
r = await as('postgres', "select count(*)::int n from audit_logs where entity_type = 'subscription_plan'");
ok('M3: plan edits are logged', r.rows[0].n > 0);
r = await as('postgres', "select count(*)::int n from audit_logs where entity_type = 'order' and entity_id = 'o2'");
ok('M3: order state changes are logged', r.rows[0].n > 0);
ok('M3: a seller cannot read the audit log', (await as(seller1, 'select id from audit_logs')).rows.length === 0);
ok('M3: an admin can', (await as(admin, 'select id from audit_logs')).rows.length > 0);
ok('M3: clients cannot write it', await throws(() => as(admin, "insert into audit_logs (actor_role, action, entity_type, entity_id) values ('admin', 'x', 'x', 'x')")));
ok('M3: nobody can edit it, not even the owner', await throws(() => as('postgres', "update audit_logs set action = 'x'")));
ok('M3: nor delete from it', await throws(() => as('postgres', 'delete from audit_logs')));
ok('M3: nor truncate it', await throws(() => as('postgres', 'truncate audit_logs')));

console.log('M4: ledger');
r = await as('postgres', "select entry_type from ledger_entries where order_id = 'o1' order by entry_type");
ok('M4: a paid order books payment, fee, supplier cost and seller earning',
  r.rows.map((x) => x.entry_type).join() === 'ORDER_PAYMENT,PLATFORM_FEE,SELLER_EARNING,SUPPLIER_COST', JSON.stringify(r.rows));
r = await as('postgres', "select amount, currency from ledger_entries where billing_history_id = 'bh1' and entry_type = 'SUBSCRIPTION_PAYMENT'");
ok('M4: a subscription payment is booked', Number(r.rows[0]?.amount) === 999 && r.rows[0].currency === 'KES');
await as('postgres', "update orders set refunded_amount = 10, refund_currency = 'KES', payment_status = 'partially_refunded' where id = 'o1'");
await as('postgres', "update orders set refunded_amount = 10 where id = 'o1'");
r = await as('postgres', "select amount from ledger_entries where order_id = 'o1' and entry_type = 'REFUND'");
ok('M4: a refund is booked once', r.rows.length === 1 && Number(r.rows[0].amount) === 10);
ok('M4: the ledger is append-only', await throws(() => as('postgres', 'update ledger_entries set amount = 0')));
ok('M4: nobody deletes from it', await throws(() => as('postgres', 'delete from ledger_entries')));
ok('M4: clients cannot write it', await throws(() => as(seller1, "insert into ledger_entries (entry_type, amount, currency) values ('REFUND', 1, 'KES')")));
ok('M4: a seller reads their own entries', (await as(seller2, 'select id from ledger_entries')).rows.length > 0);
ok('M4: a buyer reads none', (await as(buyer, 'select id from ledger_entries')).rows.length === 0);

console.log('M5: webhook events');
await asService("insert into webhook_events (provider, invoice_id, state, payload) values ('INTASEND', 'INV-9', 'COMPLETE', '{}')");
ok('M5: one row per (provider, invoice, state)', await throws(() => asService("insert into webhook_events (provider, invoice_id, state, payload) values ('INTASEND', 'INV-9', 'COMPLETE', '{}')")));
ok('M5: clients cannot read webhook events', (await as(seller1, 'select id from webhook_events')).rows.length === 0);
ok('M5: clients cannot write them', await throws(() => as(buyer, "insert into webhook_events (provider, invoice_id, payload) values ('INTASEND', 'x', '{}')")));

console.log('M6: one fee source');
r = await as('postgres', "select count(*)::int n from information_schema.columns where table_name = 'subscription_plans' and column_name = 'commission_percent'");
ok('M6: commission_percent is gone', r.rows[0].n === 0);

console.log('L2: account deletion');
await signUp(B2, 'buyer2@x.com', { role: 'buyer', name: 'Bea', store_id: 'store-' + S1 });
await as('postgres', "insert into orders (id, code, buyer_id, seller_id, store_id, status, payment_status, shipping_address) values ('o-b2', 'x', $1, $2, $3, 'delivered', 'paid', '{\"countryCode\":\"KE\",\"name\":\"Bea\",\"line1\":\"1 Road\"}')", [B2, S1, 'store-' + S1]);
ok('L2: clients cannot call the deletion function', await throws(() => as(buyer2, 'select public.delete_account_data($1)', [B2])));
r = await one('service', 'select public.delete_account_data($1) r', [B1]);
ok('L2: refused while a paid order is still in fulfilment', r.r.deleted === false && r.r.reason === 'open_orders');
r = await one('service', 'select public.delete_account_data($1) r', [B2]);
const gone = await one('postgres', 'select name, email from profiles where uid = $1', [B2]);
const member = await one('postgres', 'select email from store_customers where uid = $1', [B2]);
const addr = await one('postgres', "select shipping_address a from orders where id = 'o-b2'");
ok('L2: a buyer is scrubbed, their orders kept', r.r.deleted === true && gone.name === 'Deleted user' &&
  gone.email.endsWith('@deleted.invalid') && member.email === gone.email && addr.a.countryCode === 'KE' && !addr.a.line1);
ok('L2: an admin account is refused', await throws(() => asService('select public.delete_account_data($1)', [A1])));
await signUp(S3, 's3@x.com', { role: 'seller', name: 'Sam', store_name: 'Sams', ...terms });
r = await one('service', 'select public.delete_account_data($1) r', [S3]);
ok('L2: a seller is suspended on deletion', r.r.deleted === true &&
  (await one('postgres', 'select seller_status from profiles where uid = $1', [S3])).seller_status === 'suspended');

console.log('L3/L4/L5');
ok('L3: an overlong notification is refused', await throws(() => as(buyer, "insert into notifications (recipient_id, title, message) values ($1, 't', repeat('x', 2001))", [B1])));
ok('L3: an overlong store name is refused', await throws(() => as(seller1, "update stores set name = repeat('x', 121) where id = $1", ['store-' + S1])));
await as('postgres', "update auth.users set email = 'NEW@x.com' where id = $1", [S1]);
ok('L4: the profile email follows an Auth email change', (await one('postgres', 'select email from profiles where uid = $1', [S1])).email === 'new@x.com');
r = await one('postgres', "select has_table_privilege('anon', 'public.orders', 'TRUNCATE') t, has_table_privilege('authenticated', 'public.products', 'TRIGGER') g");
ok('L5: clients hold no TRUNCATE/TRIGGER', r.t === false && r.g === false);

// ---- 20260929000000_billing_usage.sql: implementation plan PHASE 3.
console.log('billing: usage');
await as('postgres', "insert into orders (id, code, buyer_id, seller_id, store_id, payment_status, status) values ('o-unpaid', 'U', $1, $2, $3, 'pending', 'pending')", [B1, S1, 'store-' + S1]);
let usage = (await one(seller1, 'select public.my_plan_usage() u')).u;
const listedS1 = Number((await one('postgres', 'select count(*) c from products where seller_id = $1 and is_listed', [S1])).c);
ok('usage: counts listed products, not drafts', usage.listingCount === listedS1 && listedS1 >= 2, JSON.stringify(usage));
r = await one('postgres', "select count(*) filter (where payment_status in ('paid', 'partially_refunded', 'refunded')) paid, count(*) total from orders where seller_id = $1", [S1]);
ok('usage: counts paid orders only', usage.orderCount === Number(r.paid) && usage.orderCount < Number(r.total),
  `${usage.orderCount} vs ${r.paid}/${r.total}`);
ok('usage: reports the subscription and store counts', usage.subscriptionStatus === 'active' &&
  usage.planId === 'basic' && usage.storeCount === 2 && usage.storeLimit === 2, JSON.stringify(usage));
await as('postgres', 'update subscriptions set order_limit = $2 where seller_id = $1', [S1, usage.orderCount]);
ok('usage: at orderCount = orderLimit, checkout refuses too', await gate(S1) === 'order_limit_reached' &&
  (await one(seller1, 'select public.my_plan_usage() u')).u.orderLimit === usage.orderCount);
await as('postgres', 'update subscriptions set order_limit = $2 where seller_id = $1', [S1, usage.orderCount + 1]);
ok('usage: one below the limit, checkout allows it', await gate(S1) === 'ok');
await as('postgres', 'update subscriptions set order_limit = -1 where seller_id = $1', [S1]);
ok('usage: anon cannot ask', await throws(() => as('anon', 'select public.my_plan_usage()')));
ok("usage: reads only the caller's own", (await one(seller2, 'select public.my_plan_usage() u')).u.listingCount === 0);

console.log('billing: downgrades');
await as('postgres', "insert into subscription_plans (id, name, listing_limit) values ('tiny', 'Tiny', 1)");
const oldest = (await one('postgres', 'select id from products where seller_id = $1 and is_listed order by created_at, id limit 1', [S1])).id;
await as('postgres', "insert into billing_history (id, seller_id, plan_id, amount_kes) values ('bh-down', $1, 'tiny', 1)", [S1]);
await asService("select public.activate_subscription('bh-down', 'INV-DOWN')");
r = await as('postgres', 'select id from products where seller_id = $1 and is_listed', [S1]);
ok('downgrade: listings above the new cap are unlisted', r.rows.length === 1, JSON.stringify(r.rows));
ok('downgrade: the oldest listing is the one kept', r.rows[0]?.id === oldest);
r = await one('postgres', "select details from audit_logs where action = 'subscription.listings_unlisted' and entity_id = $1", [S1]);
ok('downgrade: the unlisting is audited', r?.details?.unlisted === listedS1 - 1 && r.details.listingLimit === 1, JSON.stringify(r));
await as('postgres', "update subscriptions set current_period_start = current_period_start where seller_id = $1", [S1]);
ok('downgrade: an update that keeps the plan changes nothing',
  (await as('postgres', 'select id from products where seller_id = $1 and is_listed', [S1])).rows.length === 1);
ok('downgrade: clients cannot call the trigger function', await throws(() => as(seller1, 'select public.subscriptions_enforce_listing_cap()')));

// ---- 20260930000000_listing_sync.sql: implementation plan PHASE 4.
console.log('listing sync');
await asService("update products set supplier_alert = 'below_cost', supplier_checked_at = now(), cost_price = 19 where id = 'p1'");
r = await one('postgres', "select supplier_alert, supplier_checked_at, cost_price from products where id = 'p1'");
ok('sync: the server can flag a listing and refresh its cost', r.supplier_alert === 'below_cost' && r.supplier_checked_at && Number(r.cost_price) === 19);
await as(seller1, "update products set supplier_alert = null, supplier_checked_at = null, title = 'Lamp v3' where id = 'p1'");
r = await one('postgres', "select supplier_alert, supplier_checked_at, title from products where id = 'p1'");
ok('sync: a seller cannot clear their own alert', r.supplier_alert === 'below_cost' && r.supplier_checked_at && r.title === 'Lamp v3');
r = await as(seller1, "insert into products (store_id, id, seller_id, is_listed, supplier_alert, supplier_checked_at) values ($1, 'p-new', $2, false, 'unavailable', now()) returning supplier_alert, supplier_checked_at", ['store-' + S1, S1]);
ok('sync: a seller cannot insert a listing pre-checked', r.rows[0].supplier_alert === null && r.rows[0].supplier_checked_at === null);
ok('sync: only known alerts are stored', await throws(() => asService("update products set supplier_alert = 'fine' where id = 'p1'")));
r = await one(seller1, "select supplier_alert from products where id = 'p1'");
ok('sync: the seller can read the alert', r?.supplier_alert === 'below_cost');

// ---- 20260930000100_deployment_report.sql: scripts/preflight.js's source.
console.log('deployment report');
r = (await one('service', 'select public.deployment_report() r')).r;
ok('report: runs without Supabase-only schemas', r.appliedMigrations === null && r.vaultSecrets === null && r.cronJobs === null);
ok('report: counts plans, admins and the bucket', r.plans.includes('basic') && Number(r.admins) >= 1 && r.storageBucket === true, JSON.stringify(r));
ok('report: counts approved sellers without a current subscription', Number.isInteger(Number(r.activeSellersWithoutSubscription)));
ok('report: clients cannot read it', await throws(() => as(admin, 'select public.deployment_report()')));

// ---- 20261003000000_admin_order_refunds.sql: implementation plan PHASE 8.
console.log('admin refund view');
await as('postgres', "update orders set total_kes = 1300, refund_error = 'boom' where id = 'o2'");
r = await one(admin, "select total_kes, refund_status, refund_error, refunds from admin_order_refunds where id = 'o2'");
ok('refunds: admin reads the charged amount and refund state', Number(r?.total_kes) === 1300 && r.refund_status === 'NONE' && r.refund_error === 'boom' && Array.isArray(r.refunds));
ok('refunds: the seller sees nothing', (await as(seller1, 'select id from admin_order_refunds')).rows.length === 0);
ok('refunds: nor does the buyer', (await as(buyer, 'select id from admin_order_refunds')).rows.length === 0);
ok('refunds: anon cannot read it', await throws(() => as('anon', 'select id from admin_order_refunds')));
ok('refunds: the view cannot be written through', await throws(() => as(admin, "update admin_order_refunds set refunded_amount = 0 where id = 'o2'")));
ok('refunds: total_kes stays off the shared grant', await throws(() => as(seller1, "select total_kes from orders where id = 'o2'")));

// ---- 20261003000100_discounts.sql: implementation plan PHASE 9.
console.log('discounts');
const st1 = 'store-' + S1, st2 = 'store-' + S2;
await as(seller1, "insert into discounts (id, store_id, code, kind, value) values ('d1', $1, 'SAVE10', 'percentage', 10)", [st1]);
ok('discounts: a seller creates a code for their own store', (await as(seller1, "select id from discounts where id = 'd1'")).rows.length === 1);
ok("discounts: not for another seller's store", await throws(() => as(seller1, "insert into discounts (store_id, code, kind, value) values ($1, 'NOPE', 'percentage', 10)", [st2])));
ok('discounts: another seller cannot read them', (await as(seller2, 'select id from discounts')).rows.length === 0);
ok('discounts: nor can a buyer', (await as(buyer, 'select id from discounts')).rows.length === 0);
ok('discounts: nor anon', (await as('anon', 'select id from discounts')).rows.length === 0);
ok('discounts: admin can', (await as(admin, "select id from discounts where id = 'd1'")).rows.length === 1);
ok('discounts: codes are stored upper-case', await throws(() => as(seller1, "insert into discounts (store_id, code, kind, value) values ($1, 'lower', 'percentage', 10)", [st1])));
ok('discounts: a percentage cannot exceed 100', await throws(() => as(seller1, "insert into discounts (store_id, code, kind, value) values ($1, 'BIG', 'percentage', 101)", [st1])));
ok('discounts: one code per store', await throws(() => as(seller1, "insert into discounts (store_id, code, kind, value) values ($1, 'SAVE10', 'fixed_amount', 5)", [st1])));
ok('discounts: a code cannot move to another store', await throws(() => as(seller1, "update discounts set store_id = $1 where id = 'd1'", [st2])));
ok("discounts: another seller cannot change it", (await as(seller2, "update discounts set value = 99 where id = 'd1' returning id")).rows.length === 0);

r = await one('anon', "select public.storefront_discount($1, ' save10 ') d", [st1]);
ok('lookup: anyone with the code reads its terms, case-insensitively', r.d?.code === 'SAVE10' && r.d.kind === 'percentage' && Number(r.d.value) === 10, JSON.stringify(r));
ok('lookup: the terms carry no usage figures', r.d && !('usageLimit' in r.d) && !('id' in r.d));
ok('lookup: an unknown code is null', (await one('anon', "select public.storefront_discount($1, 'NOPE') d", [st1])).d === null);
ok("lookup: a code is only valid in its own store", (await one('anon', "select public.storefront_discount($1, 'SAVE10') d", [st2])).d === null);
await as(seller1, "update discounts set is_active = false where id = 'd1'");
ok('lookup: an inactive code is null', (await one('anon', "select public.storefront_discount($1, 'SAVE10') d", [st1])).d === null);
await as(seller1, "update discounts set is_active = true, starts_at = now() + interval '1 day' where id = 'd1'");
ok('lookup: a code that has not started is null', (await one('anon', "select public.storefront_discount($1, 'SAVE10') d", [st1])).d === null);
await as(seller1, "update discounts set starts_at = now() - interval '2 days', ends_at = now() - interval '1 day' where id = 'd1'");
ok('lookup: an ended code is null', (await one('anon', "select public.storefront_discount($1, 'SAVE10') d", [st1])).d === null);
await as(seller1, "update discounts set ends_at = null, usage_limit = 1 where id = 'd1'");

const discountOrder = (id, buyerId, discountId, store = st1) => as('postgres',
  "insert into orders (id, code, buyer_id, seller_id, store_id, discount_id, discount_code, discount_amount) values ($1, $1, $2, $3, $4, $5, 'SAVE10', 3)",
  [id, buyerId, S1, store, discountId]);
await discountOrder('o-d1', B1, 'd1');
const exhausted = await throws(() => discountOrder('o-d2', B2, 'd1'));
ok('limits: a code past its usage limit is refused at insert', /discount_exhausted/.test(exhausted?.message ?? ''), exhausted?.message);
ok('limits: and the lookup stops offering it', (await one('anon', "select public.storefront_discount($1, 'SAVE10') d", [st1])).d === null);
await as('postgres', "update orders set status = 'cancelled' where id = 'o-d1'");
ok('limits: a cancelled order gives its use back', (await one('anon', "select public.storefront_discount($1, 'SAVE10') d", [st1])).d?.code === 'SAVE10');
await as(seller1, "update discounts set usage_limit = null, once_per_customer = true where id = 'd1'");
await discountOrder('o-d3', B1, 'd1');
const again = await throws(() => discountOrder('o-d4', B1, 'd1'));
ok('limits: once per customer refuses a second order', /discount_already_used/.test(again?.message ?? ''), again?.message);
ok('limits: another customer may still use it', !(await throws(() => discountOrder('o-d5', B2, 'd1'))));
const wrongStore = await throws(() => discountOrder('o-d6', B1, 'd1', st2));
ok("limits: a code cannot be used on another store's order", /discount_unavailable/.test(wrongStore?.message ?? ''), wrongStore?.message);
await as(seller1, "update discounts set is_active = false where id = 'd1'");
ok('limits: an inactive code is refused at insert', /discount_unavailable/.test((await throws(() => discountOrder('o-d7', B2, 'd1')))?.message ?? ''));
await as(seller1, "update discounts set is_active = true where id = 'd1'");

r = await one(buyer, "select discount_code, discount_amount from orders where id = 'o-d3'");
ok('orders: the buyer sees the code and what it took off', r?.discount_code === 'SAVE10' && Number(r.discount_amount) === 3);
ok('orders: the USD bookkeeping stays server-only', await throws(() => as(buyer, "select discount_amount_usd from orders where id = 'o-d3'")));
ok('orders: a client cannot write the discount', await throws(() => as(seller1, "update orders set discount_amount = 0 where id = 'o-d3'")));
r = await one(seller1, "select discount_id, discount_code from seller_orders where id = 'o-d3'");
ok('orders: the seller sees it through seller_orders', r?.discount_id === 'd1' && r.discount_code === 'SAVE10');

r = await as(seller1, 'select * from public.store_discount_usage($1)', [st1]);
ok('usage: the owner reads uses per code', r.rows.length === 1 && r.rows[0].uses === 2, JSON.stringify(r.rows));
ok("usage: another seller reads nothing of it", (await as(seller2, 'select * from public.store_discount_usage($1)', [st1])).rows.length === 0);
ok('usage: anon cannot ask', await throws(() => as('anon', 'select * from public.store_discount_usage($1)', [st1])));
ok('usage: clients cannot call discount_uses', await throws(() => as(seller1, "select public.discount_uses('d1')")));

ok('delete: a used code cannot be deleted', await throws(() => as(seller1, "delete from discounts where id = 'd1'")));
await as(seller1, "insert into discounts (id, store_id, code, kind, value) values ('d2', $1, 'FIVEOFF', 'fixed_amount', 5)", [st1]);
await as(seller2, "delete from discounts where id = 'd2'");
ok("delete: another seller cannot delete it", (await as('postgres', "select id from discounts where id = 'd2'")).rows.length === 1);
await as(seller1, "delete from discounts where id = 'd2'");
ok('delete: an unused code can be', (await as('postgres', "select id from discounts where id = 'd2'")).rows.length === 0);


// ---- 20261003000200_admin_platform.sql: implementation plan PHASE 10/12.
console.log('store suspension');
const listedBefore = (await as('anon', 'select id from storefront_products where store_id = $1', [st1])).rows.length;
ok('suspension: the store has a visible catalog to begin with', listedBefore > 0, String(listedBefore));
ok('suspension: the owner cannot suspend or unsuspend', await throws(() => as(seller1, 'update stores set is_suspended = true where id = $1', [st1])));
ok('suspension: nor write the reason', await throws(() => as(seller1, "update stores set suspension_reason = 'x' where id = $1", [st1])));
r = await as(admin, "update stores set is_suspended = true, suspension_reason = 'Counterfeit listings', suspended_at = now() where id = $1 returning id", [st1]);
ok('suspension: admin suspends a store', r.rows.length === 1);
ok('suspension: its catalog leaves the storefront', (await as('anon', 'select id from storefront_products where store_id = $1', [st1])).rows.length === 0);
r = await one('anon', 'select is_suspended, suspension_reason from stores where id = $1', [st1]);
ok('suspension: the storefront can tell it is suspended', r?.is_suspended === true && r.suspension_reason === 'Counterfeit listings');
r = await as(seller1, "update stores set tagline = 'still mine' where id = $1 returning id", [st1]);
ok('suspension: the owner can still edit the rest of the store', r.rows.length === 1);
r = await as(seller1, 'select id from products where store_id = $1', [st1]);
ok('suspension: the owner still sees their own products', r.rows.length > 0);
await as(admin, 'update stores set is_suspended = false, suspension_reason = null, suspended_at = null where id = $1', [st1]);
ok('suspension: lifting it restores the catalog', (await as('anon', 'select id from storefront_products where store_id = $1', [st1])).rows.length === listedBefore);

console.log('platform metrics');
await as('postgres', "insert into orders (id, code, buyer_id, seller_id, store_id, payment_status, total_kes, service_fee_amount_usd, fx_rate, refunded_amount, refund_currency) values ('o-m1', 'M1', $1, $2, $3, 'paid', 1000, 2, 130, 0, null), ('o-m2', 'M2', $1, $2, $3, 'partially_refunded', 500, 1, 130, 200, 'KES'), ('o-m3', 'M3', $1, $2, $3, 'pending', 9999, 50, 130, 0, null)", [B1, S1, st1]);
const metrics = (await one(admin, 'select public.admin_platform_metrics(7) m')).m;
const lifetime = metrics?.lifetime;
ok('metrics: admin reads KES totals over every paid order', lifetime && Number(lifetime.gmvKes) >= 1500 && Number(lifetime.paidOrders) >= 2, JSON.stringify(lifetime));
ok('metrics: unpaid orders are left out', Number(lifetime?.gmvKes) < 9999);
ok('metrics: the fee is the USD snapshot at its FX rate', Number(metrics?.window.serviceFeesKes) >= 390, JSON.stringify(metrics?.window));
ok('metrics: KES refunds are counted', Number(lifetime?.refundsKes) >= 200);
ok('metrics: one series point per day of the window', metrics?.series.length === 7 && metrics.series.every((p) => 'gmvKes' in p && 'orders' in p));
ok('metrics: today carries the new orders', Number(metrics?.series.at(-1).orders) >= 2, JSON.stringify(metrics?.series.at(-1)));
ok('metrics: subscriptions are summarized', metrics?.subscriptions && 'active' in metrics.subscriptions && 'lapsed30d' in metrics.subscriptions && 'mrrKes' in metrics.subscriptions, JSON.stringify(metrics?.subscriptions));
ok('metrics: the window is clamped', (await one(admin, "select jsonb_array_length(public.admin_platform_metrics(0) -> 'series') n")).n === 1);
ok('metrics: a seller cannot read them', await throws(() => as(seller1, 'select public.admin_platform_metrics(30)')));
ok('metrics: nor anon', await throws(() => as('anon', 'select public.admin_platform_metrics(30)')));

console.log('client errors');
await as(buyer, "select public.report_client_error(E'TypeError: x is null\nmore', 'at foo (main.dart:1)', '{\"route\": \"/s/x\"}')");
await as('anon', "select public.report_client_error('Boom', null, '{}')");
r = await as(admin, 'select user_id, fingerprint, message, stack, context from client_errors order by id');
ok('errors: signed-in and anonymous reports are kept', r.rows.length === 2 && r.rows[0].user_id === B1 && r.rows[1].user_id === null, JSON.stringify(r.rows));
ok('errors: the context is kept', r.rows[0]?.context?.route === '/s/x');
ok('errors: repeats share a fingerprint by first line', r.rows[0]?.fingerprint === (await one('postgres', "select md5('TypeError: x is null') f")).f);
await as(buyer, 'select public.report_client_error($1, null, $2::jsonb)', ['big', JSON.stringify({ blob: 'x'.repeat(5000) })]);
r = await one(admin, "select context from client_errors where message = 'big'");
ok('errors: an oversized context is dropped', r && Object.keys(r.context).length === 0);
await as(buyer, 'select public.report_client_error($1)', ['y'.repeat(5000)]);
r = await one(admin, "select char_length(message) n from client_errors where message like 'yyy%'");
ok('errors: the message is capped', r?.n === 2000);
ok('errors: a non-admin cannot read them', (await as(buyer, 'select id from client_errors')).rows.length === 0);
ok('errors: nobody writes the table directly', await throws(() => as(buyer, "insert into client_errors (fingerprint, message) values ('f', 'm')")));
for (let i = 0; i < 31; i++) await as(seller2, "select public.report_client_error('loop')");
r = await one(admin, "select count(*)::int n from client_errors where message = 'loop'");
ok('errors: a signed-in user is capped at 30 an hour, and the 31st is dropped silently', r.n === 30, String(r.n));

// ---- 20261003000300_orders_import_fees.sql: TODO.md §13-15.
console.log('service fee settings');
r = await one(seller1, 'select public.service_fee_settings() s');
ok('fees: with no setting it is 7% on the goods only', Number(r.s.serviceFeeRate) === 0.07 && r.s.chargeOnShipping === false, JSON.stringify(r.s));
ok('fees: anon cannot read them', await throws(() => as('anon', 'select public.service_fee_settings()')));
ok('fees: a seller cannot set them', await throws(() => as(seller1, `insert into app_config (key, value) values ('fees', '{"serviceFeeRate": 0}')`)));
await as(admin, `insert into app_config (key, value) values ('fees', '{"serviceFeeRate": 0.05, "chargeOnShipping": true}')`);
r = await one(seller1, 'select public.service_fee_settings() s');
ok('fees: an admin sets the rate and the shipping switch', Number(r.s.serviceFeeRate) === 0.05 && r.s.chargeOnShipping === true, JSON.stringify(r.s));
ok('fees: a rate over 30% is refused', await throws(() => as(admin, `update app_config set value = '{"serviceFeeRate": 0.5}' where key = 'fees'`)));
ok('fees: a negative rate is refused', await throws(() => as(admin, `update app_config set value = '{"serviceFeeRate": -0.01}' where key = 'fees'`)));
ok('fees: a missing rate is refused', await throws(() => as(admin, `update app_config set value = '{"chargeOnShipping": true}' where key = 'fees'`)));
ok('fees: a non-boolean shipping switch is refused', await throws(() => as(admin, `update app_config set value = '{"serviceFeeRate": 0.07, "chargeOnShipping": "yes"}' where key = 'fees'`)));
r = await one(admin, "select actor_id, details from audit_logs where entity_type = 'app_config' and entity_id = 'fees' order by id desc limit 1");
ok('fees: a change is audited with who made it', r?.actor_id === A1 && Number(r.details.new.serviceFeeRate) === 0.05, JSON.stringify(r));
await as(admin, `update app_config set value = '{"serviceFeeRate": 0.07}' where key = 'fees'`);
await as('postgres', "insert into orders (id, code, buyer_id, seller_id, store_id, service_fee_rate, service_fee_amount) values ('o-fee', 'F', $1, $2, $3, 0.05, 5)", [B1, S1, st1]);
r = await one(seller1, "select service_fee_rate, service_fee_base, service_fee_amount from seller_orders where id = 'o-fee'");
ok('fees: an order keeps its own rate after the setting changes', Number(r.service_fee_rate) === 0.05 && Number(r.service_fee_amount) === 5 && r.service_fee_base === 'subtotal', JSON.stringify(r));
ok('fees: a seller cannot rewrite an order fee', await throws(() => as(seller1, "update orders set service_fee_rate = 0 where id = 'o-fee'")));
r = await one(buyer, "select service_fee_base from orders where id = 'o-fee'");
ok('fees: the buyer can read the fee base', r?.service_fee_base === 'subtotal');

console.log('order management');
r = await one(seller1, "select cj_order_status, cj_order_number from seller_orders where id = 'o-fee'");
ok('orders: the seller reads the CJ fulfilment state', r?.cj_order_status === 'NOT_PUSHED');
ok('orders: a buyer cannot read it', await throws(() => as(buyer, 'select cj_order_status from orders')));
r = await as(seller1, "update orders set status = 'cancelled' where id = 'o-fee' returning status");
ok('orders: a seller cancels an unpaid order', r.rows[0]?.status === 'cancelled');
await as('postgres', "insert into orders (id, code, buyer_id, seller_id, store_id, payment_status) values ('o-inflight', 'IF', $1, $2, $3, 'awaiting_confirmation')", [B1, S1, st1]);
ok('orders: not one with a payment in flight', await throws(() => as(seller1, "update orders set status = 'cancelled' where id = 'o-inflight'")));
await as('postgres', "insert into orders (id, code, buyer_id, seller_id, store_id) values ('o-other', 'OT', $1, $2, $3)", [B1, S2, st2]);
r = await as(seller1, "update orders set status = 'cancelled' where id = 'o-other' returning id");
ok("orders: nor another seller's order", r.rows.length === 0);
r = await as(seller1, "insert into order_notes (order_id, body, author_id, author_role, created_at) values ('o-inflight', '  Called the buyer  ', $1, 'admin', '2000-01-01') returning author_id, author_role, body, created_at", [S2]);
const note = r.rows[0];
ok('notes: the seller adds a note, stamped with their own identity and time', note?.author_id === S1 && note.author_role === 'seller' && note.body === 'Called the buyer' && new Date(note.created_at).getFullYear() > 2000, JSON.stringify(note));
ok('notes: not on an order they cannot manage', await throws(() => as(seller1, "insert into order_notes (order_id, body) values ('o-other', 'x')")));
ok('notes: nor an empty one', await throws(() => as(seller1, "insert into order_notes (order_id, body) values ('o-inflight', '   ')")));
ok('notes: the buyer cannot read them', (await as(buyer, 'select id from order_notes')).rows.length === 0);
ok('notes: nor anon', await throws(() => as('anon', 'select id from order_notes')));
ok('notes: they cannot be edited', await throws(() => as(seller1, "update order_notes set body = 'x'")));
ok('notes: or deleted', await throws(() => as('postgres', 'delete from order_notes')));
await as(admin, "insert into order_notes (order_id, body) values ('o-inflight', 'Checked with IntaSend')");
await as('postgres', "update orders set payment_status = 'paid', status = 'processing', tracking_number = 'TRK1' where id = 'o-inflight'");
r = await as(seller1, "select kind, actor_role, details from public.order_timeline('o-inflight')");
const kinds = r.rows.map((e) => e.kind);
ok('timeline: creation, then changes and notes', kinds[0] === 'created' && kinds.filter((k) => k === 'note').length === 2 && kinds.includes('change'), JSON.stringify(kinds));
const change = r.rows.find((e) => e.kind === 'change')?.details;
ok('timeline: a change carries old and new values, tracking included', change?.payment_status?.[1] === 'paid' && change?.tracking_number?.[1] === 'TRK1', JSON.stringify(change));
ok("timeline: an admin's note says so", r.rows.some((e) => e.kind === 'note' && e.actor_role === 'admin'));
ok('timeline: the buyer gets nothing', (await as(buyer, "select * from public.order_timeline('o-inflight')")).rows.length === 0);
ok("timeline: nor another seller", (await as(seller2, "select * from public.order_timeline('o-inflight')")).rows.length === 0);
ok('timeline: anon cannot call it', await throws(() => as('anon', "select * from public.order_timeline('o-inflight')")));

console.log('listing fields');
r = await as(seller1, "update products set tags = '{summer,lamp}', seo_title = 'Desk lamp', seo_description = 'A warm lamp' where id = 'p1' and store_id = $1 returning tags", [st1]);
ok('listing: the seller sets tags and SEO fields', r.rows[0]?.tags?.length === 2);
r = await one('anon', "select tags, seo_title, seo_description from storefront_products where id = 'p1' and store_id = $1", [st1]);
ok('listing: the storefront reads them', r?.seo_title === 'Desk lamp' && r.tags.includes('summer'), JSON.stringify(r));
ok('listing: more than 20 tags are refused', await throws(() => as(seller1, 'update products set tags = $2 where id = \'p1\' and store_id = $1', [st1, Array.from({ length: 21 }, (_, i) => 't' + i)])));
ok('listing: an empty tag is refused', await throws(() => as(seller1, "update products set tags = '{\"\"}' where id = 'p1' and store_id = $1", [st1])));
ok('listing: an overlong SEO description is refused', await throws(() => as(seller1, 'update products set seo_description = $2 where id = \'p1\' and store_id = $1', [st1, 'x'.repeat(321)])));

// ---- 20261003000500_billing_page.sql: TODO §17.
console.log('billing page');
await as('postgres', `update subscriptions set status = 'active', plan_id = 'starter', current_period_end = now() + interval '10 days',
  cancel_at_period_end = false, renewal_reminder_for = null where seller_id = $1`, [S1]);
await as('postgres', "insert into billing_history (id, seller_id, plan_id, plan_name, amount_kes, billing_period_days) values ('bh-inv', $1, 'starter', 'Starter', 1300, 30)", [S1]);
r = await one('postgres', "select invoice_number from billing_history where id = 'bh-inv'");
ok('invoice: a pending payment has no invoice number', r.invoice_number === null);
const endBeforeInvoice = (await one('postgres', 'select current_period_end e from subscriptions where seller_id = $1', [S1])).e;
await asService("select public.activate_subscription('bh-inv', 'INV-REF')");
r = await one(seller1, "select invoice_number, period_start, period_end from billing_history where id = 'bh-inv'");
ok('invoice: paying assigns a numbered invoice', /^INV-\d{4}-\d{6}$/.test(r?.invoice_number ?? ''), r?.invoice_number);
ok('invoice: it records the period the payment bought, from the old end',
  Math.abs(new Date(r.period_start) - new Date(endBeforeInvoice)) < 1000 &&
  Math.abs(new Date(r.period_end) - new Date(endBeforeInvoice) - 30 * 86400000) < 1000, JSON.stringify(r));
ok('invoice: the number cannot change', await throws(() => as('postgres', "update billing_history set invoice_number = 'INV-X' where id = 'bh-inv'")));
r = await as('postgres', "select count(*)::int n from billing_history where status = 'paid' and invoice_number is null");
ok('invoice: every paid entry has a number', r.rows[0].n === 0);
ok("invoice: another seller can't read it", (await as(seller2, "select id from billing_history where id = 'bh-inv'")).rows.length === 0);

r = await one(seller1, 'select public.my_plan_usage() u');
ok('usage: reports the period start and no cancellation', r.u.currentPeriodStart && r.u.cancelAtPeriodEnd === false, JSON.stringify(r.u));
ok('cancel: the seller cannot write the flag directly', (await as(seller1, 'update subscriptions set cancel_at_period_end = true returning seller_id')).rows.length === 0);
r = await one(seller1, "select public.cancel_my_subscription('  Too expensive  ') c");
ok('cancel: the seller cancels at period end', r.c.cancelAtPeriodEnd === true);
r = await one('postgres', 'select status, cancel_at_period_end, cancel_reason, cancelled_at, current_period_end > now() running from subscriptions where seller_id = $1', [S1]);
ok('cancel: the plan keeps running, flagged, with the trimmed reason', r.status === 'active' && r.running && r.cancel_at_period_end && r.cancel_reason === 'Too expensive' && r.cancelled_at, JSON.stringify(r));
ok('cancel: it is audited', (await as('postgres', "select 1 from audit_logs where action = 'subscription.cancel' and entity_id = $1", [S1])).rows.length === 1);
r = await one(seller1, 'select public.my_plan_usage() u');
ok('usage: shows the cancellation', r.u.cancelAtPeriodEnd === true && r.u.subscriptionStatus === 'active' && r.u.cancelledAt);
ok('cancel: an overlong reason is refused', await throws(() => as(seller1, 'select public.cancel_my_subscription($1)', ['x'.repeat(501)])));
ok('cancel: a buyer has nothing to cancel', await throws(() => as(buyer, 'select public.cancel_my_subscription()')));
ok('cancel: anon cannot call it', await throws(() => as('anon', 'select public.cancel_my_subscription()')));

await as('postgres', "update subscriptions set current_period_end = now() + interval '2 days' where seller_id = $1", [S1]);
r = await one('service', 'select public.send_renewal_reminders() n');
ok('reminders: none for a cancelled plan', (await as('postgres', "select 1 from notifications where recipient_id = $1 and title = 'Your plan ends soon'", [S1])).rows.length === 0);
r = await one(seller1, 'select public.resume_my_subscription() c');
ok('resume: the seller resumes', r.c.cancelAtPeriodEnd === false &&
  (await one('postgres', 'select cancel_at_period_end c, cancel_reason from subscriptions where seller_id = $1', [S1])).c === false);
await one('service', 'select public.send_renewal_reminders() n');
await one('service', 'select public.send_renewal_reminders() n');
r = await as(seller1, "select message from notifications where title = 'Your plan ends soon'");
ok('reminders: one per period once the end is three days off', r.rows.length === 1 && /Starter/.test(r.rows[0].message), JSON.stringify(r.rows));
ok('reminders: clients cannot send them', await throws(() => as(seller1, 'select public.send_renewal_reminders()')));

await one(seller1, 'select public.cancel_my_subscription() c');
await as('postgres', "insert into billing_history (id, seller_id, plan_id, plan_name, amount_kes, billing_period_days) values ('bh-inv2', $1, 'starter', 'Starter', 1300, 30)", [S1]);
await asService("select public.activate_subscription('bh-inv2', 'INV-REF2')");
r = await one('postgres', 'select cancel_at_period_end c, renewal_reminder_for is distinct from current_period_end rearmed from subscriptions where seller_id = $1', [S1]);
ok('renewing clears a cancellation and re-arms the reminder', r.c === false && r.rearmed, JSON.stringify(r));
const [inv1, inv2] = (await as('postgres', "select invoice_number n from billing_history where id in ('bh-inv', 'bh-inv2') order by id")).rows.map((x) => x.n);
ok('invoice: numbers are sequential', Number(inv2.slice(-6)) === Number(inv1.slice(-6)) + 1, `${inv1} ${inv2}`);
await as('postgres', "update subscriptions set current_period_end = now() - interval '1 day' where seller_id = $1", [S1]);
ok('resume: not once the period has ended', await throws(() => as(seller1, 'select public.resume_my_subscription()')));
ok('cancel: nor cancel', await throws(() => as(seller1, 'select public.cancel_my_subscription()')));
await as('postgres', "update subscriptions set current_period_end = now() + interval '20 days' where seller_id = $1", [S1]);

console.log('billing profile');
r = await as(seller1, "insert into seller_billing_profiles (seller_id, payment_method, mpesa_phone, billing_name, tax_id, updated_at) values ($1, 'mpesa', '254712345678', 'Amina Ltd', 'P051234567X', '2000-01-01') returning updated_at", [S1]);
ok('billing profile: the seller saves a payment method, stamped now', new Date(r.rows[0]?.updated_at).getFullYear() > 2000);
r = await as(seller1, "update seller_billing_profiles set payment_method = 'card' returning payment_method");
ok('billing profile: and changes it', r.rows[0]?.payment_method === 'card');
ok('billing profile: a malformed M-Pesa number is refused', await throws(() => as(seller1, "update seller_billing_profiles set mpesa_phone = '0712345678'")));
ok('billing profile: M-Pesa without a number is refused', await throws(() => as(seller1, "update seller_billing_profiles set payment_method = 'mpesa', mpesa_phone = null")));
ok('billing profile: an unknown method is refused', await throws(() => as(seller1, "update seller_billing_profiles set payment_method = 'paypal'")));
ok('billing profile: not for another seller', await throws(() => as(seller2, "insert into seller_billing_profiles (seller_id, payment_method) values ($1, 'card')", [S1])));
ok('billing profile: a buyer cannot have one', await throws(() => as(buyer, "insert into seller_billing_profiles (seller_id, payment_method) values ($1, 'card')", [B1])));
ok("billing profile: another seller can't read it", (await as(seller2, 'select seller_id from seller_billing_profiles')).rows.length === 0);
ok("billing profile: nor change it", (await as(seller2, "update seller_billing_profiles set tax_id = 'X' returning seller_id")).rows.length === 0);
ok('billing profile: anon reads nothing', (await as('anon', 'select seller_id from seller_billing_profiles')).rows.length === 0);
ok('billing profile: admin reads it', (await as(admin, 'select seller_id from seller_billing_profiles')).rows.length === 1);
const S4 = '88888888-8888-8888-8888-888888888888';
await signUp(S4, 'leaver@x.com', { role: 'seller', name: 'Leaver', store_name: 'Leaver Store', ...terms });
await as({ id: S4 }, "insert into seller_billing_profiles (seller_id, payment_method, mpesa_phone) values ($1, 'mpesa', '254711111111')", [S4]);
await one('service', 'select public.delete_account_data($1) r', [S4]);
ok('billing profile: account deletion removes it', (await as('postgres', 'select 1 from seller_billing_profiles where seller_id = $1', [S4])).rows.length === 0);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
