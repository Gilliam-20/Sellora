# SELLORA — MASTER BUILD PROMPT

You are the lead Flutter architect, senior product engineer, UI/UX designer, backend engineer, and QA engineer responsible for transforming my existing Flutter application **Sellora** into a production-grade, Shopify-class ecommerce SaaS platform.

## 1. PRODUCT VISION

Sellora is a multi-tenant ecommerce SaaS platform inspired by the breadth and usability of Shopify.

The business model is:

1. Sellers create an account.
2. Sellers subscribe to a Sellora monthly plan.
3. Sellers create and customize their own online store.
4. Sellora provides a catalog of products sourced from CJ Dropshipping.
5. Sellers import products into their stores.
6. Sellora helps calculate recommended selling prices and margins.
7. Customers purchase products from seller stores.
8. Sellora processes the order.
9. CJ Dropshipping is used for product sourcing/fulfillment.
10. Sellora charges the seller a **2% service fee on successful product sales**.
11. Sellora also earns recurring subscription revenue.
12. Sellora should be designed for Kenya first but architected for international expansion.

The long-term vision is:

KENYA → AFRICA → GLOBAL

Do NOT build Sellora as merely a Kenyan shopping app.

Build it as a scalable commerce operating system for sellers.

---

# 2. MOST IMPORTANT RULE

DO NOT blindly rewrite the existing project.

First:

* inspect the entire existing codebase
* understand the current architecture
* identify existing working features
* identify reusable components
* identify technical debt
* identify incomplete screens
* identify existing Firebase integration
* identify existing authentication
* identify existing GetX controllers
* identify existing Dio/API services
* identify existing models
* identify existing navigation
* identify existing theme/design system
* identify existing CJ Dropshipping integration
* identify existing Firestore structure
* identify existing storage/cache implementation

Then create a migration plan.

Preserve working code whenever possible.

Refactor only when necessary.

Do not destroy existing functionality merely to introduce a new architecture.

---

# 3. CURRENT TECHNOLOGY STACK

Use the existing project stack unless there is a strong technical reason to change it.

Primary stack:

* Flutter
* Dart
* GetX
* Dio
* Firebase
* Firebase Authentication
* Cloud Firestore
* Firebase Storage
* Firebase Cloud Functions where appropriate
* Firebase Crashlytics
* GetStorage/local storage where already appropriate
* CJ Dropshipping API
* Responsive Flutter UI

The application must support:

* mobile
* tablet
* desktop
* Flutter Web where appropriate

Do not introduce unnecessary packages.

Before adding a package, determine whether the existing Flutter/Dart SDK supports it.

---

# 4. ARCHITECTURE

Use a scalable feature-first architecture.

Recommended structure:

lib/

app/
routes/
theme/
constants/
config/
bindings/
middleware/

core/
errors/
network/
firebase/
storage/
utils/
validators/
responsive/
widgets/

features/

```
authentication/
  data/
  models/
  repositories/
  services/
  controllers/
  views/
  widgets/

onboarding/

dashboard/

products/
  data/
  models/
  repositories/
  services/
  controllers/
  views/
  widgets/

catalog/

product_import/

orders/

customers/

analytics/

discounts/

marketing/

store/

storefront/

themes/

domains/

payments/

subscriptions/

billing/

shipping/

cj_dropshipping/

notifications/

settings/

support/

profile/

admin/
```

Use separation between:

UI
↓
GetX Controller
↓
Repository
↓
Service/API/Firebase
↓
Data source

Controllers must NOT contain large amounts of Firebase/Dio business logic.

Repositories should abstract data access.

Services should handle external integrations.

Models should represent domain data.

---

# 5. MULTI-TENANT ARCHITECTURE

This is extremely important.

Sellora is a SaaS platform.

One Sellora user may own one or multiple stores depending on subscription plan.

Every store-owned resource must be associated with:

* ownerId
* storeId

Do NOT create a flat database where all sellers share ambiguous product/order/customer data.

Recommended conceptual structure:

users/{userId}

stores/{storeId}

stores/{storeId}/products/{productId}

stores/{storeId}/orders/{orderId}

