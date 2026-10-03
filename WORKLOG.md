# Work log

Append-only record of design and implementation work, newest first. Each entry states what was
decided, what actually changed on disk, and what is still blocked — so a later session can pick up
without re-deriving the reasoning.

---

## 2026-10-04 — TODO §20: storefront

**Status:** done in code and tested. **Not applied or deployed.** The new migration
`20261004000000_store_pages.sql` joins rollout step 1 in TODO.md and must land before this web build:
the storefront reads `storefront_pages`. A failed read only hides the pages; the seller's editor can't
save without the table. No Edge Function change: card payment now returns to the order page, which
`ALLOWED_REDIRECT_ORIGINS` accepts because it checks origin only.

**Why:** user request: "work on phase 20" (TODO.md §20 Storefront).

**Where it started:** `/s/:slug` was a five-tab app shell (shop, cart, orders, alerts, profile), the
same scaffold as the seller and admin portals. Only the home tab was in the store's theme. The
product page took its product from navigation arguments, so a shared or refreshed product link broke.
Checkout ended on the orders tab with a snackbar. There were no search, collections, order
confirmation, about, contact or policy pages.

**Decisions (made here, reversible):**
- **The storefront is a site, not an app shell.** Each §20 page has its own route under `/s/:slug`
  (`Routes.storefront*`, paths built by `StorefrontPaths` in `storefront_links.dart`). Each page sits
  in `StorefrontFrame` (load the store, show loading/missing/closed, apply the theme, title the tab)
  or `StorefrontPage` (the frame plus header, drawer and footer). The header has the store name
  (back to home), search, the cart with its count, and account. The drawer has the seller's menu,
  Shop all, Collections, Search, Your orders, and the store's pages. The tabbed `BuyerShellView` and
  its controller are deleted.
- **`StorefrontSession`** (permanent, in InitialBinding) loads the store, its published design, its
  pages and its categories once, for whichever page is opened first. Concurrent `ensure()` calls share
  one load. It also owns the browser tab's favicon: pages attach and detach, and the tab goes back to
  Sellora's only when the last storefront page closes. `StoreScope` still holds the store itself.
- **Checkout stays focused.** It renders in the store's theme but without the store header or menu.
- **"Collections" are categories.** There's still no collection model (PHASE 5), so
  `/collections` lists the categories that have listed products (`storeCategories`, read from up to
  1000 listings), using a Collections section's image for a category where the seller set one.
  `/collections/{handle}` resolves a slugged category name.
- **Shop and search are one page type** (`ProductListPage`). Its controller belongs to the page
  (`GetBuilder(global: false)`), not a route binding, because one collection can be opened on top of
  another from the drawer, and each needs its own controller.
- **Sellers write About, Contact and the four policies** (privacy, terms, shipping, refund) in Seller →
  Store pages. They're stored in a new `store_pages` table (owner writes, column grants, bounded
  lengths, contact email/phone allowed only on the contact page), and buyers read the
  `storefront_pages` view, which applies the same standing rule as products and designs. **Nothing
  is published on the seller's behalf.** Templates are offered, but a page exists only once saved,
  and a template's `[bracketed]` blanks block publishing (saving it hidden is allowed). The editor
  says the templates aren't legal advice. The contact page shows email, call and WhatsApp buttons.
  There's no contact form, because messages would need an inbox.
- **The order page is the confirmation.** Checkout lands on `/s/:slug/orders/{id}` with the placed
  order ("Thank you", plus what checkout said about payment), and card payment returns there too.
  Later it shows the order's status, payment, items, totals, address and tracking. It reads the order
  through a new `OrderRepository.buyerOrder` (RLS: own orders only) and refuses an order from another
  store.
- **Sign-in comes back to where it was asked for:** `?return=` (checkout, an order, order history).
  `AuthController.storeReturnPath` accepts only a path under the same store, with no `..` and not the
  login or register pages.
- **Links:** design links gained `collections`, `search` and `page:<kind>`, pickable in the builder.
  On the homepage, category, section and catalog links still scroll in place. Elsewhere they go to
  the collection, the homepage and the shop.

**What changed:**
- **Migration.** `store_pages` (+ touch trigger) and `storefront_pages`.
- **App.** Models: `StorePage`, `StorePageKind`, `StorePageTemplates`. `StorePageRepository` + Supabase
  implementation. `ProductRepository.storeCategories`, `OrderRepository.buyerOrder` (and the test
  fake's). `StorefrontSession`, and `lib/modules/storefront/shell/` (frame, page, header, drawer,
  footer, links). `lib/modules/storefront/pages/`: shop/search/collection, collections, store page.
  The product, cart, checkout, order history and account screens were rewritten as storefront pages.
  `OrderPage`. Seller → Store pages (`lib/modules/seller/store_pages/`, `/seller/store/pages`, linked
  from Profile). `StorefrontController` no longer loads the design.
- **Fixes along the way.** The cart's quantity and remove actions keyed on the product only, so two
  options of one product changed together; they now act on the line. The product page adds to the
  cart and stays (with a "View cart" action), and has "Buy now".

**Tests:** `flutter analyze`: only the two existing infos. `flutter test`: the one failure is the
known `seller_shell_controller_test` one. New `storefront_pages_test` (27): page validation and
templates, links and handles, the return-path guard, cart lines per option, the session (single
load, retry, customer), the product/collection/search/order controllers, the seller's page editor,
and widget tests that open pages straight from a URL (policy page, unpublished page, product link
then Buy now, collections, shop on phone and desktop, search from `?q=`, order confirmation, guest
order and account, unknown store). The shop-page test caught a real crash: its title's `Obx` read no
observable. `supabase npm test`: 393 RLS checks (17 new), 357 Deno steps. `flutter build web`
compiles. Not looked at in a browser, and not run against a real backend.

**Not done:**
- Sign-in and register pages are still Meridian-styled, not the store's theme.
- SEO: per-page titles are set, but meta descriptions and social cards need server-side rendering
  (the app is a hash-routed SPA).
- A real collection model, sorting the shop, related products, a contact form, a cookie banner.
- Notifications are a plain page under the account, not themed beyond the frame.

---

## 2026-10-04 — TODO §19: theme system

**Status:** done in code and tested. **No migration and no Edge Function change**, so this ships with
the web build alone. It still needs §18's `20261003000600_store_builder.sql` applied first.

**Why:** user request: "work on todo phase19" (TODO.md §19 Theme system).

**Where it started:** §18 gave every store one design document with a `themeId` field nobody read,
and theme settings that covered colors, two fonts, button shape and favicon. Every storefront had the
same layout style.

**Decisions (made here, reversible):**
- **Themes are defined in code** (`StoreTheme` in `lib/data/models/store_theme.dart`), not in a table.
  A theme only combines settings the renderer already draws, so adding one needs no migration and
  can't name anything the storefront can't render. Admin-managed themes (TODO §34 "themes") would
  need a table, plus a check that every value is one the app knows.
- **Theme model:** id, name, version, description, settings (colors, typography, buttons, layout
  style), a starter homepage built from the store's own name, tagline and banner, and the store
  categories it suits. **The thumbnail is drawn** from the settings (`ThemeThumbnail`: header, hero,
  a row of cards), so it can't drift from what the theme does and there are no image assets.
- **The five initial themes:** General Store (the §18 look, so existing designs are unchanged),
  Minimal, Modern, Fashion and Electronics. Each passes 4.5:1 text contrast on the background and on
  cards, and on its accent buttons. Their starter homepages hold only the store's own words, or
  neutral headings the seller edits. They have no testimonials, offers or delivery promises, because
  those would be made-up claims.
- **"Multiple themes" means the platform offers several, and a store applies one.** Applying copies
  the theme's settings into the store's design, which then belongs to the seller. Later edits to a
  theme in code don't change anyone's storefront. Instead a higher `version` makes the builder offer
  "Update to version N" (`StoreDesign.themeVersion`). A per-store library of several saved designs
  (Shopify's "theme library") is not built: it needs more than one design row per store.
- **Two ways to apply:** "Use this style" restyles and keeps every section. "Use with its homepage"
  also replaces the homepage sections, after a confirmation. The menu, announcement bar, footer and
  favicon always stay. Undo works until the next edit. Nothing is live until Publish.
- **Layout style is new theme settings**, read by the renderer through a `StoreStyle` theme extension:
  surface (card) color, corners (square/soft/rounded), cards (flat/outlined/shadow), product photo
  shape (square/portrait/landscape), section spacing, centered header and capital-letter headings.
  All seven are editable in Theme after applying. A document saved before today has none of them and
  reads exactly as before: surface = background, the rest defaults, and `themeId: meridian` aliases
  to General Store.
- **The store's category picks a suggested theme** (fashion → Fashion, electronics → Electronics,
  and so on), labelled in the gallery. Nothing is applied automatically.

**What changed:**
- **Model.** `StoreTheme`. `ThemeSettings` gained `surfaceHex`, `corners`, `cardStyle`, `imageShape`,
  `spacing`, `centeredHeader` and `uppercaseHeadings` (stored under `theme.style` and
  `theme.colors.surface`), each read defensively. `StoreDesign` gained `themeVersion`. Palettes
  carry a surface color, so Midnight's cards are dark too.
- **Renderer.** `StorefrontTheme` sets the surface on cards, inputs and chips, centers the app bar
  title when asked, and adds `StoreStyle`. The renderer uses it for spacing, radii, quote panels and
  title case. `ProductCard` takes a `ProductCardStyle`, and the grid sizes tiles for the photo shape.
- **Builder.** Theme now opens with the current theme (thumbnail, version, update offer) and "Change
  theme". That leads to a gallery of the five, marked Current or Suggested. Style controls follow the
  existing color and font fields. The contrast warning now also checks text on cards.
- **Two layout bugs fixed** that the new per-theme render tests found. Both were in §18 code, and
  real fonts only made them rarer. A product card overflowed its tile by a few pixels with a two-line
  title, a compare-at price and a sales count: the photo now takes the height the text leaves. A
  "Small" hero overflowed on a phone with a two-line name and a tagline: the hero height is now a
  minimum.

**Tests:** `flutter analyze`: only the two existing infos. `flutter test`: the one failure is the
known `seller_shell_controller_test` one. New `store_theme_test` (24): the five themes' contrast,
fonts and publishable homepages with a JSON round trip, legacy documents, hostile style values,
apply-keeps-content, suggestions, update offers, controller apply/undo, and every theme rendered
with products and its thumbnail at phone and desktop widths with no layout errors.
`flutter build web` compiles. Not looked at in a browser. Google Fonts aren't loaded in widget tests,
so the type in each theme was only seen in code.

**Not done:**
- Admin-managed themes, and themes as data (see above).
- A per-store theme library (several saved designs, one live).
- Product detail, cart and checkout still render in Meridian rather than the store's theme (from §18).
- A real screenshot thumbnail. The drawn one shows style, not the seller's photos.

---

## 2026-10-03 — TODO §18: store builder

**Status:** done in code and tested. **Not applied or deployed.** The new migration
`20261003000600_store_builder.sql` joins rollout step 1 in TODO.md. It must land before the new web
build: the storefront reads `storefront_designs`. It falls back to the starter layout if that read
fails, but the builder can't save without the table. No Edge Function change.

**Why:** user request: "work on phase 18" (TODO.md §18 Store builder; PHASE 6 in the plan).

**Where it started:** "Customize store" edited name, tagline, logo, banner and accent color, and
the storefront was one hard-coded layout (banner, title, search, chips, grid).

**Decisions (made here, reversible):**
- **One JSON design document per store, draft and published.** `store_designs.draft` is the
  owner's to write (column-level grants: `draft` only). `published` changes only through
  `publish_store_design()`, which audits, versions, and copies the accent onto
  `stores.primary_color_hex` so the screens still reading it match. Buyers read the public
  `storefront_designs` view, which hides suspended stores and sellers not in good standing,
  the same rule as `storefront_products`.
- **The app owns the schema; the database bounds it** (an object, 128 KB, at most 40 sections, a
  sections array required to publish). The model reads every document defensively. Unknown section
  types and duplicate ids are dropped, settings are coerced through each type's schema (lengths
  clipped, unknown options reset), fonts must be on the vetted list, and **any link or image that
  isn't an absolute http(s) URL is discarded on read**. A seller could write the JSON directly
  through the API, so this check runs where the storefront renders, not only in the editor.
  `javascript:` links never reach `launchUrl`.
- **Schema-driven editing.** Each `SectionType` lists its `SettingDef`s (text, textarea, image,
  select, toggle, link, products) and an optional `BlockSchema` with min/max. The builder's editor
  is generic over them, so a new section type is a schema entry plus a renderer widget.
- **Section types:** hero, featured products (newest, best sellers or hand-picked, up to 12), all
  products (the catalog: always present, can be moved but not removed, and publishing requires it to
  be visible), collections, banners (1–3), testimonials (up to 6), newsletter (one per page), text.
  The announcement bar, menu (up to 8 links) and footer (about, up to 8 links, six social networks,
  "Powered by Sellora" toggle) sit outside the section list.
- **"Collections" open a product category.** No collection model exists yet (PHASE 5), so a
  collection tile is a label, an image and the category it filters the catalog to. A real
  collection model can replace the block's `category` setting later.
- **Links stay on the page** where they can: home, all products, a category (filters the catalog
  and scrolls to it), a section (scrolls to it), or an external URL.
- **Theme scope.** The storefront tab (app bar included) renders in the seller's colors, fonts and
  button shape (`StorefrontTheme`). Product, cart and checkout pages stay Meridian for now. The
  favicon swaps in on the web storefront and goes back to Sellora's when it closes. `package:web`
  is now a direct dependency for this.
