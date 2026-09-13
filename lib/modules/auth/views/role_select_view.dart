import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';

/// The mobile app's welcome step between the branded splash and sign-in
/// (splash → role select → sign in; web skips straight to `MarketingView`
/// instead — see `SelloraApp.initialRoute`). There's no buyer path here: a
/// buyer signs in as a customer of a specific store from that store's own
/// `/s/{slug}/login` page, not from Sellora's own top-level auth flow, so
/// this only leads sellers (new or returning) onward. See WORKLOG.md's
/// 2026-09-14 entry for why this replaced the old two-role (buyer/seller)
/// picker.
class RoleSelectView extends StatelessWidget {
  const RoleSelectView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
                  'Sourced globally. Sold locally.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: AppColors.slate),
                ),
                const SizedBox(height: AppSpacing.xxl),
                _RoleCard(
                  title: 'Start selling',
                  description:
                      'Subscribe monthly, list CJ Dropshipping products at your own price, and get paid on every order.',
                  icon: Icons.rocket_launch_outlined,
                  accent: AppColors.sellerAccent,
                  onTap: () => Get.toNamed(Routes.registerSeller),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: TextButton(
                    onPressed: () => Get.toNamed(Routes.login),
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