stores/{storeId}/customers/{customerId}

stores/{storeId}/discounts/{discountId}

stores/{storeId}/collections/{collectionId}

stores/{storeId}/analytics/{document}

stores/{storeId}/settings/{document}

stores/{storeId}/domains/{domainId}

subscriptions/{subscriptionId}

cjProducts/{cjProductId}

platformOrders/{orderId}

payments/{paymentId}

notifications/{notificationId}

Use appropriate references and indexes.

Design Firestore rules around ownership.

A seller must NEVER be able to read or modify another seller's:

* products
* orders
* customers
* store settings
* payments
* analytics
* subscription information
* private business information

---

# 6. SELLORA DESIGN SYSTEM

Create a professional design system before building all screens.

Sellora must NOT look like a random collection of Flutter screens.

Create reusable:

* AppScaffold
* ResponsiveScaffold
* Sidebar
* NavigationRail
* MobileNavigation
* TopBar
* PageHeader
* SectionHeader
* StatCard
* MetricCard
* DataTable
* ResponsiveDataTable
* SearchField
* FilterBar
* FilterChip
* PrimaryButton
* SecondaryButton
* DestructiveButton
* IconButton
* EmptyState
* LoadingState
* ErrorState
* ProductCard
* ProductGrid
* ProductListTile
* OrderStatusBadge
* PaymentStatusBadge
* StoreStatusBadge
* ConfirmationDialog
* BottomSheet
* AppSnackbar
* AppDrawer
* Pagination
* ImageUploader
* ProductImageGallery
* PriceField
* CurrencyField
* FormSection
* SettingsSection

Every reusable component must be responsive.

---

# 7. SELLORA VISUAL IDENTITY

Do not copy Shopify branding.

Sellora should have its own professional identity.

Primary brand color:

#FFC107

Use white and neutral colors as supporting colors.

For dark interfaces, use:

#303F9F

Create:

* light theme
* dark theme
* consistent typography
* consistent spacing
* consistent corner radius
* consistent elevation
* consistent iconography
* accessible contrast

The UI should feel:

* modern
* premium
* clean
* trustworthy
* simple
* business-focused
* professional

Avoid excessive gradients and unnecessary animations.

---

# 8. MAIN SELLER APPLICATION NAVIGATION

Create a Shopify-class seller admin experience.

Desktop sidebar:

1. Home
2. Orders
3. Products
4. Customers
5. Analytics
6. Marketing
7. Discounts
8. Online Store
9. Sales Channels
10. Apps / Integrations
11. Settings

Top bar:

* global search
* notifications
* store selector
* help/support
* account menu

Mobile:

Use a responsive navigation structure appropriate for small screens.

Do NOT simply squeeze desktop UI onto mobile.

---

# 9. DASHBOARD / HOME

Create a professional seller dashboard.

Display:

* Total sales
* Orders
* Average order value
* Products
* Customers
* Conversion rate
* Net sales
* Gross sales
* Refunds
* Pending orders
* Fulfillment status
* Top products
* Recent orders
* Sales chart
* Customer acquisition
* Store health
* Subscription status

Allow date ranges:

* Today
* Yesterday
* Last 7 days
* Last 30 days
* Last 90 days
* This year
* Custom

Include useful empty states for new sellers.

A new seller should receive a guided setup checklist:

[ ] Create store
[ ] Choose theme
[ ] Add domain
[ ] Import first product
[ ] Configure payment
[ ] Configure shipping
[ ] Publish store
[ ] Make first sale

---

# 10. PRODUCT SYSTEM

Build a complete product-management system.

Product list:

* search
* filters
* sorting
* pagination
* bulk selection
* bulk edit
* bulk delete
* product status
* inventory
* price
* compare-at price
* SKU
* vendor
* product type
* collections
* tags

Product creation/editing:

* title
* description
* images
* videos if supported
* pricing
* cost
* profit
* margin
* inventory
* SKU
* barcode
* variants
* options
* shipping
* SEO
* organization
* tags
* collections
* product status

Statuses:

* Draft
* Active
* Archived

---

