import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/repositories/auth_repository.dart';

class BuyerProfileView extends StatelessWidget {
  const BuyerProfileView({super.key});

  Future<void> _signOut() async {
    await Get.find<AuthRepository>().signOut();
    Get.offAllNamed(Routes.roleSelect);
  }

  @override
  Widget build(BuildContext context) {
    final user = Get.find<AuthRepository>().cachedUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ResponsiveCenter(
        maxWidth: 560,
        child: ListView(
          padding: EdgeInsets.symmetric(
              horizontal: context.pageHorizontalPadding,
              vertical: AppSpacing.lg),
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.buyerAccent.withValues(alpha: 0.2),
              child: Text(
                (user?.name.isNotEmpty == true ? user!.name[0] : '?')
                    .toUpperCase(),
                style: const TextStyle(
                    fontSize: 24,
                    color: AppColors.horizonTealDeep,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(user?.name ?? '',
                style: Theme.of(context).textTheme.titleLarge),
            Text(user?.email ?? '',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Become a seller'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Get.toNamed('/login', arguments: {'intent': 'seller'}),
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
