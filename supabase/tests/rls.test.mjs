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
ok('client cannot write billing history', await throws(() => as(seller1, "insert into billing_history (seller_id, plan_id) values ($1, 'basic')", [S1])));
r = await as('anon', "select rates from fx_rates where id = 'current'");
ok('anon reads fx', r.rows[0]?.rates?.KES === 129);

console.log('session revocation');
ok('client cannot revoke sessions', await throws(() => as(seller1, 'select public.revoke_user_sessions($1)', [S2])));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