# 11. CJ DROPSHIPPING CATALOG

This is one of Sellora's core differentiators.

Create a dedicated:

## Product Marketplace / CJ Catalog

Features:

* product search
* categories
* trending products
* recommended products
* product details
* CJ price
* shipping origin
* shipping destination
* shipping methods
* estimated delivery
* product variants
* supplier information
* images
* videos where available
* inventory availability

Seller can:

**Add to Store**

Before importing, show:

CJ cost
+
Shipping
+
Sellora/payment costs where appropriate
+
Recommended margin
==================

Recommended selling price

---

# 12. SMART PRICING ENGINE

Build a pricing engine.

Do NOT hard-code product prices.

Store configurable pricing rules.

Example:

Product cost:
KSh 1,000

Shipping:
KSh 300

Total landed cost:
KSh 1,300

Seller chooses target margin.

Example:

30%

System calculates recommended selling price.

Display:

Product cost
Shipping
Estimated fees
Recommended selling price
Estimated profit
Profit margin

Allow sellers to override the recommended price.

Admin should be able to configure default pricing rules.

The pricing engine must support:

* KES
* USD
* GBP
* EUR
* other currencies later

Do not assume KES everywhere.

---

# 13. PRODUCT IMPORT WORKFLOW

Seller clicks:

Import Product

Show an import editor.

Allow:

* change title
* edit description
* select images
* remove images
* edit variants
* edit price
* set margin
* edit SKU
* add tags
* assign collection
* optimize SEO
* publish immediately
* save as draft

Create an efficient:

CJ → Sellora Store

workflow.

---

# 14. ORDERS

Build a complete order management system.

Orders page:

* order number
* customer
* date
* total
* payment status
* fulfillment status
* items
* shipping
* channel

Filters:

* paid
* unpaid
* pending
* processing
* fulfilled
* partially fulfilled
* cancelled
* refunded

Order detail:

* customer information
* products
* variants
* payment
* shipping
* fulfillment
* timeline
* notes
* refund
* cancellation
* CJ fulfillment status

---

# 15. SUCCESSFUL ORDER SERVICE FEE

Sellora charges:

## 2% service fee per successful product sale

Apply this to the product/order subtotal.

Do NOT automatically charge the 2% on:

* shipping
* taxes

unless explicitly configured.

Example:

Product subtotal:
KSh 40,000

Sellora service fee:
2%

Sellora fee:
KSh 800

Record this transaction separately.

Create:

platformFee
serviceFeeRate
serviceFeeAmount
sellerRevenue
paymentFee
currency

Never modify historical fees when the admin changes the fee percentage.

The fee used for an order must be stored with that order.

---

# 16. SUBSCRIPTION SYSTEM

Initial plans:

STARTER

KSh 999/month

GROWTH

KSh 2,499/month

PRO

KSh 4,999/month

Create a subscription architecture where plans are configurable from the admin dashboard.

Do NOT hard-code plan limits throughout the application.

Plan configuration should include:

* price
* currency
* product limit
* order limit
* store limit
* custom domain
* analytics
* advanced features
* support level
* feature flags

Initial suggested limits:

Starter:

* 50 products
* 100 orders/month
* 1 store

Growth:

* 500 products
* 1,000 orders/month
* 3 stores

Pro:

* unlimited products
* unlimited orders
* 10 stores

These values must be configurable.

---

# 17. BILLING PAGE

Create a complete billing experience.

Show:

* current plan
* subscription status
* renewal date
* payment method
* billing history
* invoices
* usage
* product limit
* order usage
* store usage

Actions:

* upgrade
* downgrade
* cancel
* resume
* update payment method

Show upgrade benefits clearly.

---

# 18. STORE BUILDER

Create a professional no-code storefront builder.

Seller can customize:

* logo
* favicon
* colors
* typography
* homepage
* announcement bar
* navigation
* hero section
* featured products
* collections
* banners
* testimonials
* newsletter
* footer
* social links

Use reusable section-based architecture.

Concept:

Store
→ Theme
→ Sections
→ Blocks
→ Settings

Do not hard-code one storefront layout.

