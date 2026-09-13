import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/routes/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_metrics.dart';
import '../../app/theme/app_typography.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/manifest_stub.dart';
import '../../data/models/subscription_plan_model.dart';
import 'marketing_controller.dart';

/// Sellora's public marketing/landing page — the front door for a web
/// visitor who isn't signed in yet. Every call to action here hands off
/// into the existing auth flow (role select / sign in) rather than
/// inventing a parallel one.
class MarketingView extends GetView<MarketingController> {
  MarketingView({super.key});

  final GlobalKey _flowSectionKey = GlobalKey();
  final GlobalKey _pricingSectionKey = GlobalKey();

  void _scrollTo(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(context,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  void _goToSignIn() => Get.toNamed(Routes.login);

  void _goToSellerSignUp() => Get.toNamed(Routes.login);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _Nav(
              onSignIn: _goToSignIn,
              onStart: _goToSellerSignUp,
              onSeePricing: () => _scrollTo(_pricingSectionKey),
            ),
            _Hero(
              onStart: _goToSellerSignUp,
              onSeeHowItWorks: () => _scrollTo(_flowSectionKey),
            ),
            _Flow(key: _flowSectionKey),
            const _Capabilities(),
            const _Infra(),
            _Pricing(key: _pricingSectionKey, onSelectPlan: (_) => _goToSellerSignUp()),
            const _Faq(),
            _FinalCta(onStart: _goToSellerSignUp),
            _Footer(
              onSignIn: _goToSignIn,
              onStart: _goToSellerSignUp,
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps section content in a full-bleed colored band with centered,
/// width-capped content — the layout rule this whole page follows so
/// nothing stretches edge-to-edge on a wide browser window.
Widget _section(
  BuildContext context, {
  required Widget child,
  Color background = AppColors.cloud,
  double maxWidth = 1120,
}) {
  return Container(
    width: double.infinity,
    color: background,
    padding: EdgeInsets.symmetric(
      horizontal: context.pageHorizontalPadding,
      vertical: AppSpacing.xxl,
    ),
    child: ResponsiveCenter(maxWidth: maxWidth, child: child),
  );
}

TextStyle? _eyebrowStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .labelMedium
    ?.copyWith(color: AppColors.cargoNavy);

TextStyle? _headingStyle(BuildContext context, {Color color = AppColors.ink}) =>
    Theme.of(context).textTheme.displaySmall?.copyWith(color: color);

/// CSS-grid-style "auto-fit, minmax" layout: as many equal-width columns
/// as fit the available width without any tile shrinking below
/// [minTileWidth], wrapping to further rows as needed.
class _AutoGrid extends StatelessWidget {
  const _AutoGrid({required this.children, this.minTileWidth = 240});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final columns = (maxWidth / (minTileWidth + AppSpacing.md))
          .floor()
          .clamp(1, children.length);
      final tileWidth =
          (maxWidth - AppSpacing.md * (columns - 1)) / columns;
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final child in children) SizedBox(width: tileWidth, child: child),
        ],
      );
    });
  }
}

class _Nav extends StatelessWidget {
  const _Nav(
      {required this.onSignIn,
      required this.onStart,
      required this.onSeePricing});
  final VoidCallback onSignIn;
  final VoidCallback onStart;
  final VoidCallback onSeePricing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.cargoNavy,
      padding: EdgeInsets.symmetric(
          horizontal: context.pageHorizontalPadding, vertical: AppSpacing.md),
      child: ResponsiveCenter(
        maxWidth: 1120,
        child: Row(
          children: [
            Text('Sellora',
                style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cloud)),
            const Spacer(),
            TextButton(
              onPressed: onSeePricing,
              style: TextButton.styleFrom(foregroundColor: AppColors.cloud),
              child: const Text('Pricing'),
            ),
            TextButton(
              onPressed: onSignIn,
              style: TextButton.styleFrom(foregroundColor: AppColors.cloud),
              child: const Text('Sign in'),
            ),
            const SizedBox(width: AppSpacing.sm),
            ElevatedButton(
                onPressed: onStart, child: const Text('Start selling')),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onStart, required this.onSeeHowItWorks});
  final VoidCallback onStart;
  final VoidCallback onSeeHowItWorks;

