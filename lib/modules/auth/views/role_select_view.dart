import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';

class RoleSelectView extends StatelessWidget {
  const RoleSelectView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Used to be a Column with a Spacer() pushing the cards toward
        // the bottom and no scroll fallback — on a short viewport (a
        // small phone, landscape, a resized browser window, or a larger
        // system text size) that overflows instead of laying out.
        // Wrapped in a scroll view with a fixed gap instead: safe at
        // any height, and a Spacer would in fact crash here anyway
        // (Flex children with flex need a bounded height, and a
        // scroll view's child is intentionally unbounded).
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: context.pageHorizontalPadding,
              vertical: AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                Text('Sellora',
                    style: Theme.of(context)
                        .textTheme
                        .displayMedium
                        ?.copyWith(color: AppColors.cargoNavy)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'One catalog, sourced globally. Pick how you want in.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: AppColors.slate),
                ),
                const SizedBox(height: AppSpacing.xxl),
                _RoleCard(
                  title: 'Shop the marketplace',
                  description:
                      'Browse products from every seller on Sellora and check out in a few taps.',
                  icon: Icons.storefront_outlined,
                  accent: AppColors.buyerAccent,
                  onTap: () =>
                      Get.toNamed(Routes.login, arguments: {'intent': 'buyer'}),
                ),
                const SizedBox(height: AppSpacing.md),
                _RoleCard(
                  title: 'Start selling',
                  description:
                      'Subscribe monthly, list CJ Dropshipping products at your own price, and get paid on every order.',
                  icon: Icons.rocket_launch_outlined,
                  accent: AppColors.sellerAccent,
                  onTap: () => Get.toNamed(Routes.login,
                      arguments: {'intent': 'seller'}),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: TextButton(
                    onPressed: () => Get.toNamed(Routes.login,
                        arguments: {'intent': 'buyer'}),
                    child: const Text('Already have an account? Sign in'),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => Get.toNamed(Routes.marketing),
                    child: const Text('Learn more about Sellora'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cloud,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.hairline),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(description,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.slateLight),
            ],
          ),
        ),
      ),
    );
  }
}