- **A store that never published** shows `StoreDesign.starter`: its banner as a hero (only an http(s)
  one; legacy inline `data:` banners aren't carried over), then the catalog, in its existing accent.
  Existing storefronts look the same until their seller publishes.
- **Newsletter.** `subscribe_to_store_newsletter()` (anon allowed) validates the address, refuses
  closed stores, lower-cases, and dedupes quietly so the answer never reveals who's subscribed. It is
  rate-limited to 60 an hour per store, because anonymous callers have no other key. The seller sees
  the list in the newsletter section's editor, copies it, and removes people. Sellora sends nothing.
- **Banner and accent moved out of "Customize store"** (now "Store details": name, tagline, logo,
  shipping zones) so two screens don't edit the same thing. After publishing, the builder updates the
  in-memory store's accent so Store details doesn't write the old one back.

**What changed:**
- **Migration.** `store_designs` (+ touch trigger), `publish_store_design`, `storefront_designs`,
  `newsletter_subscribers`, `subscribe_to_store_newsletter`.
- **App.** `StoreDesign` and friends (`lib/data/models/store_design.dart`).
  `StoreDesignRepository` + Supabase implementation (registered in InitialBinding).
  `ProductRepository.featuredProducts`. `StorefrontController` loads the design, featured products
  and newsletter sign-ups, with a `previewMode`. The renderer and theme are in
  `lib/modules/storefront/design/`, and `StorefrontView` is now a thin shell around the renderer.
  The builder (`lib/modules/seller/store_builder/`, route `/seller/store/design`) has a side panel
  with drill-down editors, sections reordered by drag, a live preview with a desktop/phone toggle
  (Edit/Preview tabs on narrow screens), tap-to-select in the preview, Save/Publish, problems listed
  before publishing, discard, revert to live, and a leave-without-saving guard. Entry points: Profile
  → Store design and the dashboard checklist.

**Tests:** `flutter analyze`: only the two existing infos. `flutter test`: the one failure is the
known `seller_shell_controller_test` one. New: `store_design_test` (12: starter, round trip, hostile
document, link safety, problems, controller editing/saving/publishing) and
`storefront_renderer_test` (4: every section at phone and desktop widths with no layout errors,
collection tile filtering, preview not signing anyone up). `supabase npm test`: 376 RLS checks (31
new), 357 Deno steps. `flutter build web` compiles. Not run against a real backend or looked at in a
browser: the app needs a Supabase project with the migrations applied.

**Not done:**
- Multiple themes and the five starter themes (TODO §19). `themeId` is in the document, ready for it.
- Product detail, cart and checkout in the store's theme.
- Design history (only draft and live), scheduled publishing, per-section mobile/desktop visibility.
- Newsletter export as a file, double opt-in, and removing a deleted buyer's address (sign-ups
  aren't tied to an account).

---

## 2026-10-03 — TODO §17: billing page

**Status:** done in code and tested. **Not applied or deployed.** The new migration
`20261003000500_billing_page.sql` joins rollout step 1 in TODO.md and has to land before the new
web build: the page reads `seller_billing_profiles` and fails to load without it. No Edge Function
change.

**Why:** user request: "go to the todo and work on phase 17" (TODO.md §17 Billing page, numbered
like §13–16).

**Where it started:** the Subscription screen already had the current plan, a usage line, plan
"Switch"/"Renew" over M-Pesa and a billing history list. Missing from §17: payment method,
invoices, cancel, resume, upgrade vs downgrade, upgrade benefits. Card billing (`payBillingCard`,
`confirmBillingPayment`) existed in the function and `IntasendService` but nothing called it.

**Decisions (made here, reversible):**
- **There is no automatic renewal, so cancel can't stop a charge.** Cancel sets
  `subscriptions.cancel_at_period_end`: the plan runs to its end, the renewal reminder isn't sent,
  and the page says "Ends {date}". Resume clears the flag while the period is running. Paying for
  another period clears it too (`activate_subscription`), so a seller who changes their mind
  after the end just renews. `subscriptions.status` is untouched; `'cancelled'` still means only
  account deletion.
- **"Renewal date" is shown as "Paid through {date}. Renew by then."** That's what actually
  happens.
- **Renewal reminders** are new: `send_renewal_reminders()` runs daily from pg_cron (SQL only, no
  function call) and sends one in-app notification per period when the end is ≤ 3 days away.
  `renewal_reminder_for` records which period end it reminded about, so a renewal re-arms it.
  Added to preflight's `EXPECTED_CRON_JOBS`.
- **Payment method is a saved preference, not a stored instrument.** `seller_billing_profiles`
  (owner-written under RLS) holds M-Pesa or card, the M-Pesa number in 2547… form, and an optional
  billing name and tax ID for invoices. "Card" means IntaSend's hosted page every time. The pay
  sheet prefills from it and offers "Save as my payment method". Account deletion deletes the row
  (`delete_account_data` redefined with that one line).
- **Invoices are paid billing entries.** A before-trigger numbers an entry `INV-YYYY-NNNNNN` from a
  global sequence when it turns paid. The number can't change afterwards, and existing paid entries
  were backfilled in payment order. `activate_subscription` now writes the period each payment bought
  (`period_start`/`period_end`) onto the entry. Older entries other than the latest have no period.
  The PDF comes from the `pdf` + `printing` packages (new dependencies), in Inter from Google Fonts,
  falling back to Helvetica offline. It downloads on web and opens the share sheet on Android.
- **Upgrade vs downgrade is by price per day** (`PlanChange`), so a yearly plan isn't called an
  upgrade just for costing more up front. Each plan card lists what it adds or removes against the
  current plan. The pay sheet warns before a downgrade the server would refuse for listings.
- **The "close to your limit" nudge only counts listings and orders.** Every seller has one store,
  so a one-store plan would always read as full.

**What changed:**
- **Migration.** The columns, sequence and trigger above. `cancel_my_subscription(reason)` and
  `resume_my_subscription()` are security definer, scoped to `auth.uid()`, audited, and refuse a
  period that has already ended. `my_plan_usage()` adds `currentPeriodStart`, `cancelAtPeriodEnd`,
  `cancelledAt`. Also `seller_billing_profiles`, `send_renewal_reminders()` and the cron job.
- **App.** `BillingProfileModel`. The billing entry and usage models read the new fields.
  `SubscriptionRepository` gains cancel/resume/fetch/save billing profile (the test fake too).
  `PlanChange` is in `lib/core/utils/`. The page was rewritten
  (`seller_subscription_view.dart` + `billing_sheets.dart`, `invoice.dart`): status header with
  Renew/Cancel/Resume, payments in progress with "Check payment" (`confirmBillingPayment`), the
  upgrade nudge, usage meters, the payment method card, plan cards and `ManifestStub` history rows
  that open the invoice.

**Tests:** `flutter analyze`: only the two existing infos. `flutter test`: the one failure is the
known `seller_shell_controller_test` one. New: `billing_page_test` (15). `supabase npm test`:
345 RLS checks (35 new: invoice numbering/immutability/period, cancel/resume/audit/refusals,
reminders once per period and not when cancelled, renewal clearing a cancellation, billing profile
RLS and constraints, deletion), 357 Deno steps. `flutter build web` compiles. That needed
`.dart_tool/flutter_build` cleared first: its cached web plugin registrant still imported the
removed Firebase plugins.

**Not done:**
- Automatic renewal. IntaSend's recurring/tokenized card payments aren't verified against an
  account, so nothing is charged without the seller starting it.
- Emailing invoices or reminders (in-app only), and an invoice issuer address or tax registration.
  The PDF says "Sellora, sellora.app". Owner to supply the legal details.
- Proration on a mid-period plan change (owner call, unchanged): a change applies the new plan's
  limits at once, including to the remaining paid time.

---

## 2026-10-03 — TODO §16: subscription plans as admin configuration

**Status:** done in code and tested. **Not applied or deployed.** The new migration
`20261003000400_plan_config.sql` joins rollout step 1 in TODO.md. The function must deploy after it
(`subscribeSeller` reads `subscription_plans.is_active`).

**Why:** user request: "go to the todo and work on phase 16" (TODO.md §16 Subscription system; the
previous commit, "phase 13-15", numbered the TODO's sections the same way).

**Where it started:** the limits were already data-driven and enforced server-side (listing trigger,
`seller_order_gate`, store insert policy). But the table started empty (an owner step), the admin
screen could only edit prices, order/store limits and two flags (under a stale "not yet enforced"
label), the listing limit wasn't editable at all, plan cards showed free-text perks that could
contradict the real limits, and nothing bounded a value.

**Decisions (made here, reversible):**
- Plans are charged in KES. That's what `subscribeSeller` snapshots and both payment routes charge,
  and IntaSend settles nothing else for us. `price_usd` stays as a reference price, so §16's
  "currency" is not a separate column that the charge would ignore.
- Retire, don't delete: `is_active = false` takes a plan off sale (marketing, onboarding, the
  subscription screen) while its current holders keep it and may renew. `subscribeSeller` refuses
  anyone else (409). The admin screen won't retire the last plan on offer.
- Feature flags are a map of booleans. Two are known to the app and described to sellers
  (`customDomain`, `advancedAnalytics`). Since neither exists as a separate feature yet, sellers
  see them marked "coming soon" (`PlanFeature.isBuilt`). Any other key is an internal flag: editable,
  readable through `hasFeature`, never advertised. **Nothing is gated on a flag yet.** Taking
  analytics away from Starter is an owner call.
- Support level (`standard`/`priority`/`dedicated`) is a promise shown on the card, not a switch.
- Order limits keep their existing semantics: snapshotted onto `subscriptions` at payment, so an
  edit reaches existing subscribers at their next payment. Listing and store limits apply at once.
  The admin screen says so.
- One plan holds "most popular" at a time, since onboarding preselects the first one it finds.

**What changed:**
- **Migration.** `support_level`, `is_active`, `sort_order`. Check constraints: slug ids, a 1–40
  character name, prices ≥ 0, a 1–366 day period, limits ≥ -1 with stores -1 or ≥ 1, at most 12
  perks, features an object of booleans. Seeds `starter`/`growth`/`pro` at §16's prices and limits
  (`on conflict do nothing`, so it never overwrites an admin's edits). The USD prices (10/31/80)
  are placeholders.
- **Function.** `retiredPlanRefusal` in `_shared/subscriptions.js`, checked in `createBillingEntry`.
- **App.** `SubscriptionPlanModel` gains the three fields, `PlanSupportLevel`, the `PlanFeature`
  registry, `hasFeature`, `sorted` and `offered`. `fetchPlans` returns display order.
  `SubscriptionRepository.createPlan` inserts, and throws `PlanIdTaken` instead of overwriting.
  `PlanText` (`lib/core/utils/`) builds every plan card's lines from the configured fields, then
  the admin's extra perks; the period label follows `billingPeriodDays`, not a hard-coded "/mo".
  Admin → Plans: summary cards with Edit/Retire, "New plan", and a full editor
  (`plan_editor.dart`) whose validation (`plan_form.dart`) mirrors the constraints, with the KES
  price held to M-Pesa's 10–250,000 range.

**Tests:** `flutter analyze` reports no new issues. `flutter test`: the one failure is the known
`seller_shell_controller_test` one. New: `plan_config_test` (model, text, form validation, admin
controller). `supabase npm test`: 310 RLS checks (15 new: seed, every-field edit, audit, each
constraint), 357 Deno steps (new `retiredPlanRefusal` cases).

**Not done:**
- Gating on feature flags (see above), and a custom domain feature itself (§29).
- §17's billing page (cancel/resume, invoices, payment method); that's the next section.

---

## 2026-10-03 — TODO §13–15: import editor, seller order management, configurable service fee

**Status:** done in code and tested. **Not applied or deployed.** The new migration
`20261003000300_orders_import_fees.sql` joins rollout step 1 in TODO.md. The function must deploy
after it (`createOrder` calls `service_fee_settings()` and writes `service_fee_base`), and the web
build after the function (the seller order read names the new `seller_orders` columns).

**Why:** user request: "go to the todo and work on 13 to 15" (TODO.md §13 Product import workflow,
§14 Orders, §15 Successful order service fee).

**Decisions (made here, reversible):**
- The fee rate is an admin setting, not a constant: the `fees` row of `app_config`
  (`{"serviceFeeRate": 0.07, "chargeOnShipping": false}`), bounded 0–30% by a check constraint and
  audited on every change. Clients read it through `service_fee_settings()`, since the rest of
  `app_config` (pricing margins) stays admin-only. No row means 7% on the goods only.
- `chargeOnShipping` is §15's "unless explicitly configured". When on, the fee is also taken on
  the buyer's shipping charge, out of the seller's share. Each order records which base it used
  (`service_fee_base`) next to the existing `service_fee_rate` snapshot.
- A seller may cancel an order nobody has paid for (`pending`/`failed`), as an admin already
  could. Not one with a payment in flight, and never a paid one: that's a refund, which stays
  admin-only.
- The order timeline is the existing `audit_logs` trail (now also recording `tracking_number`)
  plus a new append-only `order_notes` table. Notes are internal: the seller's and admin's, never
  the buyer's.
- The spec's `platformFee`/`serviceFeeAmount`/`sellerRevenue`/`currency` already existed on
  `orders` (and `ledger_entries` books `PLATFORM_FEE` separately). `paymentFee` is a column but
  stays 0: IntaSend's charge would come from the webhook, whose payload is still unverified.

**What changed:**
- **§15.** `_shared/fees.js` (`getFeeSettings`, 60 s cache, throws rather than guessing).
  `createOrder`, `lineRefusal` and `syncListings` use the live rate; `splitServiceFee` takes
  `{rate, shippingUsd}`. Admin → Plans has a "Service fee on sales" card. The import screen, My
  listings' below-cost warning and the order detail read the live rate (`FeeRepository`).
- **§14.** Orders tab: customer, date, total, payment and fulfilment badges, items, shipping and
  channel; filter chips with counts; search by code/name/email/phone. New order detail
  (`/seller/orders/detail`): customer and address, lines with variants, the payment breakdown
  (products, discount, shipping, refunded, fee at its snapshotted rate and base, earnings), CJ
  fulfilment state and order number, tracking and carrier scans, mark shipped/delivered, cancel
  unpaid, and the timeline with a note box. `seller_orders` gains `service_fee_base`,
  `cj_order_status` and `cj_order_number` (CJ's error text stays server-only).
- **§13.** The import screen is now an editor: title, description (CJ's HTML cleaned to text,
  which is how the storefront renders it), keep/drop images and choose the main one, per-variant
  on/off and SKU, tags, and SEO title/description with a "Suggest" button and a search preview.
  `products` gains `tags` (≤20, 1–40 chars), `seo_title` (≤120) and `seo_description` (≤320),
  appended to `storefront_products`. The price floor counts only the variants left on.

**Tests:** `flutter analyze` reports no new issues. `flutter test`: the one failure is the known
`seller_shell_controller_test` one. New: `listing_text_test`, `seller_orders_test` (filters,
labels, timeline lines, fee settings, order parsing). `supabase npm test`: 295 RLS checks (35 new:
fee settings and audit, fee snapshot, seller cancel, notes, timeline, listing fields), 352 Deno
steps (new `fees.test.js`, configurable-rate cases in `orders.test.js`).

**Not done, needs a decision, an account or a model first:**
- Assign collection (§13): collections don't exist (PHASE 5).
- Partially fulfilled (§14): a CJ order ships as one parcel, so there's nothing partial to show.
- Seller-initiated refunds: refunds stay admin-only; a "request a refund" flow needs a support
  process decision.
- `payment_fee`: needs IntaSend's real webhook payload. Related: `extractAmount` in
  `_shared/intasendApi.js` reads `net_amount` before `value`. If IntaSend deducts its charge from
  `net_amount`, every payment fails amount verification and is held for reconciliation. Check
  this in the sandbox.
- Editing tags/SEO after import (My listings has no editor for them yet), and searching the
  storefront by tag.

---

## 2026-10-03 — PHASES 9–12: platform metrics, store suspension, zone enforcement, error log, l10n, runbook

**Status:** done in code and tested. **Not applied or deployed.** The new migration
`20261003000200_admin_platform.sql` joins rollout step 1 in TODO.md. The function must deploy after it
(`createOrder` reads `stores.is_suspended`).

**Why:** user request: "work on the todo phase 9 to 12, and finish". This pass took every open item in
those phases that didn't need an owner decision, a live provider account or a model that doesn't exist
yet. The rest are listed under "Not done" below.

**What changed:**
- **PHASE 9: dashboard currency bug.** The seller dashboard added up `orders.total` across orders
  priced in different shopper currencies (KES + GBP + EUR as one number). Gross sales, net revenue,
  AOV, the chart, top products and the period delta now convert each order into the store's currency
  first, the way Customers already did. Also new: a **Sales by country** card (`CountrySales` in
  `dashboard_models.dart`, pure and tested).
- **PHASE 10: platform metrics.** The admin Overview had the same mixed-currency sum, and only over
  the 200 newest orders a client can list. `admin_platform_metrics(days)` (admin-only SQL function)
  sums every paid order in KES: `total_kes`, the fee as `service_fee_amount_usd × fx_rate`, and KES
  refunds. It also returns a zero-filled daily series in Africa/Nairobi time and subscription health
  (active, lapsed in 30 days, MRR normalized to 30 days). The Overview shows GMV, fees, MRR, ARR,
  refunds and churn, and degrades to an inline error if the function is missing. The old "total
  platform revenue" card is gone: it added lifetime fees to one month's MRR.
- **PHASE 10: per-store suspension.** `stores.is_suspended`/`suspension_reason`/`suspended_at`, admin-only
  through `stores_guard_update` (plus an insert guard). A suspended store drops out of
  `storefront_products`, `createOrder` refuses it with the same vague 422 as a lapsed seller, the
  storefront says it isn't open, and the seller's dashboard shows a banner with the reason. Admin →
  Stores has Suspend/Lift with a required reason. `SupabaseStoreRepository` never writes these
  fields, so a stale model can't lift a suspension.
- **PHASE 10/12: Activity screen** (`/admin/activity`, from the Overview app bar): the
  `audit_logs` trail, filterable by entity type, and app errors grouped by fingerprint.
- **PHASE 11: server-side zone enforcement.** `storeShipsTo(zones, country)` in `_shared/regions.js`.
  `createOrder` refuses a destination outside the store's `shipping_zones`, and refuses an
  unconfigured country, which `resolveRegion` would silently have priced as US. A store with no
  zones ships everywhere, the same fallback checkout uses.
- **PHASE 11: ARB extraction started.** `l10n.yaml`, `lib/l10n/app_en.arb`, and
  `generate: true` in pubspec. The generated `AppLocalizations` is committed under
  `lib/l10n/generated/` and its delegate is in `AppLocales`. The storefront, cart and buyer-shell
  strings are extracted, since those are what an overseas shopper reads. Still English only.
- **PHASE 12: client error log.** `client_errors` (admin read) is written only through
  `report_client_error`, which caps message, stack and context sizes and rate-limits per user
  (30/h) and for all signed-out visitors together (300/h); over the limit it drops silently.
  `sellora-expire-client-errors` keeps 30 days (added to preflight's `EXPECTED_CRON_JOBS`).
  `ErrorReporter` (`lib/core/monitoring/`) hooks `FlutterError.onError` and
  `PlatformDispatcher.onError` in release builds, sends each distinct message at most once per 5 minutes
  and 20 per session, and never throws. `SELLORA_RELEASE` (dart-define) tags the build.
- **PHASE 12: `docs/RUNBOOK.md`.** Release order (migrations → function → web) and why, rollback per
  piece, secret rotation (including the Vault copy of `CRON_SECRET`), backups/staging, and a
  symptom → where to look table.

**Tests:** `flutter analyze` reports no new issues. `flutter test`: the one failure is the known
`seller_shell_controller_test` one. New tests: `country_sales_test`, `error_reporter_test`,
`activity_models_test` and `admin_stores_controller_test`; `admin_dashboard_controller_test` was
rewritten for server metrics; the row-mapping test covers suspension fields. `supabase npm test`:
260 RLS checks (27 new: suspension, metrics, client errors) and 343 Deno steps (new
`storeShipsTo` cases).

**Not done, needs a decision, an account or a model first:**
- Role as a JWT claim (custom access token hook). It means rewriting every RLS policy that reads
  `profiles.role`. That's its own migration and audit, not a side task.
- A third-party crash/uptime service, PITR, a staging project: owner choices and dashboard steps
  (the runbook says how).
- Admin coupons/categories/themes/feature flags/platform settings: nothing in the app reads them
  yet. Each needs a product decision on what it controls.
- Device/conversion analytics (no session tracking), non-KES settlement, minor-unit persisted
  amounts, the remaining ARB extraction and a second language.

---

## 2026-10-03 — PHASE 9: discount codes, customer analytics, store sharing

**Status:** done in code and tested. **Not applied or deployed.** The new migration joins the
rollout's step 1 in TODO.md.

**Why:** user request: "work on todo phase 9". PHASE 9's dashboard slice shipped 2026-09-21; its
open items were discount codes, customer analytics and marketing.

**Decisions (made here, reversible):**
- The seller funds a discount from their own margin. The 7% service fee is taken on what the buyer
  actually pays for the goods (`splitServiceFee(chargedSubtotal, ...)`), the way Shopify charges
  on the discounted price.
- A code that would push seller revenue below zero is refused (422), so Sellora never pays CJ more
  than the buyer paid. Every line already clears that floor at full price (`lineRefusal`).
- A use counts until its order is cancelled, so an unpaid order that expires gives the use back.
- Amounts (fixed discount, minimum order) are in the listings' currency, USD today, like
  `sell_price`.

**What changed:**
- **Migration `20261003000100_discounts.sql`.** A `discounts` table (percentage or fixed amount,
  minimum order, specific products, start/end, total usage limit, once per customer, on/off).
  Owner/admin-only RLS. A guard keeps the id and store fixed. A used code can't be deleted (the
  `orders.discount_id` FK), so sellers turn it off instead. `orders` gains
  `discount_id`/`discount_code`/`discount_amount` (client-readable, appended to `seller_orders`)
  and server-only `discount_amount_usd`. The `orders_enforce_discount` trigger locks the code's
  row on insert and enforces its limits, so two checkouts can't both take the last use.
  `storefront_discount(store, code)` lets anyone who knows a code read its terms for the checkout
  preview, without usage figures. `store_discount_usage(store)` is owner-only. 36 new RLS checks.
- **Server.** `_shared/discounts.js` (pure: normalize, liveness, `priceDiscount`, trigger-error
  mapping) and `createOrder` takes `discountCode`. The code is checked before the CJ calls, priced
  on the eligible lines, and the trigger's refusal comes back as a 422 the buyer reads.
  `createOrder` was already rate-limited per user, which also limits code guessing through it.
- **Checkout.** Discount-code field with apply/remove, a discount line in the summary, and the
  total includes it. The preview mirrors the server's rules (`DiscountModel.quote`). The order
  carries what the server actually priced.
- **Seller: Marketing** (`/seller/marketing`). Discount list with status (active/scheduled/
  ended/used up/off), uses, an on/off switch, and a create/edit sheet. Also the storefront link
  with copy and WhatsApp/Facebook/X share links (`core/utils/store_link.dart`; non-web builds use
  `AppConstants.webAppUrl`, `--dart-define=SELLORA_WEB_URL`).
- **Seller: Customers** (`/seller/customers`). Registered customers (`store_customers`) joined
  with the store's orders: customers, returning customers and repeat rate, new in 30 days, average
  spend, then a searchable/sortable list and a profile sheet with order history. Totals are
  converted into the store's currency per order (the dashboard still sums raw `total`s).
  `CustomerAnalytics` is pure and tested.
- Both are linked from the Dashboard and Store profile, not new shell tabs: an 8-item bottom bar
  doesn't work on mobile (TODO.md §8). New `DiscountRepository`/`CustomerRepository` with
  `Supabase*` implementations in `InitialBinding`, plus `test/fakes/mock_discount_repository.dart`.
- **Bug fixed on the way:** `SupabaseOrderRepository.columns` (the buyer's read of `orders`)
  named `seller_revenue`, which the 2026-09-28 hardening revoked from clients. Every buyer
  order-history read would have been refused. It's now only in `sellerColumns`.

**Tests:** `flutter analyze` reports no new issues. `flutter test` 89 pass; the one failure is the known
`seller_shell_controller_test` one. New: `discount_model_test`, `customer_analytics_test`,
`store_link_test`, `seller_marketing_controller_test`. `supabase npm test`: 233 RLS checks,
338 Deno steps (new `discounts.test.js`).

**Not done, needs a decision or a model first:**
- Free-shipping codes: CJ freight still has to be paid. Who pays it (seller or Sellora's freight
  margin) is an owner call.
- Collection- and customer-group-scoped codes: neither collections (PHASE 5) nor customer groups
  exist.
- Automatic discounts, abandoned cart (the cart is in-memory by design), email campaigns, customer
  tags/notes/marketing consent (needs a writable customer record, open decision #1).
- Analytics by country/device and conversion rate: nothing records sessions or devices.

---

## 2026-10-03 — PHASE 8: admin refunds, structured shipping address, payment-provider interface

**Status:** done in code and tested. **Not applied or deployed.** The new migration joins the
rollout's step 1 in TODO.md.

**Why:** user request: "go to the todo and work on phase 8". Of PHASE 8's five open items, three are
code: refunds UI, the CJ address shape, and a provider abstraction. The other two weren't started.
Splitting mixed-seller carts is an owner decision, and real split payouts need a live IntaSend
account.

**What changed:**
- **Refunds.** `/refundOrder` already existed, but the amounts an admin needs (`total_kes`, refund
  state and history) are server-only `orders` columns. Migration
  `20261003000000_admin_order_refunds.sql` adds an admin-only, read-only `admin_order_refunds` view
  instead of widening the shared column grant (6 new RLS checks). Admin → Orders: tapping an order
  opens a sheet with the payment and refund state and a refund form: amount (empty means the
  rest), IntaSend reason, note, and a confirm step that says whether the order will be cancelled.
  New: `OrderRefundInfo` (mirrors `decideRefund`'s refusals), `OrderRepository.refundInfo`/
  `refundOrder` (fake updated), `ApiEndpoints.refundOrder`.
- **Shipping address (a real bug).** `createOrder` accepted `{countryCode, line}` while
  `cjApi.createDropshipOrder` reads `fullName`/`phone`/`line1`/`city`/..., so every paid order would
  have reached CJ with those fields blank. `normalizeShippingAddress` in `_shared/orders.js` now
  keeps only the known fields, trims them, and refuses a missing name/phone/street/city or a bad
  phone/email with a 400 that names the field. `fulfillOrder` re-checks it before the push.
  `shippingCountry` falls back to the ISO code. Checkout has proper fields, prefilled from the
  buyer's profile. The email is the account's. A 4xx from `createOrder` now shows the server's
  message instead of "payment didn't go through". `ShippingAddress.fromMap` still reads the old
  shape.
- **Payment provider.** `OrderPaymentProvider` (`startOrderPayment` → `PaymentPromptSent` |
  `PaymentRedirect`, `confirmOrderPayment`, `supports`) is bound in `InitialBinding` to the
  `IntasendService` instance. Checkout no longer names IntaSend. Billing still calls
  `IntasendService` directly.

**Tests:** `flutter analyze` reports no new issues. `flutter test` 65 pass; the one failure is the known
`seller_shell_controller_test` one. New `order_refund_model_test.dart` and `shipping_address_test.dart`.
`supabase npm test`: 197 RLS checks; 320 Deno steps, which include the new `normalizeShippingAddress`
cases.

**Deploy note:** the new function refuses the old app build's `{countryCode, line}` address, so the
function and the web build must ship together (TODO.md rollout steps 2-3).

**Still blocked:** splitting mixed-seller carts (owner decision), split payouts and confirming
IntaSend's refund payload (live account), and server-side provider dispatch for collection.

---

## 2026-09-26 — Audit follow-up: Batch C re-verified, billing (PHASE 3), listing sync (PHASE 4), rollout preflight

**Status:** done in code and tested. **Not applied or deployed**, like the entry below. The rollout
order in TODO.md now covers both entries and ends with `scripts/preflight.js`.

**Why:** user request: "go to the sellora security audit and work on phase 3 and 4". The audit has
no phases as such. Asked; the user chose all four readings: re-verify Batch C (§4 item 3), close its
leftovers, prepare the owner steps (§4 item 4), and do PHASE 3/4 of SELLORA_IMPLEMENTATION_PLAN.md.

**What changed:** `SELLORA_SECURITY_AUDIT.md` §7 has the detail. In short:
- **N1 (Medium):** the public CJ routes' per-IP key was the first `x-forwarded-for` hop, which a caller
  may control. `searchProducts`/`getProductDetail`/`getCategories` are now signed-in seller or admin
  only, limited per account (`sellerCatalog`). The app needed no change, since only seller screens
  call them. `INTASEND_WEBHOOK_CHALLENGE` moved from optional to required in TODO.md.
- **N2 (Medium):** a downgrade kept every listing. Now `subscribeSeller` refuses it (409, with how many
  to unlist), and the `subscriptions_enforce_listing_cap` trigger unlists the newest excess on a race.
- **Billing:** `my_plan_usage()` (new migration `20260929000000_billing_usage.sql`) counts usage the
  way enforcement does. The dashboard's own order count was wrong (N3). The subscription screen has
  Renew, billing history, plan limits, "Paid through"/"Ended" instead of "Renews", and the server's
  refusal reason. New `SubscriptionRepository.billingHistory` (fakes updated).
- **Listing sync:** migration `20260930000000_listing_sync.sql` adds server-owned
  `products.supplier_alert`/`supplier_checked_at` (the guard keeps them from clients) and schedules
  `syncListings` hourly. `_shared/listingSync.js` plus `cjApi.getVariantPrices`. It is advisory only
  and never unlists. My Listings shows the alert.
- **Import pricing (N4):** earnings = price × 0.93 − CJ cost. Shipping was wrongly subtracted
  (the buyer pays it) and the fee was ignored.
- **Account deletion web link:** `/#/delete-account` (`DeleteAccountView`/`DeleteAccountController`),
  email + password, then the same `POST /deleteAccount`. `AuthController.friendlyError` is now
  static and shared.
- **Owner tooling:** `deployment_report()` (migration `20260930000100_deployment_report.sql`,
  service role only) and `supabase/scripts/preflight.js` (+ test, which also pins the cron job list
  to the migrations).

**Tests:** 191 PGlite checks, 74 Deno tests / 305 steps, 12 script tests. `flutter analyze`: no new
issues (the 2 pre-existing `curly_braces` infos remain). `flutter test`: 56 pass plus the known
`seller_shell_controller_test` failure.

**Decisions left to the owner:** proration on a mid-period upgrade (today an upgrade takes effect at
once and the new period is added after the remaining days). Whether browse should move to
`catalog_products`. Whether a server-side `marginPricingService` quote is wanted.

**Not done:** cancel/resume (there's no auto-renewal to cancel). No controller test for the import
screen's new pricing (it needs a `StoreScope` fake); the formula is documented where it lives.

---

## 2026-09-26 — Security audit remediation: every finding closed in code

**Status:** done in code and tested. **Not applied or deployed.** The remote project is still on
the four earlier migrations and `api` v4. The rollout order is in TODO.md: `db push`, then
`npm run deploy`, then a web build.

**Why:** user request: "finish up with the phase 2 of the security audit, finish all". That means
every finding in `SELLORA_SECURITY_AUDIT.md` §2 (H1–H7, M1–M9, L1–L7).

**Decisions (owner, this session):** the freight margin (buyer's shipping charge minus CJ freight)
is Sellora's, so seller revenue = retail − CJ goods cost − 7% fee. `commission_percent` is dropped,
leaving the flat 7% as the only fee.

**What changed:** the audit's new §6 has a row per finding. In short:
- New migration `20260928000000_security_hardening.sql`: seller standing (`seller_can_sell`,
  `seller_order_gate`), plan limits (listing trigger, store policy, order gate), a guarded
  `activate_subscription`, an order-status transition trigger, `expires_at` plus a pg_cron sweep, and
  the `storefront_products`/`seller_orders` views. It also adds `audit_logs`, `ledger_entries`,
  `webhook_events` (append-only where it matters), `delete_account_data`, email sync, length caps and
  grant revokes.
- `api` function: H1 fee split, price floor, stock check, seller gate, order expiry, fail-closed
  amount check with a `payment_amount_unverified` alert, per-IP limits on public routes and the
  webhook, stored webhook events, refund audit rows, and `POST /deleteAccount`.
- App: buyer reads go to `storefront_products` (paged, with "Load more"). Seller and admin order
  reads go to `seller_orders`. `productDetail` reads CJ directly. The import screen enforces the
  price floor and handles publish refusals (`ListingRejected`). Sellers can only advance paid orders.
  Both profiles have "Delete account". `commissionPercent` is gone.

**Behaviour changes to know about:**
- A seller without an active subscription has an empty storefront and can't be checked out. That
  includes any real sellers who never paid.
- `products` is no longer publicly readable. Anything buyer-facing must use `storefront_products`.
- An unreadable IntaSend amount now holds the payment (alert) instead of fulfilling it.
  Confirm the response shape in the sandbox before live traffic.
- The ledger books refunds but doesn't reverse `SELLER_EARNING`; a payout job must net them.

**Tests:** 170 PGlite checks (the hardening section is new), 70 Deno tests / 285 steps. `flutter
analyze` shows no new issues. `flutter test`: 51 pass plus the known `NotificationCenter` failure.

**Not done:** a web page for account deletion (Google Play asks for one alongside the in-app flow).
Browsing still calls CJ live (M2's optional "serve from `catalog_products`"). The import screen's
profit readout still ignores the 7% fee.

---

## 2026-09-26 — Post-migration security & architecture audit

**Status:** audit only. No code, schema or config changed. The baseline `cd supabase && npm test`
passes.

**Why:** user request: a principal-level production upgrade of the Supabase-migrated app, audit
first ("produce an architecture report before implementing major changes").

**Outcome:** `SELLORA_SECURITY_AUDIT.md` supersedes `SELLORA_ARCHITECTURE.md`. The target
architecture is already in place: server-side pricing, re-verified payments, CAS idempotency,
app_metadata admin, and no client secrets. No restructure is recommended. It found 7 high issues,
including seller revenue that ignores CJ cost, no sell-price floor, a suspended seller who can
reactivate by paying, buyers who can buy subscriptions, suspended/lapsed sellers who can still sell,
unenforced plan limits, and unconstrained seller order-status changes. It also found 9 medium issues:
a fail-open amount check, un-rate-limited public CJ routes, no audit log, ledger or webhook store,
three conflicting fee rates, no order expiry, a public cost_price, and no CJ stock check.

**Blocked on (product decisions):** the seller-revenue formula and who keeps the freight markup (H1).

**Follow-up, same day: service fee 2% → 7%.** User decision: "I want to change the fee to 7%". It is
a flat rate on the product subtotal only, as before. `SERVICE_FEE_RATE` (`orders.js`, the rate
actually charged and snapshotted per order) and `AppConstants.platformServiceFeeRate` (display only,
used by the marketing page) are now 0.07. The `splitServiceFee` test, comments, TODO.md (its
self-contradictory §15 and the revenue example) and SELLORA_IMPLEMENTATION_PLAN.md were updated to
match. Existing orders keep their snapshotted rate. Still open: plans' `commission_percent` is
displayed but not charged (audit M6).

**Deployed, same day:** `api` v4 is on project `ktpxbrtjmqdsnlmfslbq` (`verify_jwt=false`, as
configured). `/health` returns 200, and an unauthenticated `createOrder` returns 401. All four
migrations were already applied remotely. Later that day the `CRON_SECRET` function secret and the
Vault secrets `sellora_cron_secret`/`sellora_api_url` were set, and all five pg_cron jobs are
active. A manual `invoke_scheduled_job('refreshFxRate')` got a 202 from the function. The project also had an unrelated `websocket-server` function (Supabase's stock echo
template) that nothing in this repo referenced; it was deleted on 2026-09-27, when `api` was also
redeployed with per-item diagnostics behind the `SELLORA_DEBUG_LOGS` secret (off by default).

---

## 2026-09-27 — Firebase → Supabase, phase 2: backend on Edge Functions; auth links; Storage

**Status:** done in code. **Nothing is applied to or deployed on the real Supabase project yet** —
TODO.md's owner checklist has the steps. `cd supabase && npm test`: 89/89 SQL/RLS checks in PGlite,
7/7 grant-admin tests, and 63 Deno tests (261 steps). `deno check` and `deno lint` are clean.
`flutter analyze`: 0 errors/warnings (the same 2 pre-existing infos). `flutter test`: 51/52, and
the one failure is the same pre-existing `seller_shell_controller_test.dart` `NotificationCenter`
failure. The backend has never talked to a live CJ or IntaSend account, same as the Firebase version.

**Why:** user request: "finish up with the supabase migration in the todo.md". That covers every
open code item in the checklist: phase 2, the Android deep link, the expired-link landing, and
Storage uploads. Hosting is still the owner's decision.

**Decisions:**
- **One Edge Function, `api`, routed by path** (`/functions/v1/api/<endpoint>`). It keeps the
  Cloud Functions' endpoint names, request bodies and `{success, data}` envelope, so the app changed
  only `ApiEndpoints.baseFunctionsUrl`. Gateway JWT verification is off (`supabase/config.toml`),
  because catalog browsing and the IntaSend webhook are public. Each signed-in route checks the token
  with Supabase Auth itself (`verifyAuth`: refuses deleted and banned users). Admin comes from
  `app_metadata.role`.
- **Logic ported as plain-JS ES modules** in `supabase/functions/_shared/`, close to verbatim from
  `functions/lib`. That keeps the review diff small and the 250 existing tests reusable: they
  run under Deno's `node:test`, and only 5 needed changes for intended behaviour differences. axios
  became a small `fetch` helper (`http.js`). The Firebase logger became JSON lines on stdout, and
  the `event`/`alert` fields are unchanged.
- **Server-only order data stays on `orders`, hidden by a column-level grant.** Supplier cost,
  provider refs, and the CJ push/refund state machines are server-only columns. A client `select *`
  is refused outright, so `SupabaseOrderRepository.columns` names the readable ones. That also means
  a future server column can't leak by default. The old orders/{id}/items subcollection is the
  `lines` jsonb column. The client-visible fee columns are now in the order's own currency (the
  Firestore version wrote USD figures next to a KES/GBP/EUR total), and the USD originals are kept
  server-side.
- **Firestore transactions → compare-and-set or SQL functions.** Fulfilment's claim is
  `UPDATE ... WHERE cj_order_status = <seen> AND cj_push_attempts = <seen>`. Every claim bumps the
  attempt count, so only one of two racers can match. Refunds claim the same way on
  `(refund_status, refunded_amount)`. Multi-row writes are SQL functions callable only by the service
  role: `activate_subscription` (billing entry + subscription + profile mirror, idempotent on
  `status = 'pending'`), `attach_order_payment_attempt` (appends to the history in one statement,
  and won't reopen a paid order), and `consume_rate_limit` (row-locked fixed window, which replaces
  the Firestore counters and their TTL).
- **Payment states:** `payment_status` now allows `awaiting_confirmation`, `partially_refunded`
  and `refunded`. The Firestore version wrote `AWAITING_CONFIRMATION`, and the phase 1 check
  constraint would have rejected it. Dart's `OrderPaymentStatus` gained `partiallyRefunded` and
  `refunded`, and `awaiting_confirmation` reads as `pending`. Order `status` now goes
  `pending` → `processing` on payment (it used to be `pendingPayment`/`paid`, which the app's
  enum couldn't read).
- **Scheduled jobs:** pg_cron + pg_net POST to `/cron/<job>` with an `x-cron-secret` header read
  from Vault. The function answers 202 and finishes the job in `EdgeRuntime.waitUntil`. Jobs: FX
  daily, catalog sync daily, fulfilment retry every 30 min, tracking hourly, and rate-limit cleanup
  hourly (plain SQL). `maxDetailCallsPerRun` dropped from 60 to 20 to stay inside an Edge Function's
  wall-clock limit.
- **Not ported:** PayPal (the app never called it), product reviews (nothing reads them), and App
  Check (Firebase-only, and it was report-only). `refunds.chargedAmount` now returns null for a
  PayPal order.
- **Fixed on the way:** `placeOrder` read `res['id']` from the `{success, data}` envelope, so it
  would have thrown on the first real order. It now unwraps `data` and uses the server's short
  `code` (`SLR-XXXXXXXX`). `fulfillOrder` now refuses to re-mark a refunded order paid (a late
  webhook retry), and it no longer walks a seller-advanced status back to processing.
- **Auth links:** `AuthService.authRedirectUrl` is the current page on web and
  `sellora://auth-callback` on Android. The intent filter is in AndroidManifest.xml, and
  `flutter_deeplinking_enabled` is off so Flutter doesn't also push the URL as a route. Reset,
  sign-up and resend all pass it. A bad link (`#error=...&error_code=otp_expired`, or a PKCE link
  opened on another device) lands on `/auth-link-error`. On web, `main()` reads it from the launch
  URL and replaces the URL before the router starts, since supabase_flutter only cleans the URL on
  success. Elsewhere, `AuthService.linkErrors` carries it, including one that arrived before
  `onReady` subscribed.
- **Storage:** a public `store-media` bucket (2MB, images only). Owners write under `{store_id}/`,
  and `owns_store()` checks the first path segment. Customize store uploads the photo and saves its
  public URL. Existing `data:` logos still render.

**Changed:**
- New: `supabase/functions/` (`api/index.ts`, `_shared/*.js`, `tests/`, `deno.json`),
  `supabase/config.toml`, and migrations `20260927000000_backend.sql`,
  `20260927000100_scheduled_jobs.sql` and `20260927000200_storage.sql`. `supabase/package.json` now
  has Deno as a devDependency and test/check/serve/deploy scripts. `rls.test.mjs` has stubs for the
  storage schema and 38 new checks.
- `ApiEndpoints`, `SupabaseOrderRepository` (columns + envelope), `OrderModel`,
  `StoreRepository.uploadStoreImage` (plus the three fakes), `StoreCustomizeController`,
  `AuthService`, `main.dart`, routes, the new `AuthLinkError`/`AuthLinkErrorView` with 7 tests,
  AndroidManifest.xml, and comments across `lib/` that pointed at `functions/lib`.
- `test/countries_test.dart` now syncs against `supabase/functions/_shared/regions.js`.
- `functions/` is **left in place**, retired. It holds an untracked `functions/.env` with live keys,
  which can't be recovered once deleted, so deleting it is an owner step (TODO.md).

**Still open:**
1. Everything in TODO.md's owner list: `db push`, function secrets + deploy, Vault secrets for cron,
   the IntaSend webhook URL, redirect URLs, admin, plan seed, catalog sources, and a smoke test.
2. Unverified against real accounts (unchanged from Firebase): CJ auth/response shapes, IntaSend
   status/refund shapes, and the webhook payload. `shippingAddress` is still `{countryCode, line}`,
   not the full address CJ needs to fulfil.
3. The web link-error path relies on `SystemNavigator.routeInformationUpdated` replacing the URL before
   the router reads its initial route. That's reasoned from the engine source, not run in a browser.
4. Hosting decision (Supabase has none).

---

## 2026-09-26 — Mock data removed from the app

**Status:** done. `flutter analyze`: 0 errors/warnings (the same 2 infos, one of which now sits in
`test/fakes/mock_admin_repository.dart`). `flutter test`: 44/45. The one failure is the same
pre-existing `seller_shell_controller_test.dart` `NotificationCenter` failure.

**Why:** user request: "remove all the mockdata in the app". This came right after confirming that the
app fetches nothing real from CJ. The user was told that the real backend path doesn't work until
phase 2.

**Changed:**
- Removed `AppConstants.useMockData`. `InitialBinding` now always binds the `Supabase*` repositories
  and always registers `CjDropshippingService`/`IntasendService`.
- Removed the demo branches in `CheckoutController` (an instant fake "paid" order),
  `SellerOnboardingController.payWithMpesa`, and `SellerSubscriptionController.switchPlan` (both
  relied on the mock activating the subscription synchronously).
- Deleted `mock_product_repository.dart`, `mock_notification_repository.dart`, and
  `mock_fx_rate_repository.dart`. Moved `mock_{auth,store,order,subscription,admin}_repository.dart`
  and `mock_seed_data.dart` to `test/fakes/`, because the admin dashboard and onboarding controller
  tests use them as in-memory doubles. `lib/data/mock/` and `lib/data/repositories/mock/` no longer
  exist.
- Deleted `test/auth_repository_test.dart` and `test/mock_subscription_repository_test.dart`. They
  only tested the mocks' own behaviour. The real sign-up/store creation is covered by
  `supabase/tests/rls.test.mjs`.
- Updated comments, `CLAUDE.md`, `README.md`, and `TODO.md`. `SELLORA_IMPLEMENTATION_PLAN.md` still
  describes "mock + Firebase" implementations as history and was left alone.

**Consequence:** with the mocks gone, the running app has no fallback. Sign-in/sign-up and store
lookup work against Supabase once the migration is applied. The CJ catalog/import, checkout, and
subscription payments go through `ApiEndpoints` and fail until phase 2 ports `functions/` to Edge
Functions with real CJ/IntaSend credentials. Plans come from the `subscription_plans` table, which
is empty until seeded.

---

## 2026-09-26 — Supabase: password-reset landing screen

**Status:** implemented, not yet exercised against the real project (the migration isn't applied
there yet). `flutter analyze`: 0 errors/warnings (the same 2 pre-existing infos). `flutter test`:
50/51, and the one failure is the same pre-existing `seller_shell_controller_test.dart`
`NotificationCenter` failure. Nothing new is covered by tests, because the flow depends on
`Supabase.instance`.

**Why:** item 2 of phase 1's "Still open" list, and the first code item in TODO.md's Supabase
checklist. Without it, reset emails and `grant-admin.js`'s first-login link led nowhere.

**Findings from the gotrue 2.25 / supabase_flutter 2.15 source:**
- A recovery link emits **only** `passwordRecovery`, never `signedIn`. That holds for both the PKCE
  `?code=` link from `resetPasswordForEmail` and the implicit `#access_token=…&type=recovery` link
  that `admin/generate_link` produces. `SupabaseAuthRepository.userChanges` skips that event.
  Before this change, a recovery link left the app signed in, with no screen and no cached profile.
- `Supabase.initialize()` consumes the launch URL before `runApp`, so the event fires before any
  widget exists. `onAuthStateChange` is a BehaviorSubject, though, so a late listener still receives
  it as the latest event.

**Changed:**
- `AuthService`: tracks `isRecoveringPassword`. It is set by `passwordRecovery` and cleared by
  `signedIn`/`signedOut`/`userUpdated`. It also exposes `passwordRecoveries` and
  `updatePassword()`. `sendPasswordReset` passes `redirectTo` on web, which is the current
  origin + path, so a dev server gets the link back. That URL must be in the redirect allow-list.
- `AuthRepository`: adds `passwordRecoveries`, `isRecoveringPassword`, and `updatePassword()`,
  which returns the profile loaded with a token refresh and caches it. There are implementations in
  the Supabase repo, the mock, and both test fakes. `same_password` maps to `same-password`.
- `SelloraApp.onReady` (in `main.dart`) listens for `passwordRecoveries` and routes to the new
  `/reset-password` route (`ResetPasswordView`: new password + confirm, using
  `Validators.newPassword`). On success, `AuthController.completePasswordReset` routes the user
  home the way sign-in does, and the suspended-seller check applies there too. If the screen is
  opened without a recovery session, it shows "This link has expired" instead.
- `AuthController.checkSession` returns early during recovery. Otherwise the mobile splash's 3-second
  fallback would call `offAllNamed(roleSelect)` over the reset screen.

**Still open:**
- **Android has no deep-link intent filter**, so a reset requested on the app goes to the web Site
  URL. The PKCE code verifier lives on the device that asked for the reset, so the code exchange
  there will fail. Either add an app link (and pass it as `redirectTo` off-web) or set
  `flowType: AuthFlowType.implicit`. Web-to-web works.
- An expired or used link arrives as a stream error (`#error=access_denied&error_code=otp_expired`).
  Nothing routes on it, and with hash routing GetX reads that fragment as a route.

---

## 2026-09-26 — Firebase → Supabase, phase 1: Auth + database

**Status:** implemented this session, **not yet applied to the Supabase project**. `flutter analyze`:
0 errors/warnings (the 2 pre-existing infos). `flutter test`: 50/51. The one failure is the same
pre-existing `seller_shell_controller_test.dart` `NotificationCenter` failure. There are 5 new
row-mapping tests. `cd supabase && npm test`: 51/51 schema/RLS checks plus 7/7 grant-admin tests.
`functions/` `npm test`: 250/250.

**Why:** user request: "switch firebase to supabase". Agreed scope: phase 1 is Auth + database. Phase
2 ports `functions/` to Supabase Edge Functions (Deno), with `pg_cron` replacing the four scheduled
functions. Hosting stays undecided. Supabase has no static hosting, so `firebase.json` keeps its
`hosting` block until then.

**Decisions:**
- **Models are untouched.** Columns are snake_case. `toRow`/`fromRow` in
  `lib/data/services/supabase_service.dart` translate top-level keys, and jsonb columns keep
  camelCase inside. They also translate timestamps. `DateTime.toIso8601String()` on a local
  DateTime has no offset, so Postgres would read it as UTC and shift it by the device's offset (3h
  in Kenya). Offset-less strings are sent as UTC, and `+00:00` values come back as local ISO strings.
- **The profile is created by a trigger, not the client.** `signUp()` passes the profile fields as
  user metadata. `handle_new_user()` then creates the profile, plus a seller's store (same slugify
  and `-N` rule as Dart) or a buyer's `store_customers` row, in the same transaction as
  `auth.users`. It accepts only what a buyer or seller sign-up can legitimately produce. This
  retires the old create-rule field policing and `_deleteAuthUserOnFailure`, and it works whether
  or not "Confirm email" is on.
- **Admin:** `app_metadata.role = 'admin'` replaces the `admin` custom claim. Only the service role
  can set it. `is_admin()` checks it, and the `profiles.role` column stays routing-only. The
  `grant-admin.js` port lives in `supabase/scripts/`. It has no npm dependencies (it calls the REST
  APIs with fetch) and needs `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`.
- **One `orders` table** replaces the flat `orders` collection plus `stores/*/orders`. RLS gives
  the cross-tenant guarantee the subcollections were for. `store_slugs` became a unique constraint.
- **Clients may write only a few order/notification columns.** A column-level `grant update` allows
  `orders(status, updated_at)` and `notifications(read_at)` only. Guard triggers make profile
  role/subscription/approval/terms/store and store id/slug/owner immutable to clients.
  `profiles_guard_update`/`stores_guard_update` replace `touchesAny()`.

**Changed:**
- `pubspec.yaml`: `firebase_core`/`firebase_auth`/`cloud_firestore` → `supabase_flutter`.
  `lib/firebase_options.dart`, `android/app/google-services.json`, and the Android
  `com.google.gms.google-services` plugin are gone.
- New: `supabase/migrations/20260926000000_initial_schema.sql`, `lib/core/config/supabase_config.dart`
  (URL and publishable key; `--dart-define` overrides), and `SupabaseService`, which replaces
  `FirestoreService`. `AuthService` now wraps Supabase Auth.
- `Firebase*Repository` → `Supabase*Repository` (all seven). `SupabaseAuthRepository` maps Supabase
  error codes onto the existing `AuthFailure` codes, so `AuthController` only gained
  `email-not-confirmed`. `userChanges` ignores token-refresh/user-updated events. `updateUser` sends
  only self-editable columns. Before, `UserModel.copyWith` dropped `storeId`, so it would have
  nulled a buyer's store.
- `DioClient` sends the Supabase access token.
- Removed `firestore.rules`, `firestore.indexes.json`, and the `firestore`/`flutter` blocks in
  `firebase.json`. Their rules are carried over in the migration, and each policy's comment names
  the rule it replaces.
- New `supabase/tests/rls.test.mjs` runs the migration in PGlite (Postgres in WASM) and checks the
  trigger and every policy as anon/buyer/seller/admin. It found one real constraint: a notification
  insert must not `.select()` the new rows. The sender can't read the counterparty's alert, so
  RETURNING fails RLS. The repository has a comment on this.

**Still open / blocked:**
1. **Apply the migration** to the Supabase project (SQL editor, or `npx supabase link` + `db push`).
   Fill in `SupabaseConfig`, then re-run `grant-admin.js` for the admin. The Firebase `sellora-20`
   accounts are not migrated. Everything was pre-launch, so this assumes no real users exist.
2. **Password reset has no landing screen.** Firebase served its own reset page. Supabase redirects
   back to the app's Site URL with a recovery session, and the app has to show a set-new-password
   form (on `AuthChangeEvent.passwordRecovery`) and call `updateUser(password:)`. Until that's built,
   reset emails, and the admin's first-login link, lead nowhere useful. Set Site URL/redirect URLs in
   the Supabase dashboard at the same time.
3. **"Confirm email":** Firebase allowed immediate sign-in, and that matches Supabase with
   confirmation **off**. If it's on, sign-up shows "check your inbox" instead of entering
   onboarding. That works, but it's a UX change.
4. **Phase 2:** the deployed Cloud Functions still verify Firebase ID tokens and read/write
   Firestore. They reject Supabase tokens, which is harmless only while `useMockData` is true. The
   server-only tables (CJ catalog → `catalog_products`, `rate_limits`, refund/fulfilment columns on
   `orders`) arrive with that port.

---

## 2026-09-25 — PHASE 2: onboarding store-setup step, no-store recovery, email verification

**Status:** implemented this session. `flutter analyze`: 0 errors/warnings (3 pre-existing
`curly_braces` infos in untouched files). `flutter test`: 45/46, with the same pre-existing
`seller_shell_controller_test.dart` `NotificationCenter` failure. 8 new tests in
`test/seller_onboarding_controller_test.dart`. Not run against the live `sellora-20` project.

**Why:** user request: "work on phase 2". The only item the STATUS row listed (the multi-store
switcher) is still blocked on decision #4. This session did the unblocked Phase 2 work from TODO.md
§32–33 instead.

**Changed:**
- `StoreModel` gained `category` (a `StoreCategories.all` key) and `countryCode` (ISO alpha-2, where
  the business is based, not where it ships), plus `isSetUp` (both are set). Old store docs read
  them as null. No rules change was needed: the `stores` update rule already allows any field except
  `id`/`slug`/`sellerId`/`createdAt`.
- `createStoreForSeller()` in `store_repository.dart` is now the one place that creates a store
  (first free slug, id `store-{sellerId}`). Both auth repositories' sign-up and onboarding call it,
  which removes the copy that was duplicated in the Firebase and mock repositories.
- Seller onboarding is now 3 steps: **store setup** (name, category, country, currency; the
  currency defaults from the country) → plan → pay. A seller whose store is already set up skips to
  plan selection. Saving updates the store and mirrors `storeName`/`currencyCode` onto the user doc.
  The slug never changes. If the seller has no store, saving creates one. The screen has a back
  button between steps and an error state if plans fail to load.
- Seller shell: `StoreScope.isMissing` separates "found no store" from "the lookup failed". The
  no-store case now offers "Create my store", which opens onboarding's setup step, instead of a
  retry that could never succeed.
- `AuthRepository.checkEmailVerified()` / `resendVerificationEmail()` (the mock always reports
  verified). The store-setup step shows a verify-your-email banner with Resend and "I've verified".
  Verification is still **not required** to continue.

**Still open (Phase 2):** multi-store switcher and store-limit enforcement (decision #4); required
email verification; Google sign-in (TODO §32, "where configured"); onboarding steps 8–11 (first
import, payment, shipping, publish) are covered by the dashboard's setup checklist, not by this flow.
Existing stores created before this session have no category/country. Their sellers only see the
setup step if they come back through onboarding, for example after a subscription lapses.

---

## 2026-09-25 — Auth flow hardening; admin is one dedicated, server-provisioned email

**Status:** implemented this session. `flutter analyze`: 0 errors (2 pre-existing infos in untouched
files). `flutter test`: 36/37, the same pre-existing `seller_shell_controller_test.dart`
`NotificationCenter` failure. Functions `npm test`: 256/256 (6 new in `grantAdmin.test.js`). Rules
emulator suite: 35/35 (2 new). Not exercised against the live `sellora-20` project.

**Why:** user request — production-ready auth with security intact, and "admin has his separate email".

**Changed:**
- `firestore.rules`: `isAdmin()` is now the `admin` custom claim **only**; the `role() == 'admin'`
  fallback is gone, so no Firestore field grants admin. The `users` update rule also stops an admin
  from setting `role: 'admin'` on another account from the client.
- `functions/scripts/grant-admin.js` (new): the only way to make an admin. `node scripts/grant-admin.js
  <email> [--name ..]` creates the Auth account if needed (no password; prints a one-time reset link),
  sets the claim, and writes the `role: admin` profile. It refuses an email that is already a
  buyer/seller (the admin must use a separate email) and refuses a second admin. `--revoke` drops the
  claim, revokes refresh tokens, and deletes the profile.
- `FirebaseAuthRepository`: a `role: admin` profile without the claim is rejected
  (`admin-claim-missing`) at sign-in, session resume, and refresh. Sign-in force-refreshes the token so
  claim changes apply immediately. Firebase exceptions become a provider-neutral `AuthFailure(code)`.
  Emails are trimmed and lowercased. Sign-up sends a verification email (best effort, not enforced).
  `signOut` clears the cache.
- `AuthController`: maps errors by code, including `invalid-credential` (what Firebase returns with
  email-enumeration protection on, which previously fell through to "Something went wrong"),
  `too-many-requests`, `user-disabled`, and offline. Suspended sellers are signed out at sign-in and
  session resume. `signOut` clears `lastRole`.
- `Validators`: `password` (sign-in) only checks non-empty. The new `newPassword` (seller/buyer sign-up)
  requires 8–128 characters with letters and digits. The email regex now accepts `+` and long TLDs.
- `firestore-tests/*`: admin contexts now carry `{ admin: true }`.

**Deploy order (required, otherwise admin access is lost):** run `grant-admin.js` for the admin email
*before* `firebase deploy --only firestore:rules`. Any existing `role: admin` doc without the claim stops
working the moment the new rules deploy.

**Still open:** email verification is sent but not required for any action. Suspension is enforced in
the client only. Rules don't block a suspended seller's writes yet.

---

## 2026-09-25 — Identity is no longer mocked: Auth + Store always bind to Firebase

**Status:** implemented this session. `flutter analyze`: 0 issues (was 1 pre-existing error in
`test/auth_repository_test.dart`, unrelated to this change — fixed in passing, see below).
`flutter test`: 36/37 pass; the 1 failure (`seller_shell_controller_test.dart` missing a
`NotificationCenter` binding) pre-dates this session (confirmed via `git stash`) and is untouched.

**Why:** user request — stop the running app from sourcing sign-in/sign-up from
`MockAuthRepository`'s in-memory fake session and wire in the real `FirebaseAuthRepository`, which
already existed fully implemented but was never bound. `AppConstants.useMockData` previously switched
*every* repository together, and flipping it wholesale is blocked on a real CJ Dropshipping account and
a confirmed IntaSend production setup (see "Known gaps" in `CLAUDE.md`) — neither of which identity
depends on. `StoreRepository` moved with it rather than staying mocked, because
`FirebaseAuthRepository.signUpSeller` creates a seller's store through whatever `StoreRepository` is
bound: pairing a real, persisted Firebase Auth account with an in-memory `MockStoreRepository` would
have made a seller's own store vanish on every app restart (`MockStoreRepository` resets to
`MockSeedData`'s two seed stores on each launch) — worse than either being fully mocked or fully real.

**Changed:**
- `lib/app/bindings/initial_binding.dart`: `AuthService`, `FirestoreService`, and
  `StoreRepository`/`AuthRepository` (bound to `FirebaseStoreRepository`/`FirebaseAuthRepository`) are
  now registered unconditionally, before the `useMockData` branch, which now only covers
  Product/Order/Notification/Subscription/Admin/FxRate. `MockAuthRepository`/`MockStoreRepository` are
  no longer instantiated anywhere in the running app.
- `lib/main.dart`: `Firebase.initializeApp()` now runs unconditionally instead of being gated on
  `!useMockData`.
- `lib/core/constants/app_constants.dart`: `useMockData`'s doc comment corrected — it no longer
  describes "the entire app."
- `CLAUDE.md`, `README.md`: architecture/quickstart sections updated to describe the split (identity
  always real; catalog/orders/etc. still gated by `useMockData`) and to drop the now-dead
  "sign in with an email containing 'seller'/'admin'" quick-login shortcut, which only ever lived in
  `MockAuthRepository` and no longer applies once it isn't bound.
- `test/auth_repository_test.dart`: fixed a pre-existing, unrelated compile error (missing
  `user_model.dart` import for `sellerTermsVersion`) found while verifying this change — not part of
  the scope, but a one-line fix needed to run the suite at all.

**Deliberately not changed:** `MockAuthRepository`/`MockStoreRepository` themselves are untouched and
still exist — `test/auth_repository_test.dart` and `test/admin_dashboard_controller_test.dart` exercise
them directly (signup slug-dedup, terms-version, terms-acceptance business logic) independent of
`InitialBinding`, and rewriting that coverage against a Firebase-backed fake was out of scope.

**New consequence, disclosed:** the two demo storefronts `MockSeedData.stores()` seeds
(`aminas-picks` / `jengo-electronics`, matched to `MockProductRepository`'s seeded listings by
`storeId`) are no longer reachable by browsing — `StoreScope`/`FirebaseAuthController` now resolve
stores through real (likely empty) Firestore, which has no docs at those slugs. Only a real seller who
actually signs up gets a real, resolvable store; buyers can no longer browse a demo storefront without
one existing for real. `AppConstants.useMockData = true` still keeps that seller's *product catalog*
on mock data once inside their store, but the store itself, and getting a buyer to it, is now real.

**Still open / unverified:**
- Whether Email/Password sign-in is actually enabled on the live `sellora-20` Firebase project, and
  whether its deployed `firestore.rules` matches what's checked in here — this session read the rules
  file and reasoned the `users`/`stores`/`store_slugs` create rules support `signUpSeller`'s write
  order (user doc, then store), but did not exercise it against the real project.
- No new Firestore data was seeded for the two former demo stores; if browsable-without-signup demo
  storefronts still matter, that needs either seeding `stores`/`store_slugs` docs for them in the real
  project, or keeping a mock fallback for anonymous storefront browsing specifically.

---

## 2026-09-25 — PHASE 8: seller/store attribution + service-fee split (scaffold, no live payout)

**Status:** implemented this session. Functions (`functions`, `npm test`): 254/254 pass (4 new in
`orders.test.js`). Firestore emulator rules suite (`firestore-tests`, `npm test`): 33/33 pass, unchanged
— no `firestore.rules` edits were needed, since the fields this touches were already locked to
Cloud-Function-only writes by today's earlier PHASE 12 pass. `useMockData` is still `true`; none of this
has run against a real order.

**Why:** continuing SELLORA_IMPLEMENTATION_PLAN.md, scoped to PHASE 4 (CJ catalog/import UI) and a
PHASE 8 scaffold (seller/store/fee fields, explicitly *not* real IntaSend sub-account wiring — see the
next entry below for why PHASE 4 turned out to need no work at all).

**A deeper finding than "add sellerId/storeId fields":** `createOrder` never read a seller's own listing.
It re-derived its own retail price straight from CJ's supplier cost via `pricing.js`'s single global
margin config — the same pricing a bare single-vendor dropshipping app would use — completely ignoring
`stores/{storeId}/products/{pid}.sellPrice`, the price a seller actually set on the product_import
screen. This was already flagged, just not yet fixed: `ProductModel.sellPrice`'s own doc comment says
"what the *seller* has chosen to charge," and `FirebaseOrderRepository.placeOrder` already had an inline
comment disclosing that the adopted backend "ignores" `storeId` entirely.

**Changed:**
- `functions/lib/orders.js`'s `createOrder` now requires `storeId`, looks up
  `stores/{storeId}/products/{pid}` per line item (must exist, `isListed: true`, and the chosen `vid`
  must not be a seller-disabled variant — see `ManageVariantsController`), and prices each line at the
  seller's own `sellPrice` instead of recomputing a fresh CJ-margin price. Adds
  `buyerId`/`sellerId`/`storeId`/`serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue` to the order doc.
  The `buyerId` addition closes the exact gap today's earlier PHASE 12 entry's "Still open" list flagged
  (`FirebaseOrderRepository.buyerOrders` queries `buyerId`, which no server-created order carried until
  now). `estimatedProfitUsd` (Sellora's own take) is corrected to also subtract `sellerRevenueUsd` — it
  was silently counting the seller's share as platform profit. New pure `splitServiceFee(retailSubtotalUsd)`
  (2% of product subtotal only, never shipping — the decision already on record in
  SELLORA_IMPLEMENTATION_PLAN.md) is exported and unit-tested the same way `marginPricingService.js` is.
  The order is now also mirrored, write-once, into `stores/{storeId}/orders/{orderId}` (previously
  always empty); no screen reads that path yet (`sellerOrders`, the one the seller order queue/dashboard
  actually call, already worked off the flat collection and stays the live source), so its staleness
  after creation is a known, flagged-inline limitation, not a live bug.
- `functions/index.js`'s `createOrder` handler forwards the new `storeId` field.
- `lib/data/repositories/firebase_order_repository.dart`'s `placeOrder` now reads
  `serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue` back off the response — `OrderModel` already had
  these fields (added 2026-09-11 for the earlier, since-deleted backend) but they'd sat unused since the
  2026-09-12 backend swap. Its stale comments (claiming the adopted backend has "no seller/fee/store
  concept at all") are corrected.
- `functions/test/orders.test.js`: 4 new cases for `splitServiceFee` (rate, rounding reconstitution to
  the cent, zero, negative/NaN) and `validateOrderRequest`'s new `storeId` requirement.

**Not done, deliberately (user's explicit "scaffold, not full implementation" choice):** no real
IntaSend Split Payments sub-account wiring — money still flows exactly as before, one IntaSend/PayPal
charge, no split, no payout. The five API specifics from the 2026-09-09 design entry below (split
precision, sub-account KYC turnaround, Payouts API minimums/fees, settlement schedule, refund-on-split
behavior) are still unconfirmed against a real IntaSend account and are what actually blocks turning
this snapshot into a real payout. `refundOrder`/`attachPaymentAttempt`/the payment webhooks/
`retryFailedFulfillments`/`refreshOrderTracking` do not update the new `stores/{storeId}/orders` mirror
— flagged inline in `orders.js` for whoever wires a screen to read it.

**Verification gap, disclosed:** did not drive `createOrder` itself through the Firestore/functions
emulator — that needs a mocked-CJ-API test harness that doesn't exist for this file's async paths today
(the existing `orders.test.js` only unit-tests its pure helpers; this pass follows that same pattern
rather than inventing new infrastructure). Ran the existing `firestore-tests` rules suite as a
regression check instead (33/33 pass, unchanged) — it confirms `firestore.rules` still holds, not that
this new logic is correct end-to-end.

---

## 2026-09-25 — SELLORA_IMPLEMENTATION_PLAN.md correction: PHASE 4 was already done

**Status:** documentation-only, no code changed.

**Why:** auditing "what hasn't been done" against the plan doc's own text, before starting the PHASE 8
work above, found its PHASE 4 section stale — it still read as if catalog-browse/shipping-estimate UI
didn't exist, three commits after they'd actually shipped (`git log` on the relevant files: "catalog and
cj import" 2026-09-18, "added freight options" 2026-09-22).

**What's actually true, confirmed by reading the code, not just commit messages:**
- Category browsing: `SellerCatalogController.loadCategories()` → `ProductRepository.categories()` →
  `CjDropshippingService.getCategories()` → the `getCategories` Cloud Function, rendering the seller
  catalog screen's filter chip row.
- Shipping estimate: `ProductImportController._loadShippingEstimate()` and `CheckoutController`'s
  shipping picker both call `CjDropshippingService.calculateFreight()`/`getShippingOptions()` → the
  `calculateFreight` Cloud Function.
- CJ-catalog-to-per-seller-listing import mapping: the `product_import` screen (2026-09-18/19) already
  does this — variant picker, landed-cost pricing card, save-as-draft vs. publish via `isListed`.
- Buyer-facing variant selector: also already shipped (`_BuyerVariantPicker` in
  `product_details_view.dart`) — the plan's PHASE 5 section separately claimed this didn't exist either;
  same staleness, same fix.

**What's genuinely still missing:** a server endpoint exposing the *full*
`marginPricingService.calculatePricing()` formula (advertising/refund/VAT/fx-aware) to the client —
`ProductImportController.priceForMargin` does its own simpler `landedCost * (1 + margin/100)` markup
instead. Whether that's a real gap or an intentional simplification is a product call, not a confirmed
defect, so left alone.

**Changed:** `SELLORA_IMPLEMENTATION_PLAN.md`'s PHASE 4 and PHASE 5 (variant-selector line) sections
corrected in place, marked with a `2026-09-25 correction` note rather than silently rewritten, so a
later session can see what the text used to claim. This entry.

---

## 2026-09-25 — PHASE 12: security + production audit and fixes

**Status:** implemented this session. Emulator rules suite (`firestore-tests`, `npm test`): 33/33
pass (15 new in `production-hardening.test.js`; one `tenant-isolation` setup changed, see below).
Functions (`functions`, `npm test`): 244/244 pass (17 new). `flutter analyze`: the same 3
pre-existing issues. `flutter test --concurrency=1`: only the same 2 pre-existing failures
(`auth_repository_test.dart` compile error, `seller_shell_controller_test.dart` `NotificationCenter`
setup) plus the new `slug_test.dart` passing. With default concurrency,
`admin_dashboard_controller_test.dart` also fails *to load* intermittently; it passes alone and
serially, so that's a parallel-load flake, not a regression. `flutter build web` succeeds. Nothing
deployed; `useMockData` is still `true`, so none of this has run against real Firebase.

**Why:** TODO.md's STATUS row called PHASE 12 "done" on the strength of the 2026-09-11 pull-forward.
Auditing all ten TODO areas showed real holes left, including two privilege escalations.

**Findings and what changed:**

| # | Area | Finding | Fix |
|---|---|---|---|
| 1 | Rules / auth | **Critical.** `users` *create* didn't restrict `role`: a brand-new account could create its own doc with `role: 'admin'` (or an active subscription). The 2026-09-11 fix only locked *update*. | Self-create now only allows `buyer`/`seller`, `sellerStatus` null/`pendingApproval`, no subscription fields. This matches exactly what `signUpBuyer`/`signUpSeller` write. |
| 2 | Rules / payments | `stores/{id}/orders` *create* was client-allowed with any `total`. | `create: if false`, like flat `orders`. No client wrote there. |
| 3 | Rules / payments | A seller (or admin) could update **any** order field, e.g. `paymentStatus: 'paid'` + `cjOrderStatus: 'FAILED'`, which would get `retryFailedFulfillments` to push an unpaid order to CJ on Sellora's wallet. | Sellers: only `status` (must be an `OrderStatus` value) + `updatedAt`. Admins: anything except `serverOwnedOrderFields()`. |
| 4 | Rules / tenancy | Store `slug` was mutable and not unique. A seller could re-point their store at another seller's `/s/:slug`. Any signed-in user (not just sellers) could create stores. | New `store_slugs/{slug}` reservation written in the same batch as the store (`FirebaseStoreRepository.createStore`); `stores` create requires it, the `seller` role, and a well-formed slug. `id`/`slug`/`sellerId`/`createdAt` are immutable. `slugify` caps at 60 chars. |
| 5 | Rules / permissions | Functions authorize admins by the `admin` custom claim, while rules used only the `role` field. Two sources of truth. | New `isAdmin()` accepts the claim (checked first, no doc read) or `role`. |
| 6 | Rules / data | `createOrder` stores the buyer as `userId`/`uid`, but rules only let `buyerId` read. Buyers couldn't read their own server-created orders. | Flat `orders` read accepts `userId` too. (The client still *queries* `buyerId`, see Still open.) |
| 7 | Rate limiting | No per-user limits, only global `maxInstances`. `payOrderMpesa` could be looped to spam STK prompts at a phone. | New `functions/lib/rateLimit.js`: Firestore fixed-window counters (`rate_limits/{policy}_{uid}`, Admin-only) on every signed-in endpoint, 429 + `Retry-After`. It fails open if Firestore itself errors. |
| 8 | Error handling | `sendError` returned raw `err.message` with a 500: CJ/IntaSend error bodies, Firestore paths. The public webhooks echoed it too. | New `functions/lib/errors.js` (`HttpError`, `badRequest`/`notFound`/`unprocessable`). Only those messages reach callers; everything else becomes a generic 500 and is logged in full. Validation throws in `orders.js`/`reviews.js`/`subscriptions.js` converted, so they now return 400/404/422 instead of 500. |
| 9 | Validation | `calculateFreight` forwarded `products[]` to CJ unbounded and unvalidated. `phoneNumber` was unchecked. Ids went straight into doc paths. | `validateFreightRequest` (≤50 lines, `sanitizeId` vids, int quantity 1–20, 2-letter countries), `isValidMpesaPhone` (`^254[17]\d{8}$`, same as the client validator), `sanitizeId` on every `orderId`/`billingEntryId`. |
| 10 | Payment security | `redirectUrl`/`returnUrl`/`cancelUrl` were passed to IntaSend/PayPal as sent: an open redirect off a trusted payment page. | `isAllowedRedirectUrl`: https + an allowlisted origin (Hosting domains + sellora.app, override with `ALLOWED_REDIRECT_ORIGINS`). `http://localhost` is accepted only under the emulator. |
| 11 | Authentication | `verifyIdToken` didn't check revocation, so a disabled account's token worked for up to an hour. | `verifyIdToken(token, true)`. Costs one Auth lookup per signed-in request. |
| 12 | Secrets | No secret is committed; `git log -S` finds none of the credential values in history. `functions/.env` is gitignored. | No change. See Still open about that file. |

A test fixture changed: `tenant-isolation.test.js`'s "store owner cannot read another store's
orders" used a *buyer creating a store order with `total: 1000`* as setup, which is finding #2. It
now seeds the order with rules disabled; its read assertions are unchanged.

**Audited, no change needed:** `requireAuth` precedes every non-public handler. The webhooks re-verify
with the provider and bind invoice → order, so a forged IntaSend webhook can't fulfil anything.
`cors: true` is fine because auth is a bearer token, not a cookie. Public browse endpoints are already
clamped (`params.js`) and cached. The client surfaces the server's `message`, so the new 429 and
generic-500 texts reach users with no client change.

**Still open (not attempted this session):**
- Admin access still falls back to the Firestore `role` field. Set the `admin` claim on every admin
  (`setCustomUserClaims`), then delete the `role() == 'admin'` half of `isAdmin()`.
- App Check is report-only (`ENFORCE_APP_CHECK`); the Flutter client doesn't send tokens yet.
- Configure a Firestore TTL policy on `rate_limits.expireAt` at deploy time; without it, counter docs
  accumulate (one per user per policy, so bounded but never cleaned).
- `functions/node_modules` (5,168 files) is tracked in git from before `.gitignore` covered it.
  `git rm -r --cached functions/node_modules` fixes it; not done here because it's a large commit
  the owner should make deliberately.
- `functions/.env` holds live-looking provider credentials in plaintext. These belong in Secret Manager
  (`firebase functions:secrets:set`). A `.env` key with the same name as a `defineSecret` param also
  conflicts at deploy.
- `FirebaseOrderRepository.buyerOrders` queries `buyerId`, which server-created orders don't have.
  Rules now permit reading by `userId`, but the query and `OrderModel.fromMap` still need
  reconciling with `createOrder`'s shape (a data-model gap, not a security one).
- Crashlytics/monitoring, Firestore backups, deployment runbooks, performance profiling.

---

## 2026-09-25 — PHASE 11: internationalization (first slice)

**Status:** implemented this session. `flutter analyze` shows only the same 3 pre-existing issues
(`responsive.dart`/`mock_admin_repository.dart` curly-brace info, `test/auth_repository_test.dart`'s
missing-`sellerTermsVersion` compile error). `flutter test`: the new `money_test.dart` and
`countries_test.dart` pass (19 cases) along with `admin_dashboard_controller_test.dart`; the only
failures are the same two pre-existing ones (that compile error, and `seller_shell_controller_test.dart`'s
`NotificationCenter` setup gap). `flutter build web` succeeds. Not click-through-verified in a live
browser this session.

**Why:** TODO.md's PHASE 11 lists multi-currency, country configuration, shipping zones,
international payment architecture and localization readiness. Auditing first showed the server
already had most of the currency backbone — `functions/lib/regions.js` (country → pricing region →
currency) and `functions/lib/fx.js` (a daily USD-base rate cache at `config/fx`) — while the Flutter
side had a USD/KES-only display toggle on a hardcoded `AppConstants.usdToKesRate`, a hand-picked
5-country checkout list, and M-Pesa as the *only* payment option for every country, including US/UK/EU
buyers who can't use it. This slice closes the client-side gaps against what the server already does.

**Changed:**
- **New `lib/core/i18n/`:**
  - `currencies.dart` — `CurrencyInfo`/`Currencies` registry (KES, USD, GBP, EUR: symbol, name,
    minor-unit digits). `Formatters.currency` now reads symbols/decimals from it.
  - `money.dart` — `Money`, an integer-minor-unit amount (build spec §36). Exact `+`/`-`/`× quantity`,
    one explicit rounding for `scale`/`convertTo`, and throws on mixing currencies. Models still store
    `double` major units — `Money` is used at the arithmetic sites (cart subtotal, checkout total,
    conversion), not persisted.
  - `countries.dart` — `CountryConfig`/`Countries` (KE, US, GB + all 27 EU members), `ShippingZone`
    (kenya/us/uk/eu — the same ids and currencies as regions.js's regions, including its US/USD
    fallback for unknown countries), and `PaymentMethodType` (M-Pesa for Kenya only; card everywhere).
    `test/countries_test.dart` parses regions.js and fails if the two drift apart.
  - `app_locales.dart` — `flutter_localizations` delegates + `supportedLocales`, wired into
    `GetMaterialApp`. English only, deliberately — see "Still open".
- **FX rates:** new `FxRates` model (pivot logic mirrors fx.js's `pivotRate`; `FxRates.fallback`
  mirrors its `FALLBACK_RATES`), `FxRateRepository` with `FirebaseFxRateRepository` (reads `config/fx`)
  and `MockFxRateRepository`, both bound in `InitialBinding`. `firestore.rules` opens **only**
  `config/fx` for public read (it's market data the server writes; the rest of `config` stays denied).
- **`CurrencyService`** supports all four currencies, converts via `Money` using the loaded rate table
  (`refreshRates()` fires once at startup, falls back silently), and exposes `isConverted()`.
  `AppConstants.usdToKesRate` is deleted. The buyer profile's USD/KSh segmented toggle is now a
  four-currency dropdown.
- **Shipping zones:** `StoreModel.shippingZones` (zone ids; a document without the field defaults to
  all zones — the same countries checkout offered before). "Customize store" gains a Shipping zones
  section (can't disable the last zone). Checkout's country dropdown now lists only countries in the
  store's zones, Kenya first.
- **Checkout:** CJ freight quotes (`FreightOption.currency`, USD) are converted into the cart's
  currency before being added to the subtotal — previously the raw numbers were summed regardless of
  currency (latent today since listings default to USD too, but wrong the moment a store prices in
  KES). Totals are computed in `Money`. A payment-method picker offers what the destination country
  supports; the M-Pesa phone field only shows for M-Pesa. Real-mode card payment calls the existing
  `payOrderCard` endpoint and opens IntaSend's hosted page via the new `url_launcher` dependency;
  `CheckoutController.placeOrder` also refuses a method the country doesn't support, not just the UI.
  A note appears when prices are shown converted.
- **pubspec:** added `url_launcher`, `flutter_localizations`; `intl` bumped `^0.19.0` → `^0.20.2`
  (flutter_localizations pins 0.20.2; only `NumberFormat`/`DateFormat` are used, unchanged).

**Still open (not attempted this session):**
- Shipping zones are enforced client-side only. The adopted single-vendor `createOrder` has no
  store concept to check a store's zones against — same root gap as PHASE 8's service-fee note.
- Every IntaSend charge is still in KES (`payOrderCard`/`payOrderMpesa` charge `order.totalKes`),
  so a GBP/EUR buyer's card is charged the KES equivalent. A true multi-currency settlement needs
  either IntaSend multi-currency confirmation or a second provider (`paypalApi.js` exists server-side,
  unreconciled). There's still no `PaymentProvider` interface — checkout switches on
  `PaymentMethodType`, which is a step toward one, not the abstraction itself.
- Monetary *models* (`OrderModel.total`, `ProductModel.sellPrice`, …) are still `double`; moving
  persisted amounts to minor units needs a coordinated server/Firestore migration.
- No per-store currency selector: `StoreModel.currencyCode` exists, but products carry their own
  `currency` and nothing re-prices them when a store's currency changes, so exposing it would mislead.
- Localization is wired but English-only: all UI strings are still inline literals. Next step is
  extracting them into ARB files (`flutter gen-l10n`) before adding e.g. Swahili.
- `CurrencyService` has no unit test of its own (`StorageService`/`GetStorage` need test setup
  nobody has built yet); its conversion logic is covered through `FxRates`/`Money` tests.

---

## 2026-09-25 — Sellora visual identity assets

**Status:** implemented this session. Focused `flutter analyze` of the updated splash view completed
without reported issues. No behavioral, routing, backend, or theme-token changes were made.

**Changed:**
- Added `assets/images/sellora-splash-logo.png`, the supplied Sellora wordmark/tagline artwork, and
  changed the in-app `SplashView` to a white background using that asset instead of the previous
  navy, text-rendered wordmark/tagline.
- Added `assets/images/sellora-app-logo.png`, the supplied cart/S app mark. It appears above the
  wordmark in `SplashView` and was rendered into each Android launcher-icon density at
  `android/app/src/main/res/mipmap-*/ic_launcher.png` (mdpi through xxxhdpi). The Android manifest
  already points at `@mipmap/ic_launcher`, so no manifest change was needed.
- Replaced `web/favicon.png` with the supplied favicon artwork, rendered as a 32×32 PNG. The existing
  `web/index.html` favicon reference remains unchanged and now serves the new icon.

**Still open:** iOS is not present in this repository, so no iOS app-icon asset was added. The web
PWA manifest icons were intentionally left unchanged; the request was specifically for the browser
favicon.

---

## 2026-09-22 — PHASE 10: admin platform-financial overview + Stores tab (first slice)

**Status:** implemented this session. `flutter analyze` clean (same 3 pre-existing issues as every
recent entry — `responsive.dart`/`mock_admin_repository.dart` curly-brace lint info, and
`test/auth_repository_test.dart`'s missing-`sellerTermsVersion` compile error). `flutter test` shows
the same two pre-existing failures as before this change (that compile error, and
`test/seller_shell_controller_test.dart`'s `NotificationCenter` setup gap) plus the new
`admin_dashboard_controller_test.dart` passing — nothing newly broken. Verified with that new unit
test against the real mock repositories; not click-through-verified in a live browser this session.

**Why:** TODO.md's STATUS table called PHASE 10 "Not started (existing admin screens are
marketplace-era mocks)". That was stale — auditing `lib/modules/admin/` first (before writing
anything, per TODO.md §2/§49's audit-first rule) showed the Overview/Sellers/Sync/Orders/Plans tabs
already call `AdminRepository`/`OrderRepository`/`SubscriptionRepository`/`StoreRepository`, which are
bound to `Firebase*`/`Mock*` implementations exactly like every other module — there was no
marketplace-era mock UI left to replace. What TODO.md §34/§35 actually calls for and was genuinely
missing: a platform financial model that keeps seller GMV separate from Sellora's own revenue ("Do NOT
confuse seller GMV with Sellora revenue"), and any admin visibility into `stores` at all — the
multi-tenant migration (stores/{storeId}/products, .../orders) landed weeks ago but no admin screen
ever read `StoreRepository.allStores()`, despite that method's own doc comment already flagging it for
"admin cross-store oversight later" (`store_repository.dart:5`). PHASE 10 is a 15+ subsystem spec
(users, stores, subscriptions, plans, catalog, orders, fees, payments, refunds, categories, themes,
coupons, reports, support, feature flags, settings); rather than attempt all of it, this session
scoped to the two gaps closest to the seams the app already has real data for, following the same
single-slice-per-session discipline as PHASE 9.

**Changed:**
- **`AdminDashboardController`** (`lib/modules/admin/dashboard/admin_dashboard_controller.dart`)
  rewritten: now also injects `StoreRepository` and `SubscriptionRepository`. Adds `serviceFeeRevenue`
  (sum of `OrderModel.serviceFeeAmount` on paid orders — real against mock data; still 0 against the
  live backend because `functions/lib/orders.js`'s `createOrder` has no seller/fee concept and never
  populates the field, a pre-existing, already-documented gap, not a new bug), `subscriptionMrr` (every
  seller with `hasActiveSubscription == true`, priced at their matched `SubscriptionPlanModel.priceKes`
  — KES-only, deliberately: there's no currency-conversion service yet, PHASE 11 is still not started),
  `subscriptionArr` (`mrr * 12`), `totalPlatformRevenue` (`serviceFeeRevenue + subscriptionMrr`,
  excluding seller GMV on purpose), plus seller-breakdown counts (active/pending/suspended/new-in-30d)
  and a store count. `totalGmv` narrowed to only sum paid orders (was every order regardless of
  payment status).
- **`admin_dashboard_view.dart`** rewritten to match: a "Platform revenue" stat grid (GMV / service-fee
  revenue / subscription MRR / total platform revenue) above the existing "Sellers & stores" grid and
  recent-orders list.
- **New `lib/modules/admin/stores/`** (`admin_stores_controller.dart` + `admin_stores_view.dart`) — a
  read-only, searchable (name/slug/owner) list of every store on the platform via
  `StoreRepository.allStores()`, cross-referenced against `AdminRepository.fetchSellers()` for the
  owner's name/email/status. Tapping a store opens a detail bottom sheet (slug, owner, currency,
  created date). No store-level suspend/activate action — `StoreModel` has no status field, and adding
  one unenforced anywhere would be exactly the "placeholder button that does nothing" TODO.md §54 warns
  against; suspending the owning seller (already wired in the Sellers tab) is the real lever today.
- **`admin_shell_view.dart`/`admin_binding.dart`**: added the Stores tab (6 tabs now). Sellers' icon
  changed from `Icons.storefront_outlined` to `Icons.people_alt_outlined` since Stores now legitimately
  owns the storefront icon.
- **New `test/admin_dashboard_controller_test.dart`**: seeds one paid and one pending-payment mock
  order and asserts GMV/service-fee revenue only count the paid one, MRR matches the mock admin
  repository's one active `growth`-plan seller, and seller/store counts are correct.
- **TODO.md / SELLORA_IMPLEMENTATION_PLAN.md**: PHASE 10 status rewritten to correct the stale
  "not started" framing and record what shipped vs. what's still open.

**Still open (not attempted this session):** store suspension (needs a `StoreModel` status field plus
rules enforcement), refunds UI (server logic exists per PHASE 8's `functions/lib/refunds.js` but has no
`ApiEndpoints` entry or admin screen), coupons, categories, themes, feature flags, platform settings,
reports/support, and churn (needs a historical subscription-state snapshot this session didn't build).

---

## 2026-09-21 — PHASE 9: seller dashboard analytics (first slice)

**Status:** implemented this session. `flutter analyze` clean (same 3 pre-existing issues as every
recent entry). `flutter test` shows the same two pre-existing failures as before this change
(`test/auth_repository_test.dart`'s missing `sellerTermsVersion` compile error and
`test/seller_shell_controller_test.dart`'s `NotificationCenter` setup gap) — nothing newly broken.
Verified with a widget test against the real mock repositories (seller Home renders every new
section — metrics, sales chart, status breakdown, top products, store health, onboarding checklist —
with no exceptions, and switching the date-range chip recomputes cleanly); not click-through-verified
in a live browser this session.

**Why:** PHASE 9 ("Analytics + marketing") was untouched — the seller Home screen was three static
stat tiles (`seller_dashboard_controller.dart`, pre-change: revenue/listing-count/pending-count) with
no date filtering, no chart, and TODO.md §9's guided-setup checklist never built. Discount codes,
customer analytics, and marketing campaigns are all separate, larger slices of the same phase and
were deliberately deferred rather than attempted alongside this one (see the scoping conversation this
session) — discounts need a new model plus a checkout change, customer analytics needs a `CustomerModel`
that doesn't exist yet, and marketing campaigns have no email/SMS provider wired up to make them real.

**Changed:**
- **`lib/modules/seller/dashboard/dashboard_models.dart`** (new) — `DateRangeOption` enum (Today/
  Yesterday/Last 7/30/90 days/This year/Custom) plus `SalesPoint` and `TopProductStat`, the view's
  chart/top-products aggregates.
- **`SellerDashboardController`** rewritten: fetches the seller's full order/listing history once,
  then derives everything else client-side per selected range — gross sales and net revenue (the
  latter from `OrderModel.sellerRevenue`, the fee snapshot already computed server-side at order
  creation, not re-derived), order count/AOV, a cancelled count, a per-`OrderStatus` breakdown, top
  products by revenue, a sales-over-time series (daily buckets, monthly for "This year"), and a
  percent-change-vs-previous-period delta for sales/orders. `pendingFulfillmentCount` stays
  unfiltered by date range deliberately — it's an operational queue, not a historical metric.
  Store-health fields (`SubscriptionUsageModel` usage, matched `SubscriptionPlanModel`, an
  orders-this-billing-period count) are fetched alongside.
- **Onboarding checklist scoped to only what's real**: TODO.md §9's suggested checklist includes
  "Choose theme," "Add domain," "Configure payment," "Configure shipping" — none of those features
  exist in this codebase yet (no theme system, no domain management, no seller-level payment/shipping
  settings). Showing checkboxes for them would be exactly the "placeholder buttons that do nothing" /
  "claim a feature works when it doesn't" TODO.md itself warns against, so the shipped checklist only
  has the four items backed by real, verifiable state: import a product, publish one, customize the
  storefront (any of `StoreModel`'s tagline/logo/banner/color set — all null at store creation, see
  `auth_repository.dart`'s `_createStoreForSeller`), and make a first sale. The card hides entirely
  once all four are done.
- **`seller_dashboard_view.dart`** rewritten to match: date-range `ChoiceChip` row (+ a custom
  `showDateRangePicker` option), a 6-tile metrics grid with previous-period deltas, an `fl_chart`
  `LineChart` sales-over-time card (single series, brand gold, touch tooltip, an explicit empty state
  instead of a zeroed chart), an order-status breakdown card, a top-products card, a store-health card
  (plan name, listing/order usage bars, taps through to `/seller/subscription`), and the checklist —
  desktop gets the two mid-page cards side by side via `Row`+`Expanded`, not a `Wrap` with
  `SizedBox(width: double.infinity)` (that combination throws — `Wrap` gives unbounded main-axis
  constraints, and an infinite-width child conflicts with them; caught before shipping).
- **`fl_chart: ^0.69.2`** added to `pubspec.yaml` — the package was already named in a "common next
  additions" comment there for exactly this purpose.
- **Fixed a real, pre-existing bug** in `MockOrderRepository.updateStatus`: it rebuilt the order via a
  bare `OrderModel(...)` constructor call that silently dropped `paymentStatus` and the whole fee
  snapshot (`serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue`/`paymentFee`) back to their zero
  defaults every time a seller advanced an order's fulfillment status — which would have corrupted the
  exact fields this new dashboard reads for "paid" filtering and net-revenue totals in demo mode. Now
  uses `copyWith(status: status)`, which preserves everything else.

**Not done / open:** discount codes, a `CustomerModel` and customer-level analytics, marketing
campaigns/abandoned-cart/email tooling (all deferred, see "Why" above) — the STATUS table and
`SELLORA_IMPLEMENTATION_PLAN.md` still list these as not started under PHASE 9. No live-browser
click-through this session (verified via widget test instead, see Status above) — a later session
should still eyeball it in Chrome, especially the `fl_chart` sales-chart tooltip and the mobile-width
stacked layout for the status-breakdown/top-products cards.

## 2026-09-20 — PHASE 7: buyer shopping flow unified under `/s/:slug`

**Status:** implemented this session. `flutter analyze` clean (same 3 pre-existing issues as every
recent entry — `responsive.dart:95`, `mock_admin_repository.dart:49`,
`test/auth_repository_test.dart:63` — none touched by this change). `flutter test` shows the same two
pre-existing failures as before this change (`test/auth_repository_test.dart` — the same missing
`sellerTermsVersion` import above — and `test/seller_shell_controller_test.dart`'s `NotificationCenter`
setup gap, confirmed pre-existing by re-running it against `git stash`); nothing newly broken.
`flutter build web` succeeds. Not click-through-verified in a browser this session — same disclosed gap
as most prior entries.

**Why:** `TODO.md`/`SELLORA_IMPLEMENTATION_PLAN.md` listed PHASE 7 ("Replace the shared buyer feed with
`/s/:slug` storefront pages, store-bound carts, customer profiles beneath that store") as not started,
but that was stale — `StoreScope`, a guest-browsable `StorefrontView` at `/s/:slug`,
`CartRepository.storeId`/`setStore`, `OrderModel.storeId`, and store-scoped
`buyerStoreOrders`/`storeProducts` repository methods already existed (see the 2026-09-11 and
2026-09-13 entries). What was actually missing, per the 2026-09-13 entry's own "Not done" note, was
that cart/checkout was never wired into the public `StorefrontView` — a signed-in buyer still shopped
through a completely separate, flat `/buyer` shell that a guest could never reach, while
`StorefrontView`'s product cards did nothing on tap. Two parallel, duplicate feed implementations
existed side by side: `StorefrontView` (guest, `/s/:slug`, `storeProducts()`) and
`BuyerHomeView`/`BuyerHomeController` (signed-in, flat `/buyer`, `sellerListings()`).

**Changed:**
- **`Routes.storefront` (`/s/:slug`) is now the buyer shell itself** (`BuyerShellView`, bound with both
  `StorefrontBinding()` and `BuyerBinding()`) instead of a standalone `StorefrontView` page — one URL
  serves guests and signed-in buyers alike, so signing in never changes the address.
  `Routes.buyerShell`/`buyerProductDetails`/`buyerCheckout` (flat `/buyer...`) are gone, replaced by
  `Routes.storefrontProduct`/`storefrontCheckout` (`/s/:slug/product`, `/s/:slug/checkout`) — still
  guest-reachable (no `RoleMiddleware`), since a guest can browse a product and hold a cart; checkout
  gates its own submit step in-widget instead.
- **Deleted `lib/modules/buyer/home/`** (`BuyerHomeController`/`BuyerHomeView`) outright —
  `StorefrontView` was already a strict superset (same search/category/grid, plus logo/banner/account
  icon `BuyerHomeView` never had) once its product tap was wired up. `StorefrontView` is now the
  shell's "Shop" tab for everyone; its account icon jumps to the Profile tab in-place
  (`Get.find<BuyerShellController>().changeTab(4)`) when already signed in here, instead of navigating
  to the now-deleted `Routes.buyerShell`.
- **`BuyerShellController`** now resolves `StoreScope` from the route's `:slug` itself
  (`resolveStore()`), mirroring `SellerShellController`'s already-proven pattern exactly — constructor-
  injected deps for testability, same `resolveStore`/gate naming. This is also what calls
  `CartRepository.setStore(store.id)`, now regardless of auth state, so a guest can add to cart before
  ever signing in. **`BuyerShellView`** gates rendering on `scope.isResolving`/`current`/`errorMessage`
  before showing the tab shell, same shape as `SellerShellView`'s guard.
- **`StorefrontController.load()`** simplified: it no longer calls `scope.resolveSlug()` itself (the
  shell now owns that single resolution call) — it just reads the already-resolved
  `scope.current.value`. Fixes a real, if minor, bug along the way: the old version re-resolved the
  slug from scratch on every search keystroke and category tap.
- **Checkout gains a sign-in gate**: `CheckoutView` now renders a "Sign in to complete your order"
  `EmptyState` instead of the order form when the cached user isn't a signed-in buyer of the cart's
  store — closes a real, previously-open gap (`buyerCheckout`/`buyerProductDetails` had no
  `RoleMiddleware` at all, so they were reachable unauthenticated with no guard whatsoever).
  Deliberately no post-login redirect-back to checkout — the buyer's cart survives the sign-in
  round-trip untouched (same store), so they just tap Checkout again from the shop tab. Building
  return-URL plumbing was scoped out.
- **Bug fixed along the way:** `BuyerOrdersController.loadOrders()` left `isLoading` stuck `true`
  forever for a guest (the `user == null` guard returned before setting it false) — a guest on the
  Orders tab saw an infinite spinner. Now clears `orders` and sets `isLoading = false`.
  `BuyerOrdersView`/`BuyerProfileView` both gained a "sign in to continue" `EmptyState` for a guest,
  instead of a stuck spinner or blank name/email fields.
- **`AuthController._goToHome`**'s buyer branch now resolves the buyer's store slug (from
  `Get.parameters['slug']`, already known during sign-in/registration since those happen from
  `/s/{slug}/login`/`register`; falls back to a `StoreRepository.storeById` lookup only for
  `checkSession()`'s cold-start case) and lands on `/s/{slug}` instead of the deleted flat
  `Routes.buyerShell`.
- **`RoleMiddleware`**'s wrong-role redirect for a buyer now points at `Routes.marketing` instead of
  the deleted `Routes.buyerShell` — this branch only fires if a signed-in buyer manually navigates to a
  seller/admin URL, and `redirect()` is synchronous with no cheap way to recover a slug, so this is
  strictly better than the dead reference it replaces rather than a full fix.

**Deliberately not done this pass** (per the plan's scope, to avoid touching work blocked elsewhere):
collections browsing (no model yet — PHASE 5 item), a dedicated `Customer` model or reading
`stores/{storeId}/customers` (nothing reads that mirror doc today), migrating order writes onto
`stores/{storeId}/orders` (the adopted Cloud Functions backend has no store concept server-side at all
— separate PHASE 8 backend work), client-side one-seller-per-cart validation at add-to-cart time (still
relies on the server-side `createOrder` rejection), a multi-store switcher, an order-detail/tracking
screen, and search/SEO improvements beyond what already existed.

---

## 2026-09-20 — PHASE 6: store builder, device photo picker for logo/banner

**Status:** implemented this session. `flutter analyze` clean (same 3 pre-existing issues as the
2026-09-19 entry below — `responsive.dart:95`, `mock_admin_repository.dart:49`,
`test/auth_repository_test.dart:63` — none touched by this change).

**Why:** the branding slice shipped 2026-09-19 only let a seller paste an already-hosted image URL
into the logo/banner fields, which isn't something a real seller has for their own photos. No seller-
side image upload exists anywhere else in the app either (`firebase_storage` is deliberately not a
dependency yet — see pubspec.yaml's "common next additions"), so this needed a way to work without a
storage backend.

**Changed:**
- **`pubspec.yaml`**: added `image_picker: ^1.1.2`.
- **New `lib/core/utils/image_data_url.dart`**: encodes picked image bytes as a `data:<mime>;base64,…`
  URI (`bytesToDataUrl`/`mimeTypeForPath`) and decodes one back to bytes (`decodeDataUrl`, `null` on
  malformed input — same "bad input is just unset" convention as `hexToColor`). `maxPickedImageBytes`
  (350KB) keeps a `StoreModel` update well under Firestore's 1MB document limit, since
  `FirebaseStoreRepository.updateStore` writes the whole model in one `.update()` call.
- **`StoreCustomizeController`**: new `pickLogo()`/`pickBanner()`, backed by a shared `_pickImage`
  helper — `ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1024)`,
  rejects anything over `maxPickedImageBytes` with a snackbar, otherwise writes the encoded `data:`
  URI straight into the existing `logoUrlCtrl`/`bannerUrlCtrl` text controllers — `save()` and the URL
  text fields didn't need to change at all, a data URI is just another string in the same field.
  `isPickingLogo`/`isPickingBanner` drive per-button loading state.
- **`StoreCustomizeView`**: an "Upload from device" button under each of the logo/banner fields; the
  URL text field stays too, for a seller who already has a hosted image. `_ImagePreview` now checks
  `isDataUrl()` and renders via `Image.memory(decodeDataUrl(...))` instead of `CachedNetworkImage`
  when the field holds a picked photo rather than a URL.
- **`StorefrontView`**: the buyer-facing logo avatar and banner image do the same `isDataUrl()` check,
  so a picked-from-device logo/banner actually renders on the storefront, not just the editor preview.

**Not done:** no real upload — this inlines the photo as a string rather than storing it in
`firebase_storage`, so a store with both a large logo and banner pushes its `StoreModel` document
size up (bounded to under ~1MB total by `maxPickedImageBytes`, but still far from ideal versus a real
CDN-hosted URL). Moving to actual `firebase_storage` upload is still open, same as it was before this
change — the pubspec.yaml comment on it is unchanged in kind, just narrower in scope. No image
cropping/aspect-ratio enforcement either — a very wide or very tall photo just gets `BoxFit.cover`-ed
into the existing circular/rectangular preview slots, which can crop awkwardly.

**Not verified live in a browser this session** — same caveat as 2026-09-19's entry; analyzer-clean
but no actual click-through of the gallery picker (particularly worth checking on `flutter run -d
chrome`, where `image_picker` uses the browser's native file input).

---

## 2026-09-19 — PHASE 6: store builder, branding slice (retroactive entry)

**Status:** committed (`cc5ae75`, "store builder") but this WORKLOG/TODO/plan update didn't happen in
that session — writing it up now before continuing. Re-ran `flutter analyze` this session: 2 pre-
existing info-level issues (`responsive.dart:95`, `mock_admin_repository.dart:49`) plus one
pre-existing error (`test/auth_repository_test.dart:63`, missing import for the top-level
`sellerTermsVersion` const — unrelated to this commit, not touched by it). No new issues from the
store builder change itself.

**Scope decision:** PHASE 6 per `SELLORA_IMPLEMENTATION_PLAN.md` is theme/section/block/setting
models plus a renderer/preview/publish flow — a large piece of work. This slice is deliberately just
the branding fields `StoreModel` already carries (`name`, `tagline`, `logoUrl`, `bannerUrl`,
`primaryColorHex`) — no new model fields, no sections/blocks, no theme picker beyond a single accent
color.

**Changed:**
- **`lib/core/utils/color_utils.dart`** (new): `hexToColor`/`colorToHex`, tolerant of a missing/
  malformed hex (returns `null` rather than throwing) so an unset store color falls back to the
  default theme color.
- **`Validators.hexColor`** (new, `validators.dart`): only enforces `#RRGGBB` formatting when the
  field is non-empty — the accent color is optional.
- **New `lib/modules/seller/store_customize/`** (`StoreCustomizeController` + `StoreCustomizeView`):
  edits a local copy of the current `StoreScope.current` store's branding fields (5 preset accent
  swatches plus a free-text hex field with inline validation, logo/banner URL fields with a live
  `CachedNetworkImage` preview), saves via the existing `StoreRepository.updateStore` — no repository
  or Firestore-rules changes needed. New route `Routes.sellerStoreCustomize`
  (`/seller/store/customize`), bound in `StoreCustomizeBinding` (added to `seller_binding.dart`),
  registered in `app_pages.dart` behind the same `RoleMiddleware(UserRole.seller)` every other seller
  route uses.
- **`SellerProfileView`**: new "Customize store" list tile above the existing payments tile, opening
  the new screen.
- **`StorefrontView`**: now renders the store's `logoUrl` as an `AppBar` leading avatar, its
  `bannerUrl` as a banner image above the category chip row (both via `CachedNetworkImage`, both
  `SizedBox.shrink()` when unset), and uses `hexToColor(primaryColorHex) ?? AppColors.cargoNavy` for
  the selected-category chip color instead of the hardcoded Cargo Navy — the only three places a
  buyer-facing screen reads store branding today.

**Not started (per `SELLORA_IMPLEMENTATION_PLAN.md` PHASE 6 scope):** theme/section/block/setting
models, a renderer, preview, or publish flow — this is branding-field editing only, not a page
builder. `primaryColorHex` also isn't threaded any further than the one storefront chip row above;
e.g. seller-shell chrome, buttons, and other storefront widgets still hardcode Cargo Navy.

**Not verified live in a browser this session** — picking this up cold from a `/clear`; the change is
small and symmetric with the existing `ManageVariants`/profile screens pattern, but should get an
actual click-through next time this area is touched, per this file's own recurring reminder about
trusting analyzer-clean over browser-verified.

**Next step:** decide whether to keep deepening PHASE 6 (sections/blocks/theme picker) or move to a
different phase — nothing forces the order.

---

## 2026-09-18 — PHASE 5: variants management UI

**Status:** implemented and verified this session (`flutter analyze` clean — same 3 pre-existing
baseline issues as before this session's changes; `flutter test` same 10/12 pass rate; live-verified
in a browser for the seller-side flow). User explicitly picked this slice out of PHASE 5's remaining
list (variants UI, collections, real inventory, SEO fields, bulk ops, pagination, server-authorized
writes) — the rest are still not started, same as the prior entry left them.

**Scope decision:** `ProductVariant` was import-time-only (set once from CJ, never editable after).
Scoped this pass to what's safe to edit without reaching into checkout pricing or the still-unstarted
"real inventory tracking" phase item: a per-variant **enable/disable** switch (which SKUs a buyer can
pick) and a seller-facing **SKU** override. Deliberately did *not* add per-variant price overrides
(would require rewiring `CartItemModel.lineTotal` and the server-side `createOrder` re-pricing logic —
checkout-pricing-engine work, not "management UI") or per-variant stock (that's what PHASE 5's own
"real inventory tracking" item is for — adding a half-version of it here would preempt and conflict
with that session). CJ's own attributes/price/costPrice/image stay read-only — supplier-of-record
facts, not the seller's to edit.

**Changed:**
- **`ProductVariant`** gained `enabled` (bool, defaults `true`) and a `copyWith`; threaded through
  `fromMap`/`toMap`. **`ProductModel.copyWith`** gained a `variants` param (previously impossible to
  update the variant list at all after construction) and a new `visibleVariants` getter — enabled
  variants, falling back to the full list if a seller has disabled every one, so a listing can never
  end up with zero pickable SKUs.
- **New `lib/modules/seller/manage_variants/`** (`ManageVariantsController` + `ManageVariantsView`):
  takes a `ProductModel` via `Get.arguments`, edits a local copy of its variants (toggle
  enabled/disabled, edit SKU), and saves via the existing `ProductRepository.updateListing` — no
  repository or Firestore-rules changes needed, since `updateListing` already writes the whole
  product document. New route `Routes.sellerManageVariants` (`/seller/variants`), bound in
  `ManageVariantsBinding` (added to `seller_binding.dart`), registered in `app_pages.dart` behind the
  same `RoleMiddleware(UserRole.seller)` every other seller route uses.
- **`MyListingsView`**: each listing tile is now an `InkWell` that opens Manage Variants for that
  product (`Get.toNamed(Routes.sellerManageVariants, arguments: product)`); listings with more than
  one variant show a "N variants · tap to manage" hint. The switch keeps its own tap target, so
  toggling listed/unlisted still works independently of the new navigation.
- **Buyer-facing filter**: `ProductDetailsController`/`ProductDetailsView` now read
  `product.visibleVariants` instead of `product.variants` for both the initial variant selection and
  the picker chip row — a disabled variant simply stops being offered to buyers, without deleting it
  or touching the CJ `vid` fulfillment needs.

**Verified live in a browser this session**: `flutter run -d web-server`, driven by a
`playwright-core` script against headless system Chrome (no bundled browser download). Getting a
screenshot out of headless Chrome required `--enable-unsafe-swiftshader` in addition to
`--use-gl=swiftshader`/`--use-angle=swiftshader-webgl` — without it CanvasKit's WebGL2 context never
attaches (`flt-glass-pane` never appears in the DOM) and every screenshot comes back blank white; this
is a headless-Chrome/CanvasKit environment quirk, not an app bug, and is worth remembering for the
next session that needs to drive this app. Signed in as the seller quick-login shortcut
(`seller@test.com`), opened My Listings (3 seeded listings, "Wireless Earbuds" showing its "2 variants
· tap to manage" hint), tapped into it, disabled the "White" SKU, changed its SKU field to
`EARBUD-WHITE-01`, and saved — got the "Variants updated" snackbar and landed back on My Listings with
the listing intact. Zero console errors across every step of the seller-side flow.

**Not verified live:** the buyer-facing consequence (that a disabled variant disappears from the
storefront's variant picker). Jumping to `/s/aminas-picks` in the same page session (needed since the
mock repository is in-memory and per-app-instance, not per-login) reliably hit the same
software-rendering flakiness described above — sometimes a partial render, twice a full blank frame
even after polling for `flt-glass-pane` and waiting several more seconds — and repeating it further
felt like chasing headless-Chrome flakiness rather than the app. The code path itself is small,
symmetric with the already-verified seller-side change, and analyzer-clean:
`ProductDetailsController.onInit`/`selectVariant` and the picker in `product_details_view.dart` both
now read `product.visibleVariants`, the same getter exercised indirectly by
`ManageVariantsController.save()` writing `enabled: false` for the White SKU. Worth a real
browser click-through next time this screen is touched, rather than assumed safe indefinitely.

**Next step:** PHASE 5 still has collections, real inventory tracking, SEO fields, bulk
select/edit/delete, pagination on the unbounded list reads, and server-authorized writes — each needs
its own scoping pass, same as this one.

---

## 2026-09-18 — PHASE 5: `stores/{storeId}/products` write-path migration

**Status:** implemented and verified this session (`flutter analyze` clean — same 3 of the 4
pre-existing baseline issues, confirmed via `git stash` A/B check; `flutter test` same 10/12 pass
rate, confirmed the same way; live-verified in a browser). Closes the blocker
`SELLORA_IMPLEMENTATION_PLAN.md`/`TODO.md` named for PHASE 5: `listProduct`/`updateListing`/
`unlistProduct` wrote flat `listings` while `stores/{storeId}/products` sat rules-ready but always
empty, since nothing wrote to it. User explicitly scoped this session to *just* the write-path
migration — variants management, collections, inventory, SEO, and bulk operations (the rest of
PHASE 5's TODO.md scope) are still not started.

**Found while investigating:** `firestore.rules` already allowed seller-owned create/update on
`stores/{storeId}/products` (lines 101-105) — the "read-only" framing in the prior docs described
the missing application code, not a rules gap. No rules changes were needed for this migration.

**Changed:**
- **`ProductModel`** gained a `storeId` field (nullable — null while sitting in the shared CJ
  catalog, same as `sellerId`), threaded through `copyWith`/`fromMap`/`toMap`.
- **`ProductRepository`**: `listProduct` gained a required `storeId` param; `unlistProduct` now
  takes `(storeId, productId)` instead of just `productId` — both needed to address the new
  subcollection path. `updateListing(ProductModel product)` keeps its old signature since the
  product now carries its own `storeId`.
- **`FirebaseProductRepository`**: `listProduct`/`updateListing`/`unlistProduct` now write
  `stores/{storeId}/products` instead of flat `listings`, using `catalogProduct.id` as the doc id
  directly — the old `${sellerId}_${catalogProduct.id}` cross-seller collision-avoidance key
  (flagged as a wart in every PHASE 4 entry back to 2026-09-14) is no longer needed once each
  seller's products live in their own subcollection. `sellerListings`/`storefrontFeed`/
  `productDetail` were **also** repointed off flat `listings` onto a new `FirestoreService
  .productsGroup` (`collectionGroup('products')`) query — without this, those three reads would've
  kept hitting a collection nothing writes to anymore the moment `useMockData` flips off, which
  would make this a half-migration, not a real one. `storeProducts()` (the customer storefront's
  read path) was already correct and untouched. The flat `listings` getter on `FirestoreService`
  is now dead and removed; `firestore.rules`' `listings` block was deliberately left alone (a rules
  change wasn't required, and removing it is a separate security-pass decision, not bundled here).
- **`firestore.indexes.json`**: added `COLLECTION_GROUP`-scoped field overrides for `products.sellerId`
  /`.id`/`.isListed`, plus a composite `isListed`+`category` index mirroring the existing flat-
  `listings` one — needed for the three collection-group queries above. Unverified against a real
  Firebase project, same caveat as every other backend-shape change in this repo.
- **`MyListingsController.unlist`**: now looks up the listing's own `storeId` before calling
  `unlistProduct` (mirrors `relist`'s existing find-by-id pattern) — no view changes needed.
- **`ProductImportController.import`**: now reads `storeId` from `StoreScope.current.value?.id`
  (already resolved by the seller shell before this screen is reachable) and passes it to
  `listProduct`; bails out (returns `false`) if it's somehow null, same as the existing user/product
  null-guards.
- **`MockProductRepository`**: mirrors the interface change — seeds the two known demo listings with
  their real `store-aminas`/`store-jengo` ids, and its "seed a starter storefront for any other
  seller" fallback now resolves a real storeId via `StoreRepository.storesForSeller` instead of
  leaving it null.
- **`test/mock_subscription_repository_test.dart`**'s fake `ProductRepository` updated to match the
  new signatures.

**Verified live in a browser this session** (same Playwright-driven headless-Chrome approach as
prior sessions — CanvasKit has no queryable DOM, so coordinate clicks + screenshots): signed in as
the seller quick-login shortcut, imported "Wireless Earbuds" (Black, $34.99, publish) — it appeared
in My Listings immediately without leaving the seller shell, exactly as before. Toggled an existing
seeded listing off then on (unlist/relist) — both worked, switch state updated correctly. Opened
`/s/aminas-picks` and confirmed all 3 seeded products still render on the storefront. Zero console
errors across every step tied to this change.

**Found in passing, unrelated to this migration, not fixed:** the storefront's category-chip row
(`storefront_view.dart:86`) trips a "GetX improper use" debug warning — reads an `Obx`-watched value
inside a lazy `ListView.separated` `itemBuilder` rather than in the `Obx`'s synchronous build scope.
Pre-existing (confirmed the file isn't among this session's changes); left alone since it's out of
scope for a product write-path migration.

**Next step:** PHASE 5's write-path blocker is closed. What's left of PHASE 5 per TODO.md §10 —
variants management UI, collections, real inventory tracking beyond the flat `stock` int, SEO
fields, bulk select/edit/delete — is all still open and needs its own scoping pass, same as this
session's.

---

## 2026-09-18 — PHASE 4: category browsing, shipping-cost estimate, buyer variant selector

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing
`info`/`error` issues confirmed present before this session's changes too via a `git stash` A/B
check; `flutter test` same 8/10 pass rate as the pre-existing baseline, confirmed the same way; live-
verified in a browser). Closes the three items the 2026-09-15 and 2026-09-14 entries left explicitly
out of scope: category browsing, a shipping-cost estimate UI, and a buyer-facing variant selector.
All three are additive client-side work — `getCategories`/`calculateFreight` already existed
correctly in `functions/index.js` and `ApiEndpoints`, just with no client consumer yet.

**Changed:**
- **New `lib/data/models/cj_category.dart`**: `CjCategory {id, name}` with
  `topLevelFromRawTree()`, parsing CJ's raw nested category tree (id/name found by key-suffix
  matching, e.g. `categoryFirstId`/`categoryFirstName`) into level-0 nodes only — mirrors
  `functions/lib/catalogSync.js`'s `normalizeCategoryNode`, scoped to a filter chip row rather than a
  3-level drill-down browser.
- **New `lib/data/models/freight_estimate.dart`**: `FreightEstimate {cost, logisticName, currency}`.
  Only `logisticPrice`/`logisticName` are contract-confirmed anywhere in this repo (via
  `functions/lib/orders.js`'s existing consumption of the same CJ call) — no delivery-time field is
  invented.
- **`lib/data/services/cj_dropshipping_service.dart`**: added `getCategories()` (GETs
  `ApiEndpoints.getCategories`, parses via `CjCategory.topLevelFromRawTree`) and `calculateFreight()`
  (POSTs `ApiEndpoints.calculateFreight`, picks the cheapest option by `logisticPrice` exactly the way
  `orders.js` already does server-side at checkout).
- **`ProductRepository`** (+ both implementations, + the test fake in
  `test/mock_subscription_repository_test.dart`): gained `categories()` and `estimateShipping({vid,
  quantity, endCountryCode = 'KE'})`. `FirebaseProductRepository` delegates to the new service
  methods; `MockProductRepository` synthesizes a category list from the distinct `category` names
  already in `MockSeedData.catalog()` and a deterministic per-vid fake freight estimate (~$2.50–$12,
  keyed off `vid.hashCode`) — kept genuinely useful rather than empty stubs, per this repo's "every
  screen fully clickable under `useMockData = true`" rule.
- **`lib/modules/seller/catalog/`**: the catalog browse screen gained a category filter chip row
  (`ChoiceChip`s, toggle-off on repeat tap) above the search field, wired to `browseCatalog`'s
  existing (previously unused) `category` param.
- **`lib/modules/seller/product_import/`**: the Smart Pricing card gained an "Est. shipping to Kenya"
  line and a "Landed cost" (CJ cost + shipping) subtotal; the quick-margin presets and the live
  profit/margin readout now price off landed cost instead of bare CJ cost, matching `TODO.md`'s
  original "CJ cost + Shipping + margin = recommended price" spec. Fetches on initial variant
  selection and every later variant switch (`ProductImportController.selectVariant`). Deliberately
  does **not** touch `ProductModel.costPrice`/`marginPercent` — those stay CJ-cost-only for the
  dashboard and other screens; the landed-cost basis is local to this screen's own calculation.
- **`lib/modules/buyer/product_details/`**: added a variant chip picker ("Choose an option",
  label-only, no price — the buyer always pays `ProductModel.sellPrice` regardless of variant) and
  image-swap state (`previewImage`, this screen had none before). No changes needed to
  `addToCart`/`CartRepository`/`CheckoutController` — the vid/label plumbing through to `OrderItem`
  was already wired from the 2026-09-15 variant-id work; only the picker UI and the `selectVariant()`
  method were missing.

**Verified live in a browser this session**: `flutter run -d web-server` driven by a headless system
Chrome via a small Playwright (`playwright-core`, no bundled browser download) script — same
CanvasKit-has-no-queryable-DOM constraint as the 2026-09-15 session, so coordinate clicks + screenshots
again, not role/label locators. Signed in as the seller quick-login shortcut, opened the CJ catalog:
category chips (Electronics/Fashion/Home) rendered and filtering worked both ways (Home → coffee set +
storage bags; Electronics → earbuds/ring light/laptop stand). Opened the Wireless Earbuds import screen
(2 variants): Black showed CJ cost $14.20 + shipping $3.18 = landed cost $17.38, profit/margin computed
correctly off that ($17.61/101% at the pre-filled $34.99); switching to White updated CJ cost to $15.10
and shipping to a *different* estimate ($11.84, confirming the per-vid mock estimate actually varies),
landed cost/profit/margin recomputed correctly (26.94 / $8.05 / 30%). Then signed in as a buyer at
`/s/aminas-picks/login` and opened the same product from the storefront: a Black/White chip row
appeared, price stayed fixed at $34.99 across both, switching to White swapped the hero image to the
variant's own photo, and "Add to cart" worked (cart badge went 0→1). Zero console errors across every
step.

**Deliberately not done (per the approved plan, out of scope):** category browsing stays level-0 chips
only, not a 3-level drill-down; no buyer-facing shipping estimate (buyer checkout already prices real
freight server-side via `createOrder`); no backend/`functions/` changes (both endpoints already
existed); no title/description/SEO/collections work.

**Caveat, unchanged from the 2026-09-14 entry:** CJ field names beyond `logisticPrice`/`logisticName`
and the id/name key-suffix convention are still unverified against a live CJ account — only backend
tests and `orders.js`'s existing server-side consumption confirm them.

**Next step:** Phase 4's three explicitly-tracked gaps are now closed. What's left of Phase 4 per
`SELLORA_IMPLEMENTATION_PLAN.md` is reconciling how a shared CJ catalog maps onto per-seller `listings`
at scale (still `${sellerId}_${catalogProduct.id}` doc ids) — unchanged from prior entries, not touched
here. Phase 5 (seller product management) remains the natural next phase.

---

## 2026-09-15 — PHASE 4: seller product-import screen (variant picker + smart pricing)

**Status:** implemented and verified this session (`flutter analyze` clean — same 3 pre-existing
`info` lints, `flutter test` 13/13, live-verified in a browser).

Picked up PHASE 4's last-named gap (2026-09-14 entry below, `SELLORA_IMPLEMENTATION_PLAN.md`): the
catalog-browsing plumbing was reconciled with the real backend, but no screen actually used it beyond
a flat-price bottom sheet with a single price field — no variant UI, no images beyond the summary
thumbnail. Asked the user to scope Phase 4's remaining surface (search polish only / full import
experience / full import + categories+shipping); chose "full import experience": a real product-detail
screen plus a margin-based smart-pricing calculator and draft/publish. Explicitly out of scope:
title/description/tags/collections/SEO editing and category browsing/shipping-estimate UI — those need
concepts (collections, SEO slugs) that don't exist anywhere in the app yet.

**Changed:**
- **New `lib/modules/seller/product_import/`** (`product_import_controller.dart`,
  `product_import_view.dart`): replaces the old catalog bottom sheet. `ProductImportController`
  re-fetches the full CJ detail via the existing `ProductRepository.productDetail` (search results are
  summary-only — no description/variants at all, confirmed against `functions/lib/cjApi.js`'s
  `searchProducts`), tracks the selected `ProductVariant`, and prices against that variant's own CJ cost
  (sizes/colors of the same product routinely cost different amounts) rather than always the first one.
  The view shows a real image gallery (main image + thumbnails, swapping to a variant's own photo when
  one is picked), a variant chip picker (only rendered when there's more than one SKU), and a "Smart
  pricing" card: cost price, four quick-margin chips (+20/30/50/100%) that set the price field, and a
  live profit/margin readout recomputed from cost + whatever's in the price field — editable directly,
  not locked to a preset. "Save as draft" / "Publish to store" both call the same `import()`, differing
  only in the `isListed` flag passed through.
- **`lib/data/repositories/product_repository.dart`** (+ both implementations, + the test fake in
  `test/mock_subscription_repository_test.dart`): `listProduct` gained `bool isListed = true` — the
  "save as draft" half of the import workflow needed a way to list unpublished, matching the same
  unpublished state `unlistProduct` already leaves an existing listing in.
- **`lib/modules/seller/catalog/seller_catalog_controller.dart`/`seller_catalog_view.dart`**: the
  controller's `listProduct`/`isListing` (the old bottom-sheet's logic) and the view's
  `_ListProductSheet` are gone — tapping a catalog tile now pushes the new import screen
  (`Get.toNamed(Routes.sellerProductImport, arguments: product)`) instead of opening a sheet with one
  price field.
- **`lib/app/routes/app_routes.dart`**: renamed the long-dead, never-registered `sellerAddListing`
  constant to `sellerProductImport` (`/seller/import`) and actually registered it —
  `lib/app/routes/app_pages.dart` gained the `GetPage` (seller-role-gated, matching every other seller
  route), `lib/modules/seller/seller_binding.dart` gained `ProductImportBinding`.
- **`lib/data/mock/mock_seed_data.dart`**: gave the earbuds (`p1`) and watch (`p2`) mock catalog
  products real sample `ProductVariant`s (distinct per-SKU cost/price, one with its own image) — every
  mock product had zero variants before this, so the variant picker had nothing to demonstrate in demo
  mode. Also fixed three broken Unsplash photo ids that 404'd (`p1`'s intended second image, `p2`'s new
  White-variant image, and `p4`'s long-standing `imageUrl` — the last one predates this session and was
  simply never noticed before, since nothing rendered a coffee-set image next to a working one to
  compare against).

**Bug found and fixed along the way, unrelated to the plumbing above:** `MyListingsController`/
`SellerDashboardController` only call their own `load()` from `onInit()`, but `SellerShellView` builds
all five tabs into one `IndexedStack` up front (see `AdaptiveShellScaffold`) — so both controllers are
created and loaded exactly once, immediately after login, and never again. Importing a product and
switching to "My listings" or "Dashboard" showed stale pre-import data (verified live: a fresh import
didn't appear, and "Active listings" didn't increment) until the whole seller shell was torn down and
rebuilt. Fixed by having `ProductImportController.import()` call `.load()` on both controllers (guarded
by `Get.isRegistered`) right after a successful write — the same self-refresh pattern
`MyListingsController.unlist`/`relist` already use on themselves, just triggered from the sibling screen
that actually changed the data.

**Deliberately not done (out of this pass's confirmed scope):** title/description/SKU/tags editing,
collection assignment, SEO fields — no "collection" or SEO-slug concept exists anywhere in the app yet,
so this would be new modeling, not wiring; category browsing and a shipping-cost estimate
(`getCategories`/`calculateFreight` stay unconsumed `ApiEndpoints`, same as the 2026-09-14 entry left
them — no category-browsing or shipping-estimate UI exists to call them from); a buyer-facing variant
selector (the buyer product-detail page still auto-picks `variants.first`, unchanged from the same-day
vid-wiring entry).

**Verified live in a browser this session**: `flutter run -d web-server` driven by a headless Chrome via
Playwright (system Chrome — Playwright's own browser download has no path to its CDN from this sandbox;
navigated with `networkidle` + coordinate clicks, since Flutter's CanvasKit renderer exposes no DOM for
label/role-based queries, and a `--disable-gpu`/software-rendering launch-flag combination crashed the
page outright, so the plain no-extra-flags recipe was kept). Signed in as the seller quick-login
shortcut and imported the earbuds product: switched Black→White and watched the cost price and gallery
image update reactively without touching the price field, tapped "+30%" and confirmed the price field
became exactly `cost × 1.3`, typed a manual override and watched profit/margin recompute live, then
saved as a draft. Separately published the watch product and confirmed — in the same session, without
navigating away — that "Active listings" on the dashboard went 3→4 and the new row appeared in My
listings switched on, both immediately (the refresh bug above, caught by this exact check). Confirmed a
product with 0/1 variants (Ceramic Pour-Over Coffee Set) skips the variant-picker section entirely
rather than rendering an empty one, and that its draft-saved row shows the toggle off, distinct from the
three active rows. Zero console/page errors across every step.

**Next step:** PHASE 4's app-facing surface now has a real import workflow; what's left of the phase
(per `SELLORA_IMPLEMENTATION_PLAN.md`) is category browsing, a shipping-cost estimate, and reconciling
how a shared CJ catalog maps onto per-seller `listings` at scale (still just
`${sellerId}_${catalogProduct.id}` doc ids) — none of that was in this session's scope. PHASE 5 (seller
product management — editing an existing listing's title/price/variants after import) is the natural
next consumer of this same screen's pricing card.

---

## 2026-09-15 — Fixed buyer-home GetX crash (category chips)

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing
`info` lints, `flutter test` 13/13).

Picked up the loose thread named at the end of the same-day checkout entry below: a fresh buyer
session showed a "[Get] the improper use of a GetX has been detected" red error banner over the
product grid. Reproduced it live (`flutter run -d web-server`, driven by a headless Chrome via
Playwright — pointed at the system-installed Chrome directly, since `npx playwright install`
couldn't reach its CDN from this sandbox) and captured the real stack trace rather than guessing:
the error-causing widget was `Obx` at `buyer_home_view.dart:53`, the category-chips row.

**Root cause:** that `Obx` wraps a `ListView.separated`. `ListView`'s `itemBuilder` is invoked
lazily during layout, *after* the wrapping `Obx`'s own synchronous `build()` has already returned —
so the only reactive read in there (`controller.selectedCategory.value`, used to highlight the
selected chip) never happens inside the Obx's own build scope. GetX's `Obx` throws this specific
error when its first build registers zero observable dependencies, which is exactly what happened:
`controller.categories` is a plain `const List`, not `.obs`, so nothing else in the builder read a
reactive value either. Beyond the crash, this was a real (if less visible) reactivity bug too:
since the dependency was never registered, tapping a category chip would never have re-highlighted
the selection, even if the crash weren't there.

**Changed:**
- **`lib/modules/buyer/home/buyer_home_view.dart`**: the category-chips `Obx`'s builder now reads
  `controller.selectedCategory.value` once at the top of its own scope (before constructing the
  `ListView.separated`), and the `itemBuilder` closes over that captured value instead of
  re-reading `.value` itself. Registers the dependency where GetX can actually see it, fixing both
  the crash and the dead reactivity in one change — no other file touched.

**Verified live in a browser this session**: registered a fresh buyer at `/s/aminas-picks/register`
(mock mode) and landed on buyer home — no error banner, "All" chip highlighted navy by default.
Clicked "Electronics" — chip highlight correctly moved and the grid filtered to the 2 electronics
listings, confirming the reactivity now actually works, not just that the crash is gone.

**Next step:** the two PHASE 4/8 threads named in the entry below are both still open (the seller
variant-picker screen, and the order-model architectural fork). Neither was in this session's scope.

---

## 2026-09-15 — Checkout: real `shippingAddress` shape + `createOrder` response parsing

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing `info`
lints, `flutter test` 13/13, `flutter build web` succeeds).

Picked up the two items named at the end of the same-day variant-id entry below. Asked the user how to
scope this first, since reading `functions/lib/orders.js` showed the response-parsing half isn't purely
mechanical: the adopted backend has no seller/store/fee concept at all, while `OrderModel` is built
around Sellora's marketplace fee-split (`sellerId`, `storeId`, `serviceFeeRate`, `sellerRevenue`,
`code`). Fixing that "for real" is either a client-side decision to treat those fields as unused/zeroed
bookkeeping (this session's scope), or a bigger change to add seller/store/2% fee support to the backend
itself (named as its own, separate option; not started). User chose the client-only fix.

**Changed:**
- **`lib/data/models/order_model.dart`**: new `ShippingAddress` class (`{countryCode, line}`,
  `fromMap`/`toMap`) — `countryCode` is the only field `createOrder` validates (it derives
  region/currency from it via `functions/lib/regions.js`); `line` is the same free-text address the UI
  collected before. `OrderModel.shippingAddress` is now `ShippingAddress` (was `String`). `copyWith`
  gained a `currency` override — needed because the server derives currency from the shipping address
  and can disagree with the client's draft guess.
- **`lib/data/repositories/firebase_order_repository.dart`**: `placeOrder` now sends
  `order.shippingAddress.toMap()`, and its response parsing reads the real shape
  (`id`/`totalAmount`/`currency`) instead of the nonexistent `orderId`/`code`/`serviceFeeAmount`. There's
  no human-readable order code in this backend, so the order id doubles as `code`. Deliberately keeps
  the client-built `items` list rather than the response's own (which lacks `imageUrl`/`variantLabel`) —
  only the fields the server actually recomputed are trusted from it.
- **`lib/modules/buyer/checkout/checkout_controller.dart`**: `placeOrder` takes a new `countryCode`
  param and builds a `ShippingAddress` from it + the existing address text, used in both the mock- and
  real-mode order construction.
- **`lib/modules/buyer/checkout/checkout_view.dart`**: added a country dropdown above the address field
  (Kenya first, plus US/GB/DE/FR — the countries `functions/lib/regions.js` names its own pricing region
  for; any other country still works, falling back to us/USD region pricing). Wired into `placeOrder`.
- **`lib/core/constants/app_constants.dart`**: `createOrder`'s doc comment updated — both gaps closed;
  documents the one still open (see below).

**Deliberately not done (out of this pass's confirmed scope):**
- No richer CJ-fulfillment address (`fullName`/`phone`/`email`/`line1`/`line2`/`city`/`province`/`zip` —
  what `functions/lib/cjApi.js` actually needs to push a fulfillment to CJ later). `shippingAddress.line`
  stays one free-text field, same shape the UI already collected; only `countryCode` was added.
- No backend change. `sellerId`/`storeId`/`serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue`/
  `paymentFee` on `OrderModel` stay client-side-only bookkeeping the real order doc in Firestore has no
  matching fields for — the 2% platform fee is not actually computed or collected by this backend for
  any order. That's the "add seller/store/fee support to createOrder" option the user didn't pick this
  session.

**Verified live in a browser this session** (not just analyze/test/build): ran `flutter run -d web-server`
and drove it with a headless Chrome via Playwright — signed up a seller, subscribed, signed in as a
buyer at that store's `/s/{slug}/login`, added a seeded product to cart, and placed an order through the
new checkout form. Confirmed the Country dropdown renders (Kenya default, plus US/GB/DE/FR), the order
summary/total render correctly, and submitting produces the "Order placed" snackbar with the order
showing up on the buyer's Orders tab — the mock-mode path works end to end with the new shape.

**Bug found and fixed along the way, unrelated to this change:** `StorefrontLoginView`/
`StorefrontRegisterView` called `_scope.resolveSlug(slug)` synchronously from `initState()`, which flips
`StoreScope.isResolving` (an Rx an `Obx` in the same build depends on) while the widget is still
mid-build — Flutter throws "setState()/markNeedsBuild() called during build" and the page is stuck on
its loading spinner forever. This was a full block on **any** buyer ever signing in or registering at a
storefront, confirmed via a browser console `pageerror`, and would have blocked this session's own live
verification. Fixed in both files by deferring the call with
`WidgetsBinding.instance.addPostFrameCallback`, the standard fix for this class of GetX/Flutter bug —
confirmed fixed by rerunning the same browser flow (the spinner now resolves to the real sign-in form).

**Second, separate bug surfaced but NOT fixed (out of this session's confirmed scope):** the buyer home
screen (`BuyerHomeController`/its view) throws "[Get] the improper use of a GetX has been detected" as a
visible red error banner over the product grid for a freshly-created store's buyer session — the
underlying product data still renders correctly beneath it, and it didn't block navigating to product
details/cart/checkout, so it was left alone rather than pulled into this pass's scope. Worth a dedicated
look next time someone is in `lib/modules/buyer/home/`.

**Next step:** PHASE 8 checkout is no longer blocked on any *named* mechanical gap — what's left is the
real architectural fork flagged above (extend the adopted single-vendor backend with seller/store/2% fee
support, or accept single-vendor and rethink what `OrderModel`'s marketplace fields mean) and the CJ
fulfillment-address shape. For PHASE 4, the seller still has no screen to pick a specific variant before
importing (unchanged from the entry below). The buyer-home GetX error banner above is a loose thread
worth picking up too.

---

## 2026-09-15 — ProductVariant carries CJ's real per-SKU `vid`; threaded through cart/checkout

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing `info`
lints, `flutter test` 13/13, `flutter build web` succeeds).

Picked up the concrete next step named at the end of the 2026-09-14 entry below: `ProductVariant` was
only `{name, options}` attribute strings, so no real CJ purchasable-SKU id (`vid`) existed anywhere
client-side — the confirmed blocker for both PHASE 4's import screen and PHASE 8's checkout (`createOrder`
requires `{pid, vid, quantity}` per line). Asked the user how to scope this before touching code, given
three genuinely different-sized options (model+wiring only, model+wiring+seller variant-picker screen,
model+wiring+buyer variant-picker screen). User chose the narrowest: model + wiring only, no new UI.

Confirmed the exact real shape against `functions/lib/cjApi.js`'s `getProductDetail` (per variant:
`{vid, sku, key, attributes, image, supplierPriceUsd, retailPriceUsd, weight}` — no per-variant stock;
CJ stock is a separate internal-only lookup used by `catalogSync.js`, not exposed to the client) and
`functions/lib/orders.js`'s `createOrder`/`validateOrderRequest` (every item requires a non-empty
string `vid`, or the request is rejected outright).

Also confirmed neither `product_details_view.dart` nor `seller_catalog_view.dart` ever actually
rendered variant data (the old `selectedVariant` just silently auto-picked "first option" with no
picker UI) — so this really was a pure model/wiring change with zero UI to update, matching the chosen
scope exactly.

**Changed:**
- **`lib/data/models/product_model.dart`**: `ProductVariant` redesigned from `{name, options}` (an
  attribute-picker dimension) to one purchasable SKU: `{vid, sku, attributes: Map<String,String>, price,
  costPrice, image}`, with `label` (e.g. "Black / M"), `fromMap`/`toMap`. `ProductModel.toMap`/`fromMap`
  now round-trip `variants` (previously dropped entirely — a real CJ `vid` would have been lost the
  moment a seller's `listings` doc was written/read back).
- **`lib/data/services/cj_dropshipping_service.dart`**: `_detailToProduct` now maps CJ's real per-SKU
  variant list straight onto `ProductVariant` (`_mapVariants`, replacing the old `_variantOptions` that
  collapsed the list into distinct attribute values and threw the per-SKU `vid` away).
- **`lib/data/models/cart_item_model.dart`**: `selectedVariant` is now `ProductVariant?` (was `String?`).
  Line pricing deliberately still comes from `product.sellPrice` (the seller's own listing price), not
  the variant's CJ price — no pricing-model change was in scope here.
- **`lib/data/repositories/cart_repository.dart`**: `add()` takes `ProductVariant?`; the
  same-product-different-variant cart-line check now compares by `vid` instead of object/string equality.
- **`lib/modules/buyer/product_details/product_details_controller.dart`**: `selectedVariant` is now
  `Rxn<ProductVariant>`, auto-picking `product.variants.first` (unchanged behavior, now the whole variant
  rather than one attribute string).
- **`lib/data/models/order_model.dart`**: `OrderItem` gained `cjProductId` (CJ's `pid`) and split the old
  `variant` string into `variantId` (CJ's `vid`) + `variantLabel` (display). Confirmed zero UI ever read
  `OrderItem.variant` before renaming it.
- **`lib/modules/buyer/checkout/checkout_controller.dart`**: `OrderItem` construction now passes
  `cjProductId`/`variantId`/`variantLabel` from the cart line's product/variant.
- **`lib/data/repositories/firebase_order_repository.dart`**: `placeOrder`'s `createOrder` request now
  sends `{pid, vid, quantity}` per item (previously `{productId, quantity, variant}`, which matched
  neither the adopted backend nor any prior one).
- **`lib/core/constants/app_constants.dart`**: `createOrder`'s doc comment updated — the `vid` gap is
  closed; documents precisely what's still unreconciled (see below).

**Deliberately not done (out of this pass's confirmed scope):**
- No seller-facing variant-picker/import-detail screen and no buyer-facing variant-selector UI — the
  user explicitly chose model+wiring only. A seller importing a multi-variant product still lists it at
  one flat price with whatever `variants` the CJ detail call returned; a buyer's product-detail page still
  silently defaults to the first variant, same as before.
- `FirebaseOrderRepository.placeOrder`'s two other known-broken parts, deliberately left alone rather
  than half-fixed: (1) `shippingAddress` is still a free-text string; `createOrder` requires
  `{countryCode, ...}`, and `CheckoutController` has no UI to collect anything more than a string
  address. (2) The response parsing (`res['orderId']`/`res['code']`/`res['serviceFeeAmount']`) still
  assumes fields the adopted single-vendor backend's `createOrder` doesn't return at all (real shape:
  `{id, totalAmount, currency, items, ...}`, no seller/store/fee concept). Fixing either is a real
  reconciliation of two different checkout models (marketplace-with-fee-split vs. single-vendor), the
  same "reconciling the two backends" work flagged as its own step since the 2026-09-12 backend-adoption
  entry — not a mechanical fix alongside the variant-id wiring.
- `CartItemModel`/checkout pricing still ignores the variant's own CJ `price`/`costPrice` — intentional;
  `sellPrice` is the seller's single chosen price for the whole listing, and changing that would be a
  pricing-model decision, not wiring.

**Next step:** the per-SKU variant id gap is closed at the model layer. What's left for PHASE 8 checkout
to actually work end-to-end against the real backend is exactly the two items above (shippingAddress
shape, response parsing) — both already scoped out here, not newly discovered. For PHASE 4, the seller
still has no screen to actually see/pick a specific variant before importing; today's flat-price import
just carries whichever variants CJ returned along for the ride.

---

## 2026-09-14 — IntasendService reconciled with the adopted backend; deeper checkout blocker confirmed

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing `info`
lints as every prior entry, `flutter test` 13/13, `flutter build web` succeeds).

Picked up from the same day's catalog-plumbing entry below, which flagged `IntasendService`'s three
order-checkout endpoints as "the same class of bug" as the catalog mismatch it had just fixed. Asked the
user how to scope this before touching code, since a first pass at reading the real `payOrderMpesa`/
`payOrderCard`/`confirmIntasendPayment`/`createOrder` contracts (`functions/index.js`,
`functions/lib/orders.js`) showed it isn't actually the same class of bug: the adopted backend's
checkout has no seller/store/fee concept at all, and `createOrder` requires CJ's own `pid`/`vid` per
line item — a purchasable per-SKU id that doesn't exist anywhere client-side (`ProductVariant` is only
`{name, options}` attribute strings, confirmed in the same-day catalog entry). Fixing
`FirebaseOrderRepository.placeOrder` for real is therefore blocked on the same variant-id gap as PHASE
4's import/variant-picker screen — not a same-day fix. User chose the narrow option: fix
`IntasendService` itself (mechanical, self-contained) and explicitly leave `placeOrder`/
`CheckoutController` documented as still broken, rather than either stopping entirely or wiring a
placeholder `vid` through checkout just to make it "run."

**Changed:**
- **`lib/core/constants/app_constants.dart`**: replaced `intasendCollectMpesa`/`intasendCheckout`/
  `intasendStatus` with the real `payOrderMpesa`/`payOrderCard`/`confirmIntasendPayment` endpoint
  constants; expanded the `createOrder` doc comment with the specific `pid`/`vid` blocker found this
  session (previously it only said "old shape," not why that shape can't just be swapped in).
- **`lib/data/services/intasend_service.dart`**: rewritten. `collectMpesa`/`createCheckout`/
  `checkStatus` (client-computed amount, generic "reference") replaced with `payOrderMpesa(orderId,
  phoneNumber)` / `payOrderCard(orderId, method, redirectUrl)` / `confirmOrderPayment(orderId)` —
  matching the real contract, where the server derives the amount from an order it already created and
  every call keys off that order's id, not a client-supplied figure. `checkStatus` was a GET; the real
  endpoint (`confirmIntasendPayment`) is a POST that also fulfills the order server-side when complete,
  so the new `confirmOrderPayment` reflects that too. Removed the now-fully-unused `PaymentResult` class
  (only ever constructed by the two rewritten methods).
- **`lib/modules/buyer/checkout/checkout_controller.dart`**: updated its one call site
  (`collectMpesa(phone:, amountKes:, narrative:)` → `payOrderMpesa(orderId:, phoneNumber:)`) so the
  project keeps compiling, and expanded the surrounding comment to say plainly that this whole branch is
  unreachable today (`useMockData` is always true) and would still fail if it ran, because `placeOrder`
  above it sends the old request shape and has no real CJ `vid` to send. The `payOrderMpesa` call itself
  is now correct; what it would be called with isn't, yet.

**Deliberately not done (out of this pass's confirmed scope):** `FirebaseOrderRepository.placeOrder`'s
request/response shape and `createOrder`'s missing seller/store/fee concept — reconciling either for
real needs a variant-id-carrying product model first (PHASE 4's still-unstarted import/variant-picker
screen), not a client-side endpoint fix. `createCheckout`/`payOrderCard` (card/Google Pay) has no caller
anywhere in `lib/` today, same as before — left in place as correctly-shaped but unconsumed, matching
`getCategories`/`calculateFreight`'s status.

**Next step:** checkout end-to-end is now blocked on one concrete, named thing — a real per-SKU variant
id reaching the cart/order — rather than a vague "Phase 8 scope" note. Whoever next works on either
PHASE 4's import/product-detail screen or PHASE 8's checkout should treat those as the same unblocking
step, not two independent ones.

---

## 2026-09-14 — PHASE 4 started: CJ catalog-browse plumbing reconciled with the adopted backend

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing `info`
lints as every prior entry, `flutter test` 13/13, `flutter build web` succeeds). No new test coverage
added for `CjDropshippingService` itself — flagged below as a real gap, not silently skipped.

Picking up PHASE 4 (catalog + CJ import), repeatedly flagged since the 2026-09-12 backend-adoption
entry as "the real next step": the Flutter client's `ApiEndpoints`/`CjDropshippingService`/
`ProductModel` parsing were still written against the *old*, deleted TypeScript backend and didn't
match the adopted `functions/index.js` at all — wrong endpoint names, wrong query param names, and no
awareness of the `{success, data, message}` response envelope every endpoint in the adopted backend
uses. Confirmed with the user beforehand to scope this pass to catalog-browsing plumbing only (search,
detail, admin sync) — not the checkout/payment path, and not any new UI.

An `Explore` audit first read every relevant file on both sides (`functions/index.js` in full, plus
`cjApi.js`/`catalogSync.js`/`pricing.js`/`marginPricingService.js`/`fx.js`/`regions.js` on the backend;
`ApiEndpoints`, `CjDropshippingService`, `ProductModel`, both `ProductRepository` implementations, and
their controllers on the client) and produced a field-by-field diff before any code changed.

**What the audit found, beyond the wrapper mismatch:**
- `ApiEndpoints.cjSearchProducts`/`cjProductDetail`/`cjCreateOrder`/`cjTrackShipment` don't exist as
  exported functions at all; the real names are `searchProducts`/`getProductDetail`. `createFulfillmentOrder`/
  `trackShipment` in `CjDropshippingService` were dead code (zero callers) that also didn't match any real
  endpoint shape.
- `searchProducts`'s live response has no `stock`/`rating`/`soldCount`/`discountPercent`/`compareAtPrice`/
  `currency` — `ProductModel.fromMap` was reading all of those from a shape that can never supply them.
- `getProductDetail` has no top-level price or stock at all — pricing lives per-variant; the real
  variant shape (`{vid, sku, key, attributes, image, supplierPriceUsd, retailPriceUsd, weight}`) has no
  overlap with `ProductVariant`'s existing `{name, options}` attribute-picker shape, so
  `ProductModel.variants` was always `[]` regardless of what the backend returned.
- `FirebaseAdminRepository.syncCjCatalog()` hand-rolled its own partial sync from the client (one page
  of `searchProducts`, no categories/detail/variant/stock enrichment) and batch-wrote into a Firestore
  collection named `catalog` — which the backend's real sync pipeline (`runCatalogSync`,
  admin-claim-gated, up to 9 minutes) never touches; it writes `products`/`categories` instead. Two
  independently-invented, non-overlapping collection names for the same concept, and the client path
  bypassed the admin-claim gate entirely.
- No seller/store field exists anywhere on the backend's catalog responses or Firestore docs — confirmed,
  matches the 2026-09-12 entry. This is a real, load-bearing gap for PHASE 4/5 (mapping a shared catalog
  onto per-seller listings has no backend hook to lean on), not something this pass could fix.
- A second, unrelated stale-endpoint bug surfaced while cross-checking `ApiEndpoints`: `intasendCollectMpesa`/
  `intasendCheckout`/`intasendStatus` (used by `IntasendService`, the buyer-checkout payment path — PHASE 8,
  not this pass) also don't match anything the adopted backend exports (real names are
  `payOrderMpesa`/`payOrderCard`/`confirmIntasendPayment`). Left alone and flagged inline in
  `app_constants.dart` rather than fixed, since it's checkout/payment code deserving its own confirmed
  pass, not catalog-browsing. Same for `FirebaseOrderRepository.placeOrder`/`createOrder`'s request/
  response shape, which is likewise still written against the old deleted backend.

**Changed:**
- **`lib/core/constants/app_constants.dart`**: replaced the four wrong CJ endpoint names with the real
  ones (`searchProducts`, `getProductDetail`, `getCategories`, `calculateFreight`, `runCatalogSync`);
  added inline notes flagging the `createOrder`/IntaSend-checkout staleness found above for whoever picks
  up PHASE 8.
- **`lib/core/network/dio_client.dart`**: `post()` gained an optional `receiveTimeout` override — the
  default 20s would always time out `runCatalogSync`, which can legitimately run for minutes.
- **`lib/data/services/cj_dropshipping_service.dart`**: rewritten. `searchProducts`/`productDetail` now
  call the correct paths with the correct query param names (`categoryId` not `category`, `pid` not
  `id`, plus `size`), unwrap `data` themselves (matching the pattern `FirebaseSubscriptionRepository`
  already established for `subscribeSeller` — no `success` boolean check needed since a `success:false`
  response always carries a non-2xx status, which `DioClient` already turns into a thrown
  `ApiException`), and map the real field names onto `ProductModel` via new private
  `_summaryToProduct`/`_detailToProduct` helpers instead of relying on `ProductModel.fromMap` (deliberately
  left untouched — it's the round-trip shape for the client's own persisted `listings` documents, a
  different concern from parsing the backend's raw catalog response). Added `_variantOptions` to derive an
  attribute-picker from the real per-SKU variant list (distinct values per attribute name) — the closest
  a `{name, options}` shape can get to real variant data without a model change. Added `runCatalogSync()`.
  Removed dead `createFulfillmentOrder`/`trackShipment`.
- **`lib/data/repositories/firebase_admin_repository.dart`**: `syncCjCatalog()` now calls
  `CjDropshippingService.runCatalogSync()` instead of hand-rolling a partial sync and batch-write;
  interface (`Future<int>`) unchanged so `AdminCatalogSyncController` needed no changes.
- **`lib/data/services/firestore_service.dart`**: removed the now-fully-unused `catalog` collection
  getter (confirmed zero remaining references after the above).
- **`firestore.rules`**: removed the stale `catalog/{productId}` block, which referenced a
  `syncCjCatalog` Cloud Function that no longer exists in that form. Left `products`/`categories`
  (the real, server-written collections) with no explicit client rule — default-denied, matching that
  nothing in `lib/` reads either directly today (catalog browsing goes through the HTTP endpoints, not
  Firestore reads); noted inline for whenever that changes.

**Deliberately not done (out of this pass's confirmed scope):**
- `getCategories`/`calculateFreight` are wired up as `ApiEndpoints` constants (accurate names for
  whenever they're needed) but have no `CjDropshippingService` methods yet — nothing in `lib/` consumes
  either today (no category-browsing UI, no shipping-estimate UI), so adding client methods now would be
  speculative.
- No dedicated "recalculate price for margin X" endpoint exists anywhere server-side — margin pricing
  (`pricing.js`/`marginPricingService.js`) is baked silently into `retailPriceUsd` inside search/detail
  responses with no way to ask "what if I set margin to Y%". If PHASE 4's import-editor screen wants an
  interactive margin slider, that needs a new backend endpoint, not a client fix.
- The IntaSend order-checkout path and `FirebaseOrderRepository.placeOrder`'s shape (flagged above) —
  real bugs, same class as the ones just fixed, but PHASE 8 scope, not this pass.
- Reconciling how a shared, unscoped CJ catalog maps onto per-seller `listings` at import time — the
  plumbing this pass fixed makes that possible to build correctly, but no import-editor UI exists yet
  (`SELLORA_IMPLEMENTATION_PLAN.md`'s PHASE 4 section, still not started as app-facing work).

**Verification gap, disclosed:** no test exercises `CjDropshippingService`'s new parsing logic directly
(mocking `DioClient`/Dio) — relied on `flutter analyze`/`flutter test`/`flutter build web` staying clean,
which only proves the code compiles and every *other* code path is unaffected, not that the new mapping
is correct against a live response. Also unverified against a real deployed `functions/index.js` — same
"never run against real backend" caveat as every prior entry (`useMockData` is still `true`).

**Next step:** PHASE 4's remaining app-facing work (a catalog browse/import screen actually using this
now-correct plumbing) is still not started. PHASE 8's stale checkout-payment endpoints, found but not
fixed here, are the next concrete gap if payments work resumes before catalog import screens do.

---

## 2026-09-14 — Role select returns for mobile, seller-only this time

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing `info`
lints as every prior entry, `flutter test` 13/13). No browser-driven check — same disclosed gap as
every prior entry.

User asked for the platform split to be explicit: mobile app leads splash → role select → sign in; web
leads with the marketing view. Web already worked this way (`SelloraApp.initialRoute` picks
`Routes.marketing` under `kIsWeb`) — the actual gap was mobile, where `AuthController.checkSession()`
sent an unauthenticated visitor straight to `Routes.marketing` too, skipping role select entirely
(a deliberate choice made in the entry directly below, before this one).

Re-adding role select isn't a plain revert: the version deleted on 2026-09-13 offered two cards, "Shop
the marketplace" (buyer) and "Start selling" (seller), because buyers were still a shared top-level
role back then. Today a buyer only exists as a customer of one store, signed in from that store's own
`/s/{slug}/login` — there's no top-level buyer destination to point a card at, and no store-directory
screen exists yet for a mobile user without a direct link to find one. Confirmed with the user: keep
role select seller-only for now (a welcome step with "Start selling" → `registerSeller` and "Sign in" →
`login`) rather than also building a new store-search screen to restore the buyer card.

**Changed:**
- **New** `lib/modules/auth/views/role_select_view.dart` — reintroduced, trimmed to the single seller
  card plus "Already have an account? Sign in" and "Learn more about Sellora" links. No `intent`
  argument passed anywhere (today's `LoginView` doesn't branch on one).
- **`lib/app/routes/app_routes.dart`**: added `Routes.roleSelect = '/role-select'`.
- **`lib/app/routes/app_pages.dart`**: registered the route (no binding needed — the view has no
  controller).
- **`lib/modules/auth/controllers/auth_controller.dart`**: `checkSession()`'s no-session branch is now
  `kIsWeb ? Routes.marketing : Routes.roleSelect` instead of unconditionally `Routes.marketing`.
- **`lib/main.dart`**: updated the `initialRoute` comment to describe the full mobile chain.

**Still open:** a buyer with no direct `/s/{slug}` link has no way to find a store from the mobile app —
flagged above as a real gap, not fixed here since the user chose to scope this to the seller-only
welcome step.

---

## 2026-09-14 — Claude Design "Meridian" export reviewed; documented as reference-only, not a build spec

**Status:** documentation only — no Flutter or Cloud Functions code changed.

A Claude Design project ("Sellora Mockups," `_ds/sellora-meridian-design-system-ffa880f5-…`) was shared
for import via the `claude_design` MCP: design tokens (`tokens/*.css`), React recreations of Meridian's
component set, and three click-through portal UI kits (`ui/{admin,buyer,seller}/{bundle.jsx,mockData.js}`)
plus browser/iOS frame chrome for prototyping outside Flutter. Read every listed file before deciding
what, if anything, to bring into the app.

**Findings:**
- The project's own `readme.md` says it was built by reading `lib/app/theme/` and the existing screens
  directly — it's an export *of* the app, not a design *for* the app. Confirmed: `colors.css`,
  `spacing.css`, `radius.css` are value-for-value identical to `AppColors`/`AppSpacing`/`AppRadii`
  (`lib/app/theme/app_colors.dart`, `app_metrics.dart`).
- Every screen in the three `bundle.jsx` files already exists as a Flutter module: seller's
  dashboard/catalog/my_listings/orders/profile/subscription, admin's
  dashboard/sellers/catalog_sync/orders/plans, buyer's home/product_details/cart/checkout/orders/profile
  all have a matching directory under `lib/modules/`.
- The project's auth-flow description ("splash → role select → sign in / register") is now stale: the
  2026-09-13 entry below deleted `role_select_view.dart`/`register_buyer_view.dart`/`store_select_view.dart`
  as part of the multi-tenant storefront rework. The design project predates that change and still shows
  the old shared-marketplace role picker, not today's seller-only `/login` + per-store `/s/{slug}/login`.

**Decision (confirmed with the user):** treat this as an external reference for prototyping, marketing
collateral and decks outside Flutter — not an implementation spec. Reimplementing its screens in Flutter
would rebuild what already exists, and its buyer/auth screens would reintroduce flows deleted this week.
Same category of mistake as the 2026-09-06 marketplace-layer drop that was evaluated and deleted earlier
(not logged in this file, but on record): treat the repo, not an externally-authored artifact, as the
source of truth. No code was changed as a result of this review.

**Still open:** the design project itself hasn't been corrected (its readme and auth mockups remain
stale) — if it's kept as a living reference, a follow-up push via `DesignSync` to update the auth screens
and note the storefront-per-seller model would keep it useful; not done this session since it wasn't
requested.

---

## 2026-09-13 — Sellora's own login becomes seller-only; buyer auth moves into the storefront

**Status:** implemented and verified this session (`flutter analyze` clean — 4 pre-existing `info`
lints, `flutter test` 13/13, `flutter build web` succeeds). No browser-driven check — same disclosed
gap as every prior entry (no `chromium-cli`/Python in this environment); see "Verification gap" below.

Closed the gap between the multi-tenant data model (already built — see the 2026-09-11 entries) and
Sellora's own auth flow, which still had a full buyer path living at the top level. Auditing first
found most of the *data model* already done: `StoreModel`/`StoreRepository` (abstract+mock+Firebase),
`StoreScope`, a guest-browsable `StorefrontView`, and `firestore.rules`' `stores/{storeId}/{customers,
products,orders}` rules all already existed and needed no changes. What was actually missing was the
auth wiring: `RoleSelectView` still offered "Shop the marketplace," `RegisterBuyerView`/`StoreSelectView`
were reachable from Sellora's own top-level flow instead of from inside a store's own URL, and both
buyer/seller profile screens had hardcoded shortcuts into the other role's login. Confirmed with the
user beforehand: delete `StoreSelectView` outright rather than repurpose it as a store directory — its
own code comment already called it a stand-in "until path routing (`/s/:slug`) exists," which now does.

**A real bug found and fixed along the way:** `MockAuthRepository.signIn`'s buyer branch never set
`storeId` at all — every mock buyer sign-in silently got `storeId: null`, breaking
`CartRepository.setStore`/`BuyerOrdersController`'s store-scoped queries for anyone using the generic
mock sign-in shortcut (not just this session's new store-scoped login path).

**Changed:**
- **Deleted** `lib/modules/auth/views/role_select_view.dart`, `register_buyer_view.dart`,
  `store_select_view.dart`, `lib/modules/auth/controllers/store_select_controller.dart`. Removed
  `Routes.roleSelect`/`registerBuyer`/`storeSelect` and their `GetPage`s.
- **`lib/modules/auth/views/login_view.dart`** rewritten as the sole entry point (`Routes.login`
  replaces the old role-chooser) — seller/admin only, no `intent` branching. Split-screen layout on wide
  screens (a marketing panel — wordmark, headline, one testimonial, three trust badges, all copy reused
  from existing `MarketingView` claims — next to the sign-in form), form-only below the desktop
  breakpoint. Modeled on a generic single-purpose SaaS login pattern; the `app.droxen.cloud/login`
  reference the user linked 403'd on fetch, so this wasn't built against the actual page — flagged to
  the user to compare and redirect if the shape is off.
- **New** `lib/modules/storefront/storefront_login_view.dart` / `storefront_register_view.dart` — a
  buyer's sign-in/registration as a customer of one store, reached only at `/s/{slug}/login` and
  `/s/{slug}/register` (`Routes.storefrontLogin`/`storefrontRegister`), storeId resolved from the route
  `:slug` via `StoreScope` rather than passed as `Get.arguments`. `StorefrontView` gained an account
  icon in its `AppBar` linking here (or straight to `/buyer` if already signed in as *this* store's
  buyer).
- **`AuthRepository.signIn`** gained an optional `storeId` param (`FirebaseAuthRepository` ignores it —
  a real buyer's doc already carries their true storeId; `MockAuthRepository` uses it to fix the bug
  above). **`AuthController`** gained `signInToStore` (rejects a sign-in whose result isn't a buyer of
  exactly that store — signing in from the wrong store's page can't silently attach the wrong
  cart/order history) and taught `signIn` to reject a buyer-role result outright, so Sellora's own login
  can't be used as an accidental side door into the buyer portal.
- Removed the cross-role shortcuts: `BuyerProfileView`'s "Become a seller" tile, `SellerProfileView`'s
  "Shop as a buyer" tile (neither makes sense once a buyer belongs to one specific store). Buyer
  sign-out (`BuyerProfileView`) now resolves the buyer's store slug and returns them to `/s/{slug}`
  instead of Sellora's own login, falling back to `/marketing` if the store can't be resolved.
  `RoleMiddleware`'s unauthenticated fallback now splits by role: buyer → `/marketing` (no store context
  to send them anywhere store-specific), seller/admin → `/login`.
- `MarketingView`: removed the buyer sign-in CTA and the footer's "Shop the marketplace" link — no path
  from marketing into a buyer flow through Sellora's own auth.

**Not done:** cart/checkout still isn't wired into the public `StorefrontView` itself (same deliberate
deferral its existing code comment already stated) — a buyer still completes shop→cart→checkout via the
existing flat `/buyer` shell after signing in, same as before this session. No `firestore.rules` or
`firestore.indexes.json` changes were needed — verified the existing tenant-scoped rules and the
unfiltered/single-field-sorted store subcollection reads already cover this without a new composite
index.

**Verification gap, disclosed:** did not drive this through an actual browser — same environment gap
noted in the 2026-09-11 entries (no `chromium-cli`, no Python). Relied on `flutter analyze`, `flutter
test` (13/13, including a fixed `test/seller_shell_controller_test.dart` fake that needed the new
`signIn` param), and a clean `flutter build web`. Worth a manual click-through (seller login → dashboard;
`/s/aminas-picks` and `/s/jengo-electronics` → account icon → sign in → confirm separate carts/order
history per store; buyer sign-out lands back on the right store) before this is considered fully proven.

**Next step:** none of this touches `functions/` — the adopted backend still has no seller/store concept
at all (see the 2026-09-12 backend-adoption entry), which remains separate, larger work.

---

## 2026-09-12 — PHASE 3 (Billing): security core, configurable plan schema, usage tracking

**Status:** implemented and verified this session (`flutter analyze` clean — 4 pre-existing `info`
lints, `flutter test` 13/13, `cd functions && npm test` 227/227, `cd firestore-tests && npm test`
18/18). Builds on the same-day backend adoption entry below — read that first.

Closes the gap both this file and `SELLORA_IMPLEMENTATION_PLAN.md` had flagged since 2026-09-11:
`FirebaseSubscriptionRepository.subscribeSeller` wrote `billing_history`/`users` subscription fields
directly from the client, which `firestore.rules`' `allow write: if false` on `billing_history` already
silently blocked against real Firestore. Confirmed scope with the user beforehand: security core +
configurable plan schema + usage tracking, keeping the existing Starter/Growth/Scale pricing and
per-plan commission unchanged.

**Data model:** `SubscriptionPlanModel` gained `orderLimit`/`storeLimit`/`features` (backward-compatible
defaults, `copyWith` added) — `storeLimit` is schema-only/unenforced pending decision #4 (multi-store),
`orderLimit` is schema-only/unenforced because `createOrder`'s backend has no `sellerId` to count
against yet (see the backend-adoption entry). New `SubscriptionRecordModel` (`subscriptions/{sellerId}`,
read-only from Dart) and `BillingHistoryEntryModel` (`billing_history/{id}`) — both written only by
Cloud Functions. New `SubscriptionUsageModel` (listing usage only; no order-count fields for the same
reason `orderLimit` isn't enforced). `AuthRepository` gained `refreshCurrentUser()` — re-reads the
user doc bypassing the in-memory cache, since activation is now server-side and the client has no
realtime channel to it.

**Cloud Functions:** new `functions/lib/subscriptions.js` — `createBillingEntry` (server-prices from
`subscription_plans`, writes a pending ledger entry), `activatePendingSubscription` (idempotent —
guards on `isPayable`/entry status — upserts `subscriptions/{sellerId}` and mirrors
`subscriptionPlanId`/`subscriptionActiveUntil`/`sellerStatus` onto `users/{sellerId}` in one batch),
`attachBillingPaymentAttempt`/`billingRefMatches` (the anti-fraud invoice-binding check, mirroring
`orders.js`'s `paymentRefMatches` — without it, a genuinely-completed IntaSend invoice for a *different*
payment could be paired with someone else's billing entry id and activate their subscription for free).
`functions/index.js` gained `subscribeSeller`, `payBillingMpesa`, `payBillingCard`,
`confirmBillingPayment` — exact structural mirrors of the existing order-payment handlers, reusing
`intasend.mpesaStkPush`/`createCheckout`/`checkPaymentStatus`/`verifyAmount` completely unchanged.
`intasendWebhook` now checks `billing_history` before falling through to the existing order lookup (order
ids and billing entry ids can never collide — separate collections, separate auto-ids). New
`functions/test/subscriptions.test.js` (9 cases) covers `isPayable`/`billingRefMatches` as pure
functions, matching this codebase's existing test style.

**Firestore rules:** new `subscriptions/{sellerId}` block (owner-or-admin read, `write: if false`).
`users/{uid}`'s update rule extended with a field-level lockdown via
`request.resource.data.diff(resource.data).affectedKeys()` blocking self-writes to
`subscriptionPlanId`/`subscriptionActiveUntil`/`sellerStatus` — the same technique already used to lock
down `role`, closing the hole where a seller could self-activate by editing their own user doc.
`create` stays unrestricted (signup legitimately sets `sellerStatus: pendingApproval`). New
`firestore-tests/billing-hardening.test.js` (7 cases).

**Repositories:** `SubscriptionRepository.subscribeSeller` no longer takes a client-supplied
`paymentReference` — it returns a pending `BillingHistoryEntryModel`; added `fetchUsage`.
`FirebaseSubscriptionRepository` now injects `DioClient`, posts to the new endpoints, and no longer
writes `_fs.users`/`_fs.billingHistory` directly at all (the actual fix). `MockSubscriptionRepository`
now injects `AuthRepository` and activates the mock user itself inside `subscribeSeller` — this is what
let the hand-rolled `UserModel` reconstruction duplicated in both `SellerOnboardingController` and
`SellerSubscriptionController` be deleted entirely, real mode's copy of which also had to go regardless
since the new rules block it.

**Controllers/UI:** `SellerOnboardingController` gained an `OnboardingStep.pendingConfirmation` step and
`refreshStatus()` — in mock mode nothing changes (repository already activated synchronously); in real
mode, payment is fired via `payBillingMpesa` and the screen shows a pending state with a manual "I've
completed payment" refresh action, since there's no live confirmation channel (matching buyer checkout's
own fire-and-forget standard — deliberately not introducing polling/streaming here). `switchPlan` on
`SellerSubscriptionController` gained the identical pattern plus a try/catch it was missing before (a
real pre-existing bug — an exception there previously propagated unhandled). `SellerSubscriptionView`
gained a "Usage this period" listing-count card and a "Refresh status" action. `AdminPlansController`/
view gained order/store-limit and feature-flag editing (schema-only, left visibly editable rather than
hidden). `SellerCatalogController.listProduct` gained a soft, client-side listing-limit upsell check —
deliberately not server-enforced, since listing creation isn't server-authoritative yet (Phase 5).

**Not done (deliberately deferred, not silently skipped):** order-limit enforcement inside `createOrder`
and order-usage display — both need `sellerId` on the order document, which the newly-adopted backend's
`orders.js` doesn't have (see below); store-limit enforcement — gated on decision #4; a full billing UI
(invoices list, cancel/resume, plan-comparison) — out of the confirmed scope for this pass.

**Next step:** PHASE 4/5/8's reconciliation of the adopted backend with the Flutter client's
`ApiEndpoints`/`ProductModel`/order shapes is what unblocks the deferred items above.

---

## 2026-09-12 — Cloud Functions backend replaced (rebranded from a dropped-in codebase); Phase 3 started

**Status:** in progress this session, picking up from "let's go to phase 3" (billing).

Before Phase 3 work could start, found `functions/` in an inconsistent state: the tracked Sellora
TypeScript functions (`auth.ts`, `cj.ts`, `index.ts`, `intasend.ts`, `orders.ts`, `tsconfig.json`) were
deleted, uncommitted, and replaced on disk by an untracked plain-JavaScript codebase from a different
project, "GoShopping" (a single-vendor CJ dropshipping storefront — `functions/package.json`'s own
description said so). Confirmed with the user this was deliberate: keep it, rebrand it, and **fold its
capabilities into Sellora's existing multi-tenant architecture** rather than restore the old TS code or
pivot Sellora to single-vendor.

**What the adopted codebase actually is** (a strict superset of what it replaces, once rebranded): a
real CJ auth/token-refresh/catalog-sync/tracking pipeline (`cjAuth.js`, `cjApi.js`, `catalogSync.js`,
`tracking.js`) well beyond the old `cj.ts` sketch; a margin-based Smart Pricing Engine with FX and
region/VAT handling (`marginPricingService.js`, `pricing.js`, `fx.js`, `regions.js`); IntaSend *and*
PayPal (`intasendApi.js`, `paypalApi.js`), with real provider-side refunds (`refunds.js`); product
reviews with a transactionally-updated rating aggregate (`reviews.js`); a per-instance LRU/TTL cache
(`cache.js`); and a 218-case `node --test` suite covering the pure logic in all of it. Auth is the same
shape as before — `Authorization: Bearer <idToken>` verified via `admin.auth().verifyIdToken`.

**The real gap, not fixed this session:** this codebase has **no seller/store concept anywhere** — one
global `products` catalog, one global `orders` collection, no `sellerId`/`storeId` on anything —
whereas Sellora's own multi-tenant work (`stores/{storeId}/...`, `StoreScope`, per-seller `listings`,
the 2% marketplace fee split) assumes many sellers each running a store. `orders.js` and everything
hung off it (`payOrderMpesa`/`payOrderCard`, `confirmIntasendPayment`, `intasendWebhook`, `refundOrder`,
`submitProductReview`'s verified-purchase check) has no seller/store attribution or fee split. The
Flutter client's current `ApiEndpoints`/`ProductModel.fromMap`/`FirebaseOrderRepository`/
`CjDropshippingService` also don't match this backend's request/response shapes at all — it wraps
every response as `{success, data, message}`, not the old flat fields, and uses different field/query-
param names throughout. Reconciling per-seller order/catalog attribution with this backend is separate
future work (Phase 4/5/8 territory) — not attempted here. Since `AppConstants.useMockData` is still
`true` and the app has never run against real Firebase, none of this is a regression from a working
state; it's a disclosed gap in scaffolding, same as every other "Not started" line in
`SELLORA_IMPLEMENTATION_PLAN.md`.

One more unreconciled duplicate: admin gating in this codebase is a Firebase Auth custom claim
(`user.admin === true`), while the rest of Sellora checks a Firestore `users/{uid}.role` field. Not
fixed here — flagging so a later session doesn't assume Sellora's existing admin accounts can call
`refundOrder`/`runCatalogSync`.

**Changed:**
- `functions/lib/orders.js` — the one substantive rename (`GoShopping order ${orderId}` → `Sellora
  order ${orderId}`, a CJ order remark string). This and `functions/package.json`'s `description` were
  the *only* two "GoShopping" strings anywhere in the adopted code — confirmed by grep.
- `functions/package.json` — added a no-op `"build"` script (the old `tsc` step is gone along with
  `tsconfig.json`, but `firebase.json`'s `predeploy` hook still calls `npm run build`).
- `CLAUDE.md` — Cloud Functions command block updated to drop the `tsc` framing.
- Deleted `functions/src/*.ts`/`tsconfig.json` left deleted, not restored — no git operations performed
  (add/rm/commit stay the user's call).

**Verification:** `cd functions && npm run build && npm test` — build no-ops cleanly, all 218
pre-existing tests still pass unchanged (nothing besides the two string edits was touched).

**Next step:** Phase 3 (billing/subscriptions) proceeds on top of this backend, self-contained enough
to not depend on the deferred order/catalog multi-tenant threading — see the Phase 3 entry that follows
once that work lands this same session.

---

## 2026-09-12 — Marketing landing page; seller-shell store-resolution guard

**Status:** implemented and verified this session (`flutter analyze` clean — 4 pre-existing `info`
lints, `flutter test` 8/8 passing).

Picking up from the 2026-09-11 entries below. Two things landed:

1. **Public marketing page** (commit `3318770`, earlier today, undocumented until now): a new
   `lib/modules/marketing/` (`MarketingView`/`MarketingController`, route `/marketing`) is Sellora's
   own landing page — hero, how-it-works, pricing pulled from `SubscriptionPlanModel`, FAQ, footer.
   `AuthController.checkSession` now sends a signed-out visitor here instead of straight to
   `Routes.roleSelect`; `RoleSelectView` gained a "Learn more about Sellora" link back to it. Self-
   contained — no repository or model changes.
2. **Seller-shell store-resolution guard** (this session): closes the PHASE 2 item both this file and
   `SELLORA_IMPLEMENTATION_PLAN.md` had listed as open — "nothing blocks navigation while the store is
   resolving or missing." `SellerShellView` now reads `StoreScope.isResolving`/`current`/`errorMessage`
   (already-reactive state `SellerShellController.onInit()` was populating but nothing consumed) before
   rendering the tab shell: a loading state while resolving, an `EmptyState` with a "Try again" action
   (`SellerShellController.resolveStore()`, the same lookup `onInit` already ran, now re-callable) and
   a "Sign out" fallback (`SellerShellController.signOut()`, new) if it comes back empty. Deliberately
   does **not** add a store-creation screen — every current signup path already creates a store
   (2026-09-11 fix), so an empty `StoreScope.current` is a defensive/edge case, not a known-reachable
   one; building a creation flow for it now would be speculative scope, not this item.

**Changed:** `lib/modules/seller/shell/seller_shell_controller.dart` (extracted `onInit`'s lookup into
public `resolveStore()`, added `signOut()`), `lib/modules/seller/shell/seller_shell_view.dart` (the
guard), `SELLORA_IMPLEMENTATION_PLAN.md` (PHASE 2 section updated to match both changes above).

**Not done:** the store switcher and store-creation-recovery-screen items noted above remain open,
same as before.

**Verification gap, disclosed:** same as every prior entry in this file — no browser/widget-level
check of the new loading/error branches, only `flutter analyze` and the pre-existing
`seller_shell_controller_test.dart` cases (which still pass unchanged, since `onInit`'s behavior is
unchanged, just renamed-and-exposed). `signOut()` isn't unit tested — it's a thin wrapper around
`AuthRepository.signOut()` + `Get.offAllNamed`, matching `AuthController.signOut()`'s existing
(likewise untested) shape; testing GetX navigation here would need a full `GetMaterialApp` harness this
repo doesn't otherwise use for controller tests.

**Next step:** decisions #1/#4/#5 are still the gate for going further into PHASE 3+ (see 2026-09-11
entry below) — nothing in today's work changes that.

---

## 2026-09-11 — Multi-tenant pivot: Phase 0 audit, Phase 1 foundation, Phase 2 started

**Status:** in progress, uncommitted. Supersedes the "no implementation code written" status on every
entry below — implementation began without a separate explicit sign-off message, on the reasoning
that decisions #2 (Firestore subcollection model) and #3 (path routing at `/s/:slug`) from the
2026-09-08 design doc are the only two Phase 1–3 depend on, both already recommendations rather than
open questions, and phases 1–3 don't touch Q2/Q3 (CJ account ownership, IntaSend split capability) per
that entry's own note. Decisions #1, #4, #5 (buyer account scoping, multi-store-per-seller, white-label
depth) are still open and should be confirmed before Phase 3 (seller onboarding/entitlements) goes far.

**Changed on disk:**
- `SELLORA_ARCHITECTURE.md`, `SELLORA_IMPLEMENTATION_PLAN.md` — audit + 8-phase plan (finer-grained
  than the design doc's phase list, adapted to what actually exists in the repo).
- Phase 1: Sellora theme pair (`#FFC107` / `#303F9F`) with system dark mode in `app_theme.dart`,
  shared `lib/core/widgets/app_page.dart` (page header, search field, loading/error states), seller
  dashboard migrated to the shared header.
- Phase 2 (partial): `lib/modules/storefront/` — `StoreScope` (`GetxService` resolving `/s/:slug` to
  a `StoreModel`, tested in `test/store_scope_test.dart`), `StorefrontView`/`Controller`/`Binding`
  wired into `app_pages.dart`/`app_routes.dart`/`initial_binding.dart`. `ProductRepository` gained
  `storeProducts(storeId, ...)` (mock + Firebase implementations). `FirestoreService` gained
  `storeProducts()`/`storeOrders()` subcollection accessors.
- `firestore.rules` — added `stores/{storeId}/products` and `stores/{storeId}/orders` subcollection
  rules. These paths existed in `firestore_service.dart` with no matching rule, which under
  Firestore's default-deny meant they were unreachable — a latent bug, not a leak, but it would have
  silently broken the first real-Firestore run.
- `OrderRepository` gained `storeOrders(storeId)` (mock + Firebase), mirroring `storeProducts()`. Like
  `storeProducts()`, this reads the new subcollection only — `placeOrder` still writes to the flat
  `orders` collection, so `storeOrders()` returns nothing against real Firestore until that write path
  migrates. Mock's version filters the existing seed list by `OrderModel.storeId` instead, since mock
  orders already carry that field.
- `firebase.json` gained an `emulators.firestore` block (port 8080, UI disabled) so `firebase
  emulators:exec` runs non-interactively.
- New `firestore-tests/` — a small Node package (`@firebase/rules-unit-testing`, run via
  `npm test`, which shells out to `firebase emulators:exec --only firestore "node --test"`) with
  `tenant-isolation.test.js`: 5 tests proving a seller can write/read/update only their own store's
  `products`/`orders`, a buyer's `customers` profile is private to them + their store's seller + admins,
  and the storefront stays publicly readable for guests. All 5 pass against the real emulator, with
  the rules engine's own `PERMISSION_DENIED` responses visible in the log — not vacuous passes.

**Verification:** `flutter analyze` clean (only 6 pre-existing `info`-level lints), `flutter test`
passes (2 tests), `npm test` in `firestore-tests/` passes (5 tests, ~12s against the emulator).

**Found and left alone:** `functions/node_modules` (5,839 files) is already committed to git. Not this
session's doing and not touched — flagging it here since it's the kind of thing a later session might
otherwise "fix" by surprise. `firestore-tests/node_modules` is gitignored so this isn't repeated.

**Not done:** route middleware enforcing store scope on seller-admin routes (only the public storefront
resolves a slug today), store-scoped `customers`/`settings`/`collections` repository *methods* (the
Firestore path and rules exist; nothing in `lib/` reads/writes store-scoped customers yet beyond
`AuthRepository`'s existing write), the `placeOrder`/product-create write-path migration to the new
subcollections, and any indexes for `storeOrders()`/`storeProducts()` (none needed yet — both do a bare
`.get()`/`.orderBy()` with no `.where()`).

**Also added this session:** `StoreScope.resolveForSeller(sellerId)` (refactored `resolveSlug` and it
onto a shared `_resolve` helper to avoid duplicating the loading/error-state bookkeeping), wired into
`SellerShellController.onInit()` so every seller-admin route populates `StoreScope.current` with the
signed-in seller's own store, the same way the public storefront does for a slug. Picks
`storesForSeller(sellerId).first` — a placeholder for "the active store" until a store switcher exists
(decision #4). Both `SellerShellController` and `StoreScope` take constructor-injected dependencies
(default to `Get.find`) so this is unit-testable without a GetX test harness; see
`test/seller_shell_controller_test.dart` and the two new cases in `test/store_scope_test.dart`.

**Gap found, not fixed:** `AuthRepository.signUpSeller` (both mock and Firebase) never calls
`StoreRepository.createStore` — a freshly-registered seller has no `StoreModel` at all, ever. Today
nothing reads `StoreScope` from the dashboard so this was invisible; `resolveForSeller` now surfaces it
correctly as "no store yet" rather than crashing, but there is still no screen that lets a seller
create one. This is Phase 3 work ("seller onboarding/entitlements... store creation"), not fixed here.
The mock quick-login path (`mock-seller` / `mock-seller-2`) is unaffected — those uids already have
seeded stores.

**Verification gap, disclosed:** did not drive this through an actual browser. This environment has
neither `chromium-cli` nor Python (the two paths the `run` skill's browser-driven pattern needs), and
Flutter web renders to canvas rather than DOM text nodes, so generic Playwright text-selectors aren't
reliable without first enabling Flutter's semantics/accessibility tree — a setup investment outside
this change's scope. Relied instead on `flutter analyze` (clean) and unit tests exercising the exact
`onInit()` path for both a signed-in and a signed-out seller. Worth a `/run-skill-generator` pass if
browser-driven verification becomes routinely needed for this repo.

**Next step:** decisions #1/#4/#5 are still open and Phase 3 (seller onboarding/entitlements) depends
on #4 (single vs. multi-store per seller changes the dashboard's store-picker and the custom-claim
shape) — worth confirming before going much further into Phase 3. Within Phase 2 itself, still open:
route middleware/guard for seller-admin routes (today `SellerShellController` resolves the store but
nothing blocks navigation while it's resolving or missing), and the `placeOrder`/product-create
write-path migration onto the `stores/{storeId}/...` subcollections.

---

## 2026-09-11 — TODOD.md adopted as phase framework; security/checkout hardening

**Status:** implemented and verified this session (`flutter analyze` clean, `flutter test` — 8/8
passing, `cd functions && npm run build` clean).

The user handed in `TODOD.md`, a 56-section "master build prompt" asking for a full Shopify-class
rebuild in one pass, plus an instruction to "remove all mock data." Neither is something to execute
literally in one session — `TODOD.md`'s own rules say to work in phases and audit first, and this
repo's `SELLORA_ARCHITECTURE.md` already shows the real backend isn't close to safe to point real
money at. Three decisions were confirmed with the user before writing any code:

1. **Phase framework**: adopt `TODOD.md`'s `PHASE 0`–`PHASE 12` numbering going forward (re-keyed into
   `SELLORA_IMPLEMENTATION_PLAN.md`), rather than restarting the project under it — the existing audit
   and phased plan stay the source of truth for *what's actually next*, `TODOD.md` for *how phases are
   named/ordered*.
2. **Platform service fee: 2%** (`TODOD.md` §15), replacing the app's previously-unused 5%
   `defaultCommissionPercent` constant. Renamed to `AppConstants.platformServiceFeeRate = 0.02`.
3. **Tenant write-path migration deferred** — `stores/{storeId}/products`/`.../orders` stay read-only
   this pass; new work continues against the flat `listings`/`orders` collections.

### What "remove mock data" actually required

A second, sharper audit pass (reading `functions/src/*` and the checkout/repository code directly,
not just the existing docs) found the real backend was further from usable than documented — flipping
`AppConstants.useMockData` to `false` as-is would have shipped a self-escalating-privilege,
unverified-payment app:

- `firestore.rules` let a user set their own `role` to `'admin'` — every privileged check in the
  ruleset is `role() == 'admin'`.
- `listings` writes checked `role() == 'seller'` only, not ownership — any seller could edit any other
  seller's listing.
- Checkout was fully client-trusted: `CheckoutController` computed `total` and wrote
  `paymentReference` itself; `FirebaseOrderRepository.placeOrder` just `.set()` it verbatim.
- `intasendWebhook` was a stub — logged the payload, verified nothing, never touched Firestore. No
  payment was ever actually confirmed anywhere.
- The old `onOrderCreated` trigger's CJ-fulfillment call POSTed to the auth-gated `cjCreateOrder`
  function with no `Authorization` header — it would 401 every time, and it also ran before payment was
  verified (its own comment already flagged this).
- `functions.config()` (CJ/IntaSend credentials) is deprecated in the installed `firebase-functions`
  version, with no `.env`/`.runtimeconfig.json` present — a fresh deploy would call CJ/IntaSend with
  `undefined` credentials.
- `AuthRepository.signUpSeller` (mock and Firebase) never created a `StoreModel` — confirmed still true
  from the 2026-09-11 Phase-2 entry above.

None of this needed new decisions or real provider credentials to fix correctly, so it got fixed this
session. `useMockData` stays `true` — flipping it for real use is a separate step gated on things only
the user can supply (a real CJ Dropshipping account, a confirmed IntaSend production setup with the
webhook verification scheme reconfirmed against current docs, and `firebase functions:secrets:set` run
with real values).

### Changed

- **`firestore.rules`**: `users.role` can no longer be self-written (only an existing admin can change
  someone's role); `users` read narrowed from "any signed-in user" to owner-or-admin; `listings`
  create/update now ownership-checked; `orders` create is `allow create: if false` (Cloud-Function-only
  via Admin SDK).
- **`functions/src/orders.ts`**: new `createOrder` (`onRequest`, `requireAuth`) re-prices every item
  from `listings` server-side, computes the 2% fee snapshot, writes the order with
  `paymentStatus: 'pending'`. The old `onOrderCreated` trigger and its broken CJ call are gone —
  fulfillment now happens from the webhook, after payment is confirmed, not at document-creation time.
- **`functions/src/cj.ts`**: extracted `placeCjOrder()` as a plain function so the webhook can call it
  in-process (no HTTP self-call, no missing-auth-header bug); migrated CJ credentials to
  `defineSecret`/`runWith`.
- **`functions/src/intasend.ts`**: `intasendWebhook` now verifies a shared "challenge" value (flagged
  inline as needing reconfirmation against IntaSend's current docs before go-live — same caveat style
  already used for `cj.ts`'s auth handshake) and, on a confirmed payment, looks the order up by
  `api_ref` (the order id), sets `paymentStatus`/`paymentReference`, and calls `placeCjOrder` per item.
  Migrated the secret key to `defineSecret`.
- **`lib/data/models/order_model.dart`**: added `OrderPaymentStatus` (`pending`/`paid`/`failed` —
  named distinctly from `IntasendService`'s own `PaymentStatus` to avoid an import collision) and the
  fee snapshot fields (`serviceFeeRate`, `serviceFeeAmount`, `sellerRevenue`, `paymentFee`); added
  `copyWith`.
- **`lib/modules/buyer/checkout/checkout_controller.dart`** +
  **`lib/data/repositories/firebase_order_repository.dart`**: checkout now creates the order
  server-side (via a new `ApiEndpoints.createOrder` call) *before* contacting IntaSend, using the
  server-assigned order id as the payment's `api_ref`/narrative, so the webhook can find it later.
  Mock mode is untouched — it still fakes an instant "paid" order in one step, since there's no server
  to re-price against or webhook to wait on.
- **`lib/data/repositories/auth_repository.dart`** + **`mock/mock_auth_repository.dart`**:
  `signUpSeller` now creates a `StoreModel` (slug derived from the store name via a new
  `lib/core/utils/slug.dart`, de-duplicated against existing slugs). Both repos now take an optional
  constructor-injected `StoreRepository` (default `Get.find`), matching the testability pattern the
  2026-09-11 Phase-2 entry above established for `SellerShellController`/`StoreScope`.
- **`lib/app/bindings/initial_binding.dart`**: `StoreRepository` registration moved before
  `AuthRepository` in both branches — required now that `AuthRepository`'s constructor resolves it
  eagerly via `Get.find`.
- **`SELLORA_ARCHITECTURE.md`** (section K) and **`SELLORA_IMPLEMENTATION_PLAN.md`** (re-keyed to
  `TODOD.md`'s phase numbering) updated to match.
- New `test/auth_repository_test.dart` (2 cases: store gets created on signup; slug de-duplication).

### Not done this session (deliberately)

Everything in `TODOD.md` PHASE 3–7/9–11 (billing UI, CJ catalog import, store builder, storefront,
analytics/marketing, admin panel, i18n); the `stores/{storeId}/...` write-path migration; the payment
custody model decision (the two conflicting 2026-09-08 entries above are still unresolved — this
session's webhook/order work is written to be compatible with either outcome); the CJ shared-vs-
per-seller account decision; subscription-payment webhook wiring (`billing_history` writes are still
client-side and silently blocked by rules against real Firestore — same class of bug as the order one
just fixed, next in line for Phase 3).

### Verification gap, disclosed

Did not drive the new `createOrder`/webhook flow through the Firebase emulator or a real IntaSend
sandbox call — this environment has neither running, and the IntaSend webhook "challenge" scheme is
implemented from memory of their published docs, not verified against a live account. Flagged inline
in `intasend.ts` and in `SELLORA_IMPLEMENTATION_PLAN.md`'s PHASE 12 as needing a firestore-tests case
and a real-account read-through before deploy, rather than claimed as tested.

---

## 2026-09-09 — Payment design finalized: IntaSend Split Payments mechanics

**Status:** design complete, still awaiting overall sign-off. No implementation code written.

Section 04 fully specified per explicit direction: buyer funds collect into Sellora's IntaSend
account and split automatically at collection via IntaSend Split Payments (sub-accounts) — seller's
net share to their own sub-account, CJ-cost-plus-fee stays with Sellora. Design document updated in
place: <https://claude.ai/code/artifact/0b1113cb-1fc9-4176-9dc7-7df3bfda170f>

New content:
- **Split calculation** — computed fresh per order (not a stored ratio), since product mix varies:
  `orderTotal / costOfGoods / platformFee / sellerNet`, in minor units, rounding remainder to
  Sellora never the seller.
- **Paying CJ** — explicit that CJ isn't an IntaSend party, so this is a second, Sellora-initiated
  payment funded from its own settled balance, not a live per-order transfer. Sellora keeps a small
  bounded float in its CJ wallet so fulfilment doesn't wait on settlement timing — a materially
  smaller exposure than the original direct-to-seller design's open "who fronts CJ" problem.
- **Payout hold policy** — recommended holding seller payouts until delivery is confirmed (standard
  marketplace practice). Flagged a real gap in the current codebase: `OrderStatus.delivered` is
  seller-self-reported with nothing independent behind it, which is a conflict of interest as a
  payout trigger — recommended wiring the hold timer to CJ's own tracking data
  (`cjTrackShipment`, already stubbed) instead of trusting self-report alone.
- Data model: `orders/{id}` gains a `settlement` map; new `stores/{id}/payouts` subcollection; new
  isolation tests for both. `stores/{id}/private/payments` gains `intasendSubAccountId`/`kycStatus`.
- Commission model reverts back to "live split at collection" (from the prior revision's "invoiced
  arrears," which was specific to the direct-to-seller design this supersedes).
- Sharpened the open question that used to be "does IntaSend support this" (now decided) into five
  concrete API specifics to confirm before Phase 4: split precision (fixed amount vs. percentage),
  sub-account KYC turnaround, Payouts API minimums/fees, settlement schedule, and refund behavior on
  an already-split transaction.

**Next step:** unchanged from the prior entry — Phase 0 sign-off, then Q1–Q5 (Q3 now the five-item
IntaSend checklist above).

---

## 2026-09-08 — Bug fixes + responsiveness pass (current marketplace UI)

**Status:** done. First real code changes in this repo (everything above was design-only). Scoped
to the existing marketplace-model Flutter UI — unrelated to the multi-tenant pivot below, which is
still awaiting sign-off and untouched by this pass.

### Bugs fixed

- **Buyer shell tab restore ran on every `build()`**, not once — `Get.arguments['tab']` was
  re-applied via `addPostFrameCallback` on any rebuild, silently snapping the user back to the
  checkout-handoff tab (e.g. after a MediaQuery-driven rebuild on resize). Moved into
  `BuyerShellController.onInit()`, which runs exactly once per controller lifetime.
- **Data loss on rebuild**: `TextEditingController`/`GlobalKey<FormState>` were created inline in
  `StatelessWidget.build()` in `LoginView`, `RegisterBuyerView`, `RegisterSellerView`,
  `CheckoutView`, and onboarding's `_PaymentStep` — any rebuild (a responsive `MediaQuery` read is
  exactly that trigger) would silently wipe whatever the user had typed. Converted all five to
  `StatefulWidget`s owning their controllers in `initState`/`dispose`. This was a prerequisite for
  adding responsiveness to those screens safely, not just a cleanup.
- **`MyListingsView`'s relist switch was a no-op**: `Switch.onChanged` unconditionally called
  `unlist`, so turning a paused listing back on silently did nothing. Added
  `MyListingsController.relist()` and branched on the switch's new value.
- **Admin catalog sync's "Last synced" label never updated**: the controller exposed the repo's
  plain `DateTime?` getter through an `Obx`, which has no reactive dependency on a non-Rx read — the
  sync worked, the label just never refreshed. Made `lastSyncedAt` an `Rxn<DateTime>` on the
  controller.
- **Mock-mode cold start stalled ~3s on every launch**: `MockAuthRepository.userChanges` never
  emitted until an explicit sign-in/out, so `checkSession()`'s `.first` always hit its timeout —
  directly undercutting the README's "try it in 60 seconds" claim. Now yields the current value
  immediately, matching how the Firebase-backed implementation behaves.
- **`RoleSelectView` could overflow** on a short viewport: a `Spacer()`-based `Column` with no
  scroll fallback. Fixed with a scroll view and fixed spacing rather than a flex spacer — note a
  `Spacer()` inside a `SingleChildScrollView` is a different, worse bug (unbounded-height
  `RenderFlex` crash), so the fix is spacing, not just "add scrolling."
- Plus the 5 pre-existing `flutter analyze` lint infos (missing `const`, double-quote style).

### Responsiveness

- New `lib/core/utils/responsive.dart` — breakpoints, `BuildContext` extensions (`isWide`,
  `pageHorizontalPadding`, …), `ResponsiveCenter` (caps + centers page content on wide screens),
  `centeredSliverPadding()` for `CustomScrollView` screens, `productGridDelegate()`
  (`SliverGridDelegateWithMaxCrossAxisExtent`-based, so grids grow columns with width instead of a
  hardcoded count).
- New `lib/core/widgets/adaptive_shell_scaffold.dart` — bottom nav bar below desktop width, a
  Material `NavigationRail` at/above it. All three portal shells (buyer/seller/admin) now use it,
  which also collapsed three near-duplicate shell implementations into one.
- Buyer product grid and both stat-card dashboards (seller, admin) moved from a fixed
  `crossAxisCount` to extent-based grids.
- Every list/form screen wrapped in `ResponsiveCenter` so content stops stretching edge-to-edge on
  desktop web; auth/checkout/onboarding forms capped at 440–560px and centered.
- `BottomActionBar` and the two bottom-sheet forms (seller catalog listing, subscription switch) cap
  and center their content — deliberately via a `Row`, not `Center`/`Align`: those slots (Scaffold's
  `bottomNavigationBar`, a modal bottom sheet) give bounded-but-loose height, which `Align` fills
  entirely per its own documented sizing rule; a `Row`'s cross axis always hugs its child regardless.
- `ManifestStub` and `EmptyState` got overflow/width guards so they hold up at both very narrow and
  very wide sizes.

### Verification

`flutter analyze` — 0 issues (was 5 infos). `flutter build web --release` — succeeds.

### Changed

23 view/controller files, plus 2 new files (`responsive.dart`, `adaptive_shell_scaffold.dart`) and
`common.dart`/`empty_state.dart`/`manifest_stub.dart`. Nothing under `functions/`, routing, or
Firestore rules touched — out of scope for this pass and overlapping with the pivot work below.

---

## 2026-09-08 — Payment model revision: platform collect-and-disburse

**Status:** revises decision #4 below. **No implementation code written.**

The user explicitly overrode the direct-to-seller recommendation: buyer funds must land at Sellora
first, Sellora pays CJ, keeps a service fee, and disburses the remainder to the seller. Section 04 of
the design document was rewritten to the safe version of that model rather than re-arguing against it.

**New recommendation:** collect through a licensed processor's marketplace/split-payment rails (the
IntaSend/Flutterwave/Paystack pattern behind Jumia, Uber, Airbnb, Stripe Connect) — never a bank or
M-Pesa account Sellora itself controls. The processor stays custodian of funds in transit; Sellora
only instructs the split (CJ cost / platform fee / seller payout) via API. This is lower-risk than
Sellora pooling funds itself, but not risk-free: Sellora is very likely still merchant of record for
refunds/disputes, and the processor will likely require its own aggregator/KYB onboarding.

**A genuine upside surfaced by this change:** the earlier "who fronts CJ" risk (`functions/src/cj.ts`
uses one shared platform CJ credential) is resolved differently now — Sellora holds the buyer's
payment before it owes CJ anything, so a shared CJ account is no longer credit extended to sellers,
just ordinary treasury/reconciliation work. Q2 below was downgraded accordingly.

**Commission model reverses again:** now a live split at settlement (natural, since Sellora holds the
funds) rather than the invoiced-arrears approach the direct-to-seller version required.

**New blocking question, sharper than before (Q3):** does IntaSend actually support marketplace/split
payments with sub-merchant custody? `functions/src/intasend.ts` has no notion of sub-merchants today.
If not, Flutterwave's Multi-Split Payments or Paystack's Split Payments are the named fallbacks — both
operate in Kenya and are built for exactly this.

**Changed in this repo:** the design artifact (`https://claude.ai/code/artifact/0b1113cb-1fc9-4176-9dc7-7df3bfda170f`),
Section 04 and the open-questions Q2/Q3, updated in place. This worklog entry.

**Next step:** unchanged — still gated on Phase 0 sign-off. Q3 (processor capability) is now the
sharper blocker for Phase 4 specifically.

---

## 2026-09-08 — Multi-tenant storefront platform: design

**Status:** design complete, awaiting sign-off. **No implementation code written.**

### Goal

Evolve Sellora from a single shared marketplace into a Shopify-style platform. Each seller gets a
customizable storefront; buyers sign up as customers of *that specific store* rather than as global
Sellora accounts. Sellora keeps the seller dashboard, the shared CJ catalog, and subscription
billing. The marketplace-style shared buyer app is retired.

### Deliverable

Full design document (5 sections + open questions):
<https://claude.ai/code/artifact/0b1113cb-1fc9-4176-9dc7-7df3bfda170f>

It covers account scoping options, the Firestore model and security rules, Flutter Web routing,
payment flow of funds, and a phased migration plan. The summary below is the decision record; the
document holds the reasoning, the comparison tables, and the isolation test checklist.

### Decisions to confirm

| # | Question | Recommendation |
|---|---|---|
| 1 | Buyer account scoping | One Firebase Auth pool + a `stores/{storeId}/customers/{uid}` profile document. **Not** Cloud Identity Platform multi-tenancy — GCIP charges per MAU from the first customer and adds tenant provisioning to the seller signup path, to buy credential isolation when MVP only needs data isolation. Accepted cost: global email uniqueness. |
| 2 | Firestore model | Store-owned data moves under `stores/{storeId}/…` **subcollections**, not flat collections with a `storeId` field — so a missed `.where()` cannot leak across tenants. Admin cross-store views become collection group queries. |
| 3 | Routing | Path routing at `/s/:slug/…` behind an injected `StoreScope`, so subdomains later are a resolver swap. Firebase Hosting cannot do wildcard subdomains — that, not effort, is why paths win for the MVP. |
| 4 | Payments | Each seller connects **their own** IntaSend account; buyer funds never touch Sellora. Sellora's revenue stays the subscription. Platform-collect-and-disburse would make Sellora a payment aggregator (CBK/NPS Act licensing, plus likely a breach of IntaSend's own terms). |
| 5 | Migration | GetX View→Controller→Repository, the `useMockData` dual-implementation split, and Meridian all survive. The buyer portal, `storefrontFeed()`, `UserRole.buyer`, and the global cart singleton do not. |

### Findings from reading the codebase

Three things surfaced during the review that are worth carrying forward regardless of the pivot:

- **`functions/src/cj.ts` uses one platform-level CJ account.** If checkout money goes directly to
  sellers, who pays CJ for the goods? A shared CJ account means Sellora fronts every merchant's
  inventory cost and invoices afterwards — unsecured credit to small sellers, a materially different
  business. Per-seller CJ accounts keep Sellora as pure software. Demo mode hides this entirely.
- **`CheckoutController` prices the cart client-side** and writes an order carrying a client-set
  `total` and `paymentReference`. Already a hole; with real merchant money behind it, it is the whole
  problem. Order creation must move into a Cloud Function that re-prices from listings.
- **`firestore.rules` allows `users` read to any signed-in user.** Today that exposes every user
  document; once buyers are tenants it would be a platform-wide customer list readable by any seller.

### Changed in this repo

- `CLAUDE.md` — new. Architecture orientation for future sessions.
- `WORKLOG.md` — new. This file.

Nothing under `lib/`, `functions/`, or `firestore.rules` was touched.

### Blocked on

1. Is there any live production data? Everything in the repo reads as pre-launch
   (`useMockData = true`, `baseFunctionsUrl` still `YOUR_FIREBASE_PROJECT`,
   `Firebase.initializeApp()` commented out). Confirming this lets the migration skip a backfill.
2. Does each seller bring their own CJ Dropshipping account, or does Sellora hold one shared account?
   Gates the payments phase and determines whether Sellora is extending credit.
3. Has IntaSend confirmed a platform/connect capability for marketplaces? Determines whether sellers
   supply raw API keys (stored in Secret Manager, never Firestore) or Sellora receives scoped
   per-merchant credentials. Ask explicitly whether funds ever transit a Sellora-owned wallet — if
   they do, the custody problem returns.
4. Will one seller ever need more than one store? Cheap now, expensive to retrofit — it changes the
   custom-claim shape and the dashboard navigation.
5. How white-label must this be at launch? If merchants need password-reset emails and sign-in pages
   carrying *their* brand, that is the trigger for Identity Platform, and it belongs in phase 1
   rather than a later migration.

### Next step

Sign off on the five decisions, answer Q1–Q5 above, then start phase 1 — `StoreModel`, `StoreScope`,
slug resolution, path URL strategy, and the `/s/:slug` route tree, all against mock data with two
seeded demo stores. Phases 1–3 need no answers to Q2 or Q3; only the payments phase is gated.