  @override
  Widget build(BuildContext context) {
    final headlineSize = ResponsiveContext(context)
        .responsiveValue(mobile: 32.0, tablet: 44.0, desktop: 56.0);
    final isWide = context.isWide;

    return Container(
      width: double.infinity,
      color: AppColors.cargoNavy,
      padding: EdgeInsets.symmetric(
          horizontal: context.pageHorizontalPadding, vertical: AppSpacing.xxl),
      child: ResponsiveCenter(
        maxWidth: 1120,
        child: Column(
          children: [
            const StatusBadge(
                label: 'New — CJ Dropshipping live sync',
                color: AppColors.manifestGold),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'One catalog, sourced globally. Sell it as your own store.',
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: headlineSize,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                height: 1.1,
                color: AppColors.cloud,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: const Text(
                'Subscribe monthly, list products from Sellora\'s shared '
                'catalog at your own price, and get paid on every order — '
                'checkout, fulfillment and payouts, all inside Sellora.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.slateLight, fontSize: 16, height: 1.4),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ElevatedButton(
                    onPressed: onStart,
                    child: const Text('Start selling today')),
                OutlinedButton(
                  onPressed: onSeeHowItWorks,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.cloud,
                      side: const BorderSide(color: AppColors.slateLight)),
                  child: const Text('See how it works'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 920),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.cloud,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: isWide
                  ? const Row(children: [
                      Expanded(
                          child: ManifestStatCard(
                              label: 'Revenue this month',
                              value: 'KSh 84,200',
                              accentColor: AppColors.manifestGold)),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                          child: ManifestStatCard(
                              label: 'Active listings',
                              value: '24',
                              accentColor: AppColors.horizonTeal)),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                          child: ManifestStatCard(
                              label: 'Orders to fulfill',
                              value: '6',
                              accentColor: AppColors.info)),
                    ])
                  : const Column(children: [
                      ManifestStatCard(
                          label: 'Revenue this month',
                          value: 'KSh 84,200',
                          accentColor: AppColors.manifestGold),
                      SizedBox(height: AppSpacing.md),
                      ManifestStatCard(
                          label: 'Active listings',
                          value: '24',
                          accentColor: AppColors.horizonTeal),
                      SizedBox(height: AppSpacing.md),
                      ManifestStatCard(
                          label: 'Orders to fulfill',
                          value: '6',
                          accentColor: AppColors.info),
                    ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowStep {
  const _FlowStep(this.code, this.title, this.description);
  final String code;
  final String title;
  final String description;
}

const _flowSteps = [
  _FlowStep('01', 'Subscribe & set up your store',
      'Pick a plan and name your storefront. You\'re live in minutes — no developer required.'),
  _FlowStep('02', 'List the products',
      'Pull products from Sellora\'s shared catalog, keep the photos and variants, and set your own price on top of the supplier cost.'),
  _FlowStep('03', 'Buyers discover & pay',
      'Your listings show up in the marketplace feed. Buyers check out with M-Pesa or card through IntaSend.'),
  _FlowStep('04', 'Sellora fulfills & you get paid',
      'Every order is re-priced and confirmed server-side, then pushed to the supplier for fulfillment — your payout follows on schedule.'),
];

class _Flow extends StatelessWidget {
  const _Flow({super.key});

  @override
  Widget build(BuildContext context) {
    return _section(
      context,
      child: Column(
        children: [
          Text('How it flows', style: _eyebrowStyle(context)),
          const SizedBox(height: AppSpacing.sm),
          Text('From supplier to a buyer\'s door.',
              style: _headingStyle(context), textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xl),
          _AutoGrid(
            minTileWidth: 220,
            children: [
              for (final step in _flowSteps)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.cloud,
                    border: Border.all(color: AppColors.hairline),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.code,
                          style: AppTypography.manifestCode(
                              color: AppColors.manifestGoldDeep)),
                      const SizedBox(height: AppSpacing.sm),
                      Text(step.title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(step.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.slate)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CapabilityItem {
  const _CapabilityItem(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;
}

const _capabilities = [
  _CapabilityItem(Icons.travel_explore_outlined, 'A shared product catalog',
      'Search and list products with real photos, variants and supplier cost — set your margin once and it applies everywhere.'),
  _CapabilityItem(Icons.storefront_outlined, 'Three role-based portals',
      'Buyer, seller and admin experiences behind one sign-in, each with only the navigation and tools that role needs.'),
  _CapabilityItem(Icons.payments_outlined, 'M-Pesa & card checkout',
      'Buyers pay through IntaSend — an M-Pesa STK push or hosted card checkout — settled to your payout schedule.'),
  _CapabilityItem(Icons.verified_outlined, 'Server-verified orders',
      'Every order is re-priced and confirmed on the server before it\'s marked paid — nothing is trusted from the client.'),
  _CapabilityItem(Icons.dashboard_outlined, 'A seller dashboard that matters',
      'Revenue, active listings and orders waiting on you, plus the recent-orders feed you\'ll actually check daily.'),
  _CapabilityItem(Icons.receipt_long_outlined, 'Plans with a real limit',
      'Starter, Growth and Scale tiers, each with a listing limit and commission rate that\'s clear up front.'),
];

class _Capabilities extends StatelessWidget {
  const _Capabilities();

  @override
  Widget build(BuildContext context) {
    return _section(
      context,
      background: AppColors.mist,
      child: Column(
        children: [
          Text('Operational capabilities', style: _eyebrowStyle(context)),
          const SizedBox(height: AppSpacing.sm),
          Text('Everything a merchant needs. Day one.',
              style: _headingStyle(context), textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xl),
          _AutoGrid(
            minTileWidth: 250,
            children: [
              for (final item in _capabilities)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.cloud,
                    border: Border.all(color: AppColors.hairline),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.icon, color: AppColors.cargoNavy, size: 26),
                      const SizedBox(height: AppSpacing.sm + 2),
                      Text(item.title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(item.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.slate)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfraPoint {
  const _InfraPoint(this.title, this.description);
  final String title;
  final String description;
}

class _Infra extends StatelessWidget {
  const _Infra();

  @override
  Widget build(BuildContext context) {
    final feePercent =
        (AppConstants.platformServiceFeeRate * 100).toStringAsFixed(0);
    final points = [
      const _InfraPoint('Role-scoped by design',
          'Buyer, seller and admin routes are middleware-guarded — no portal leaks into another.'),
      const _InfraPoint('Server-verified orders',
          'Every order is re-priced and payment-confirmed server-side before it\'s marked paid.'),
      const _InfraPoint('Built for scale',
          'One Flutter codebase powers the web and Android experience from a single source.'),
      _InfraPoint('A transparent platform fee',
          'Sellora takes a $feePercent% fee on the order subtotal — calculated and confirmed server-side, never on shipping or tax.'),
    ];

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Infrastructure', style: _eyebrowStyle(context)),
        const SizedBox(height: AppSpacing.sm),
        Text('Built like a platform, not a plugin.',
            style: _headingStyle(context)),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Every Sellora store runs on the same hardened, multi-tenant '
          'infrastructure — real security rules and real operational '
          'primitives, not a bundle of glued-together plugins.',
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: AppColors.slate),
        ),
      ],
    );

    final bullets = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.horizonTealDeep, size: 22),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(point.title,
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(point.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.slate)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return _section(
      context,
      child: context.isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: text),
                const SizedBox(width: AppSpacing.xxl),
                Expanded(child: bullets),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: AppSpacing.xl),
                bullets,
              ],
            ),
    );
  }
}

class _Pricing extends StatelessWidget {
  const _Pricing({super.key, required this.onSelectPlan});
  final ValueChanged<SubscriptionPlanModel> onSelectPlan;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketingController>();
    return _section(
      context,
      child: Column(
        children: [
          Text('Pricing', style: _eyebrowStyle(context)),
          const SizedBox(height: AppSpacing.sm),
          Text('Simple pricing. No surprises.',
              style: _headingStyle(context), textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xl),
          Obx(() {
            if (controller.isLoading.value) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: SelloraLoader(),
              );
            }
            if (controller.plans.isEmpty) return const SizedBox.shrink();
            return _AutoGrid(
              minTileWidth: 260,
              children: [
                for (final plan in controller.plans)
                  _PlanCard(plan: plan, onSelect: () => onSelectPlan(plan)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onSelect});
  final SubscriptionPlanModel plan;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: plan.isPopular ? AppColors.manifestGold : AppColors.hairline,
          width: plan.isPopular ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (plan.isPopular) ...[
            const StatusBadge(
                label: 'Most popular', color: AppColors.manifestGoldDeep),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(plan.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(Formatters.currency(plan.priceKes, code: 'KES'),
                  style: AppTypography.price(size: 26)),
              Text(' /mo',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.slate)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final perk in plan.perks)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check,
                      size: 16, color: AppColors.horizonTealDeep),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text(perk,
                          style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: plan.isPopular
                ? ElevatedButton(
                    onPressed: onSelect, child: const Text('Start selling'))
                : OutlinedButton(
                    onPressed: onSelect, child: const Text('Start selling')),
          ),
        ],
      ),
    );
  }
}

class _FaqItem {
  const _FaqItem(this.question, this.answer);
  final String question;
  final String answer;
}

class _Faq extends StatelessWidget {
  const _Faq();

  @override
  Widget build(BuildContext context) {
    final feePercent =
        (AppConstants.platformServiceFeeRate * 100).toStringAsFixed(0);
    final items = [
      const _FaqItem(
        'Do I need my own CJ Dropshipping account?',
        'No. Sellora sources from one shared CJ Dropshipping catalog — you '
            'pick products from it and set your own price on top of the '
            'supplier cost.',
      ),
      _FaqItem(
        'What does Sellora charge?',
        'Your monthly plan, plus a $feePercent% fee on the order subtotal '
            'when something actually sells — calculated and confirmed '
            'server-side, never on shipping or tax.',
      ),
      const _FaqItem(
        'How do buyers pay?',
        'M-Pesa STK push or card checkout through IntaSend. Every order is '
            're-priced and payment-confirmed server-side before it\'s '
            'marked paid.',
      ),
      const _FaqItem(
        'Can I change my plan later?',
        'Yes — upgrade or downgrade at any time. Your listing limit and '
            'commission rate update immediately.',
      ),
      const _FaqItem(
        'Who handles fulfillment?',
        'Once payment is confirmed, the order routes to the supplier '
            'automatically — you don\'t hold or ship inventory yourself.',
      ),
      const _FaqItem(
        'Is Sellora only for Kenya?',
        'Sellora launches Kenya-first, with M-Pesa and KES pricing built '
            'in from day one, on infrastructure designed to expand across '
            'Africa.',
      ),
    ];

    return _section(
      context,
      background: AppColors.mist,
      maxWidth: 820,
      child: Column(
        children: [
          Text('FAQ', style: _eyebrowStyle(context)),
          const SizedBox(height: AppSpacing.sm),
          Text('Common questions.',
              style: _headingStyle(context), textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xl),
          for (final item in items) _FaqTile(item: item),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  const _FaqTile({required this.item});
  final _FaqItem item;

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.item.question,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  Icon(_expanded ? Icons.remove : Icons.add,
                      color: AppColors.cargoNavy),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0,
                  AppSpacing.md, AppSpacing.md),
              child: Text(widget.item.answer,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.slate)),
            ),
        ],
      ),
    );
  }
}

class _FinalCta extends StatelessWidget {
  const _FinalCta({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.cargoNavy,
      padding: EdgeInsets.symmetric(
          horizontal: context.pageHorizontalPadding, vertical: AppSpacing.xxl),
      child: ResponsiveCenter(
        maxWidth: 720,
        child: Column(
          children: [
            Text(
              'Ready to start selling?',
              textAlign: TextAlign.center,
              style: _headingStyle(context, color: AppColors.cloud),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Set up your store in minutes, list your first product, and '
              'start taking orders.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.slateLight, fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
                onPressed: onStart,
                child: const Text('Create your seller account')),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onSignIn, required this.onStart});
  final VoidCallback onSignIn;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.ink,
      padding: EdgeInsets.symmetric(
          horizontal: context.pageHorizontalPadding, vertical: AppSpacing.xl),
      child: ResponsiveCenter(
        maxWidth: 1120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sellora',
                style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cloud)),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Source from one shared catalog. Sell it as your own store.',
              style: TextStyle(color: AppColors.slateLight, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                _FooterLink('Sign in', onSignIn),
                _FooterLink('Start selling', onStart),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const Divider(color: Color(0xFF2A2E3F)),
            const SizedBox(height: AppSpacing.md),
            const Text('© 2026 Sellora. All rights reserved.',
                style: TextStyle(color: AppColors.slateLight, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(label,
          style: const TextStyle(color: AppColors.slateLight, fontSize: 13)),
    );
  }
}