---

# 19. THEME SYSTEM

Create a theme architecture.

Theme model:

Theme

* id
* name
* version
* thumbnail
* sections
* settings
* typography
* colors

Allow multiple themes.

Initial themes:

* Minimal
* Modern
* Fashion
* Electronics
* General Store

The storefront renderer should dynamically render sections based on configuration.

---

# 20. STOREFRONT

Create a customer-facing storefront.

Pages:

* Home
* Shop
* Collections
* Product detail
* Search
* Cart
* Checkout
* Order confirmation
* Customer account
* Order history
* Contact
* About
* Privacy
* Terms
* Shipping policy
* Refund policy

Storefront must be independent from the seller admin interface.

---

# 21. CUSTOMER EXPERIENCE

Customer should be able to:

* browse products
* search
* filter
* sort
* view product
* choose variants
* add to cart
* update quantity
* checkout
* pay
* receive order confirmation
* track order
* create account
* view orders

Make checkout as simple as possible.

---

# 22. PAYMENTS

Design payment architecture as a provider abstraction.

Example:

PaymentProvider

Implement providers independently.

Kenya-first:

* M-Pesa
* Visa
* Mastercard

International:

* international card processing
* additional providers later

Do NOT tightly couple the entire application to IntaSend.

Payment architecture should allow providers to be added/replaced.

Never store raw card details.

Use provider-hosted/tokenized checkout where required.

Payment states:

* pending
* authorized
* paid
* failed
* refunded
* partially_refunded
* cancelled

---

# 23. SHIPPING

Create shipping architecture.

Seller settings:

* shipping zones
* shipping rates
* free shipping
* flat rate
* carrier-based shipping
* estimated delivery

Product/shipping logic should support:

Kenya
Africa
USA
UK
Global

Do not hard-code Kenya into the shipping engine.

---

# 24. CUSTOMERS

Customer management:

* customer list
* search
* filters
* customer profile
* order history
* total spent
* number of orders
* average order value
* customer tags
* notes
* marketing consent

---

# 25. ANALYTICS

Create:

Overview
Sales
Orders
Products
Customers
Marketing

Metrics:

* sales
* orders
* average order value
* conversion rate
* returning customers
* new customers
* top products
* top collections
* sales by country
* sales by device
* sales over time

Use clean charts.

Do not overload the dashboard.

---

# 26. MARKETING

Create marketing tools:

* discount codes
* automatic discounts
* campaigns
* abandoned cart
* email marketing architecture
* social sharing
* product promotion
* SEO tools

AI-ready architecture should allow future features such as:

* AI product descriptions
* AI ad copy
* AI social posts
* AI SEO optimization
* AI product recommendations

---

# 27. DISCOUNTS

Support:

* percentage discount
* fixed amount
* free shipping
* minimum purchase
* specific products
* collections
* customer groups
* start/end dates
* usage limits

---

# 28. SEO

Store-level SEO:

* meta title
* meta description
* social image
* favicon
* robots configuration
* sitemap architecture

Product SEO:

* SEO title
* meta description
* URL slug

Collection SEO:

same system.

---

# 29. DOMAINS

Create domain management.

Support architecture for:

* Sellora subdomain
* custom domain
* domain verification
* DNS instructions
* SSL status

Example:

mystore.sellora.com

Later:

