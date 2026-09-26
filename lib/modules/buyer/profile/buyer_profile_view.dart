import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/i18n/currencies.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/delete_account_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/store_repository.dart';
import '../../../data/services/currency_service.dart';

class BuyerProfileView extends StatelessWidget {
  const BuyerProfileView({super.key});

  // A buyer's sign-out must land them back on their own store's storefront,
  // never on Sellora's own (seller-only) login — resolve the slug before
  // clearing the session, since the store lookup needs the still-cached
  // user's storeId.
  Future<void> _signOut() async {
    final authRepo = Get.find<AuthRepository>();
    final storeId = authRepo.cachedUser?.storeId;
    final store = storeId != null
        ? await Get.find<StoreRepository>().storeById(storeId)
        : null;
    await authRepo.signOut();
    Get.offAllNamed(store != null ? '/s/${store.slug}' : Routes.marketing);
  }

  @override
  Widget build(BuildContext context) {
    final user = Get.find<AuthRepository>().cachedUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: EmptyState(
          icon: Icons.person_outline,
          title: 'You\'re browsing as a guest',
          message: 'Sign in or create an account to save your details and '
              'track orders.',
          actionLabel: 'Sign in',
          onAction: () => Get.toNamed('/s/${Get.parameters['slug']}/login'),
        ),
      );
    }

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
                (user.name.isNotEmpty ? user.name[0] : '?').toUpperCase(),
                style: const TextStyle(
                    fontSize: 24,
                    color: AppColors.horizonTealDeep,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(user.name, style: Theme.of(context).textTheme.titleLarge),
            Text(user.email, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.attach_money),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text('Currency',
                          style: Theme.of(context).textTheme.bodyMedium)),
                  Obx(() {
                    final currency = Get.find<CurrencyService>();
                    // A dropdown rather than a segmented control — four
                    // currencies no longer fit one row on a phone.
                    return DropdownButton<String>(
                      value: currency.code.value,
                      underline: const SizedBox.shrink(),
                      // Closed state shows only the code; names are in
                      // the open menu, where there's room for them.
                      selectedItemBuilder: (_) => Currencies.all
                          .map((c) => Align(
                              alignment: Alignment.centerRight,
                              child: Text(c.code)))
                          .toList(),
                      items: Currencies.all
                          .map((c) => DropdownMenuItem(
                                value: c.code,
                                child: Text('${c.code} · ${c.name}'),
                              ))
                          .toList(),
                      onChanged: (code) {
                        if (code != null) currency.setCode(code);
                      },
                    );
                  }),
                ],
              ),
            ),
            const Divider(),
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
            const SizedBox(height: AppSpacing.sm),
            DeleteAccountButton(onDeleted: () {
              final slug = Get.parameters['slug'];
              Get.offAllNamed(slug != null ? '/s/$slug' : Routes.marketing);
            }),
          ],
        ),
      ),
    );
  }
}
