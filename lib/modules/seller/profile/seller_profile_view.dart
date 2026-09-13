import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/repositories/auth_repository.dart';

class SellerProfileView extends StatelessWidget {
  const SellerProfileView({super.key});

  Future<void> _signOut() async {
    await Get.find<AuthRepository>().signOut();
    Get.offAllNamed(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final user = Get.find<AuthRepository>().cachedUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Store profile')),
      body: ResponsiveCenter(
        maxWidth: 560,
        child: ListView(
          padding: EdgeInsets.symmetric(
              horizontal: context.pageHorizontalPadding,
              vertical: AppSpacing.lg),
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.sellerAccent.withValues(alpha: 0.2),
              child: Text(
                (user?.storeName?.isNotEmpty == true
                        ? user!.storeName![0]
                        : '?')
                    .toUpperCase(),
                style: const TextStyle(
                    fontSize: 24,
                    color: AppColors.manifestGoldDeep,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(user?.storeName ?? '',
                style: Theme.of(context).textTheme.titleLarge),
            Text(user?.name ?? '',
                style: Theme.of(context).textTheme.bodyMedium),
            Text(user?.email ?? '',
                style: Theme.of(context).textTheme.bodySmall),
            if (user?.phone != null)
              Text(user!.phone!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Subscription & billing'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed(Routes.sellerSubscription),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.help_outline),
              title: const Text('Help & support'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger)),
              onPressed: _signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