[www.mystore.com](http://www.mystore.com)

---

# 30. SETTINGS

Create comprehensive settings.

Settings sections:

Store details
Payments
Checkout
Shipping
Taxes
Domains
Notifications
Customer accounts
Marketing
SEO
Policies
Staff/accounts
Billing
Security
Integrations

---

# 31. NOTIFICATIONS

Create notification center.

Events:

* new order
* payment received
* order fulfilled
* order cancelled
* refund
* subscription renewal
* subscription failed
* low inventory
* product imported
* CJ fulfillment update

Use a centralized notification model.

---

# 32. AUTHENTICATION

Support:

* email/password
* Google Sign-In where configured
* password reset
* email verification
* session handling
* logout

After authentication:

Determine:

* user
* seller profile
* subscription
* stores
* onboarding state

Then route appropriately.

---

# 33. ONBOARDING

New seller onboarding:

1. Welcome
2. Business/store name
3. Store category
4. Country
5. Currency
6. Choose plan
7. Create first store
8. Import first product
9. Configure payment
10. Configure shipping
11. Publish store

Make onboarding easy enough for someone who has never run an online store.

---

# 34. ADMIN PANEL

Build a separate platform-admin architecture.

Admin should be able to manage:

* users
* sellers
* stores
* subscriptions
* plans
* products
* CJ catalog
* orders
* platform fees
* payments
* refunds
* categories
* themes
* coupons
* reports
* support
* feature flags
* pricing rules
* platform settings

Admin analytics:

* total sellers
* active sellers
* new sellers
* churn
* MRR
* ARR
* GMV
* platform service-fee revenue
* subscription revenue
* orders
* customers
* conversion

---

# 35. PLATFORM FINANCIAL MODEL

Track separately:

Seller GMV

Sellora subscription revenue

Sellora service-fee revenue

Payment processing fees

Refunds

Chargebacks

CJ product cost

CJ shipping cost

Seller revenue

Platform revenue

Do NOT confuse seller GMV with Sellora revenue.

Example:

950 sellers

Average seller sales:
KSh 40,000/month

GMV:

KSh 38,000,000

2% Sellora service fee:

KSh 760,000

Subscription revenue using current plans:

Starter:
600 × KSh 999 = KSh 599,400

Growth:
300 × KSh 2,499 = KSh 749,700

Pro:
50 × KSh 4,999 = KSh 249,950

Total subscription revenue:

KSh 1,599,050

Total platform revenue:

KSh 2,359,050/month

This must be represented correctly in analytics.

---

# 36. CURRENCY ARCHITECTURE

Never assume one currency.

Every monetary model should contain:

amount
currency

Support:

KES
USD
GBP
EUR

Build currency conversion as a service.

Do not use floating-point arithmetic for financial calculations where avoidable.

Use integer minor units or a safe decimal strategy.

---

# 37. FIREBASE SECURITY

Implement strict Firestore rules.

Principles:

* authenticated users only where required
* store ownership verification
* role-based admin access
* seller isolation
* customer access limited to their own records
* server-side validation for financial operations
* clients must not be trusted with platform fee calculations
* subscription state should be validated server-side
* payment state must come from trusted payment callbacks/webhooks
* CJ credentials/tokens must never be exposed in the Flutter application

CJ credentials must be server-side.

---

# 38. CJ API SECURITY

Do NOT put sensitive CJ API credentials directly into Flutter.

Preferred architecture:

Flutter
↓
Sellora backend / Cloud Functions
↓
CJ Dropshipping API

Store secrets securely.

Implement:

* token management
* refresh logic where required
* rate limiting
* retry logic
* timeout handling
* logging
* error handling
* caching

---

# 39. NETWORK HANDLING

Improve the existing NetworkManager.

The app should handle:

online
offline
reconnecting
connection restored

Do not permanently redirect the user to an offline screen if the connection is temporarily unavailable.

When connectivity returns:

* retry appropriate operations
* refresh user data
* refresh store state
* refresh subscription
* refresh dashboard data

Avoid infinite retry loops.

---

# 40. ERROR HANDLING

Create centralized errors.

Handle:

* network errors
* Firebase errors
* authentication errors
* payment errors
* CJ errors
* validation errors
* permission errors
* unexpected errors

Give users useful messages.

Never expose internal stack traces to customers.

---

# 41. LOADING STATES

Every async screen must have:

* loading
* success
* empty
* error

Do not show blank screens while data loads.

Use skeleton loaders where appropriate.

---

# 42. RESPONSIVE DESIGN

Desktop:

* sidebar
* top navigation
* multi-column layouts
* data tables

Tablet:

* compact navigation
* adaptive grids
* responsive forms

Mobile:

* bottom navigation or drawer where appropriate
* stacked layouts
* mobile-friendly tables
* bottom sheets
* large touch targets

Use LayoutBuilder / MediaQuery / responsive utilities appropriately.

Do NOT create separate duplicated screens unnecessarily.

---

# 43. PERFORMANCE

Optimize for scale.

Avoid:

* unnecessary Firestore reads
* unnecessary rebuilds
* huge widget trees
* loading entire collections into memory
* unbounded queries
* duplicate API calls

Use:

* pagination
* caching
* lazy loading
* query limits
* indexes
* debouncing
* image optimization
* efficient GetX updates

---

# 44. DATABASE DESIGN

Create proper Firestore indexes.

Every important collection should have clear ownership and query strategy.

Document:

* collection purpose
* fields
* indexes
* security rules
* relationships

Do not create random Firestore documents just to make a screen work.

---

# 45. GETX RULES

Use GetX consistently.

Controllers should:

* expose observable state
* call repositories
* manage UI state
* coordinate workflows

Do not place huge amounts of business logic in widgets.

Avoid unnecessary Bindings.

The project should support straightforward dependency management with Get.put/Get.find where appropriate, while preventing duplicate controller instances.

---

# 46. ROUTING

Create centralized routes.

Example:

/login
/register
/onboarding
/home
/orders
/orders/:id
/products
/products/create
/products/:id
/catalog
/catalog/:id
/customers
/analytics
/marketing
/discounts
/store
/store/theme
/store/navigation
/settings
/billing

Storefront routes should be separate from seller-admin routes.

Use middleware for:

* authentication
* subscription
* admin
* onboarding

---

# 47. ACCESS CONTROL

Roles:

customer
seller
admin
support

Potential future roles:

staff
manager

Do not rely only on UI hiding.

Enforce authorization at backend/database level.

---

# 48. UX PRINCIPLES

Follow these principles throughout the entire application:

* simple
* obvious
* fast
* consistent
* minimal clicks
* clear hierarchy
* useful defaults
* helpful empty states
* meaningful feedback
* professional forms
* accessible controls

A beginner should understand the product without reading documentation.

---

# 49. IMPLEMENTATION STRATEGY

DO NOT attempt to build everything in one giant uncontrolled change.

Work in phases.

## PHASE 0 — AUDIT

Before modifying code:

1. inspect repository
2. inspect pubspec.yaml
3. inspect architecture
4. inspect routes
5. inspect Firebase
6. inspect Firestore models
7. inspect controllers
8. inspect API services
9. inspect CJ integration
10. inspect existing UI
11. identify broken features
12. identify duplicated code

Then produce:

SELLORA_ARCHITECTURE.md

and

SELLORA_IMPLEMENTATION_PLAN.md

Do not start massive feature implementation until this audit is complete.

---

# PHASE 1 — FOUNDATION

Implement:

* design system
* themes
* responsive framework
* navigation
* routing
* error handling
* loading states
* shared components
* architecture cleanup

Do not build advanced features yet.

---

# PHASE 2 — AUTH + SELLER ONBOARDING

Implement:

* authentication
* profile
* seller account
* subscription state
* onboarding
* store creation

---

# PHASE 3 — BILLING

Implement:

* Starter
* Growth
* Pro
* subscription UI
* billing history
* usage limits
* plan upgrades/downgrades

Make plan configuration data-driven.

---

# PHASE 4 — PRODUCT CATALOG + CJ

Implement:

* CJ catalog
* search
* categories
* product details
* shipping calculations
* smart pricing
* product import
* product synchronization

This is a major milestone.

---

# PHASE 5 — SELLER PRODUCT MANAGEMENT

Implement:

* products
* variants
* collections
* inventory
* pricing
* SEO
* bulk operations

---

# PHASE 6 — STORE BUILDER

Implement:

* themes
* sections
* blocks
* navigation
* homepage
* storefront renderer
* preview
* publish

---

# PHASE 7 — CUSTOMER STOREFRONT

Implement:

* storefront
* search
* collections
* product pages
* cart
* checkout
* customer account
* order tracking

---

# PHASE 8 — PAYMENTS + ORDERS

Implement:

* payment provider abstraction
* M-Pesa
* cards
* payment callbacks
* order creation
* order state machine
* refunds
* service fee
* CJ fulfillment

---

# PHASE 9 — ANALYTICS + MARKETING

Implement:

* dashboard
* analytics
* discounts
* marketing
* customer analytics
* sales analytics

---

# PHASE 10 — ADMIN

Implement complete platform administration.

---

# PHASE 11 — INTERNATIONALIZATION

Implement:

* multi-currency
* country configuration
* shipping zones
* international payment architecture
* localization readiness

---

# PHASE 12 — SECURITY + PRODUCTION

Audit:

* Firestore rules
* API security
* authentication
* payment security
* secrets
* rate limiting
* permissions
* data validation
* error handling
* performance

---

# 50. DEVELOPMENT RULE

At the end of EVERY phase:

1. Run flutter analyze.
2. Run tests.
3. Fix errors.
4. Verify affected screens.
5. Verify routing.
6. Verify Firebase operations.
7. Verify responsive layouts.
8. Document what changed.
9. Do not continue if the previous phase is broken.

Never leave the project in a knowingly broken state.

---

# 51. UI IMPLEMENTATION RULE

Before creating a new screen:

1. Define its purpose.
2. Define its user actions.
3. Define its data requirements.
4. Define loading state.
5. Define empty state.
6. Define error state.
7. Define desktop layout.
8. Define tablet layout.
9. Define mobile layout.
10. Define reusable components.

Then implement it.

---

# 52. SHOPIFY REFERENCE RULE

Use Shopify's current product experience as inspiration for:

* information architecture
* merchant workflows
* dashboard organization
* ecommerce terminology
* usability patterns
* feature completeness
* responsive behavior

But:

DO NOT copy Shopify's:

* branding
* logos
* proprietary assets
* exact visual design
* copyrighted text
* source code

Sellora must have its own visual identity.

---

# 53. FUTURE-READY FEATURES

Architect the system so these can be added later without major rewrites:

* AI store builder
* AI product descriptions
* AI advertisements
* AI product recommendations
* abandoned-cart recovery
* email campaigns
* SMS
* WhatsApp commerce
* affiliate marketing
* influencer tracking
* seller staff accounts
* multi-store management
* advanced shipping
* tax automation
* additional payment gateways
* additional supplier integrations
* Amazon-like marketplace capabilities
* mobile seller app
* public Sellora API

---

# 54. WHAT NOT TO DO

Do NOT:

* rebuild the entire application blindly
* hard-code business rules
* hard-code subscription prices
* hard-code currencies
* hard-code payment providers
* expose API secrets
* put all logic inside widgets
* create giant controllers
* create giant files
* duplicate mobile and desktop screens unnecessarily
* ignore Firestore security
* ignore empty states
* ignore error states
* create fake functionality
* use placeholder buttons that do nothing
* claim a feature works when it doesn't
* break existing working functionality

---

# 55. DEFINITION OF DONE

A feature is NOT complete just because its UI exists.

A feature is complete only when:

UI
+
State management
+
Validation
+
Repository
+
Backend
+
Database
+
Security
+
Error handling
+
Loading state
+
Empty state
+
Responsive layout
+
Testing

are implemented where applicable.

---

# 56. FIRST TASK

Do NOT immediately start coding all the features above.

Your FIRST task is:

## AUDIT THE EXISTING SELLORA PROJECT.

Inspect the complete project.

Then report:

### A. Existing architecture

### B. Existing features

### C. Existing screens

### D. Existing Firebase structure

### E. Existing Firestore rules

### F. Existing CJ integration

### G. Existing payment integration

### H. Existing GetX architecture

### I. Existing navigation

### J. Existing reusable widgets

### K. Technical debt

### L. Missing features

### M. Recommended architecture

### N. Exact implementation phases

### O. Files that should be modified

### P. Files that should be created

Do not make massive changes during the audit.

After the audit, begin **PHASE 1**.

Work incrementally and keep the application compiling throughout the entire transformation.

The objective is not simply to create many screens.

The objective is to transform the existing Sellora codebase into a **production-ready, scalable, multi-tenant, Shopify-class commerce SaaS platform with its own identity.**
