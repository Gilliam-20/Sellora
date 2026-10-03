import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/i18n/currencies.dart';
import '../../../core/widgets/delete_account_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/store_page.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/currency_service.dart';
import '../../notifications/notification_center.dart';
import '../../storefront/design/storefront_theme.dart';
import '../../storefront/shell/storefront_links.dart';
import '../../storefront/shell/storefront_page.dart';
import '../../storefront/storefront_session.dart';

/// `/s/{slug}/account`: the customer's account with this store: who they
/// are, their orders and notifications, display currency, signing out and
/// deleting the account. A guest gets sign-in and sign-up instead.
class BuyerProfileView extends StatelessWidget {
  const BuyerProfileView({super.key});

  /// A buyer signs out back to this store's homepage, never Sellora's own
  /// (seller-only) sign-in.
  Future<void> _signOut(StorefrontSession session) async {
    final home = session.path();
    await Get.find<AuthRepository>().signOut();
    Get.offAllNamed(home);
  }

  @override
  Widget build(BuildContext context) {
    final session = Get.find<StorefrontSession>();
    return StorefrontPage(
      title: 'Account',
      slivers: (context, store, design) {
        final style = StoreStyle.of(context);
        final textTheme = Theme.of(context).textTheme;
        final user = session.customer;
        final heading = Text(style.heading('Account'),
            style: style.headingStyle(textTheme.headlineSmall));

        if (user == null) {
          return [
            SliverToBoxAdapter(
              child: StorefrontContent(
                maxWidth: 560,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    EmptyState(
                      icon: Icons.person_outline,
                      title: 'You\'re browsing as a guest',
                      message: 'Sign in or create an account with '
                          '${store.name} to check out and track your orders.',
                      actionLabel: 'Sign in',
                      onAction: () =>
                          Get.toNamed(session.path(StorefrontPaths.login)),
                    ),
                    TextButton(
                      onPressed: () => Get.toNamed(session.path('register')),
                      child: const Text('New here? Create an account'),
                    ),
                  ],
                ),
              ),
            ),
          ];
        }

        final notifications = Get.find<NotificationCenter>();
        Widget link(IconData icon, String title, String path,
                {Widget? trailing}) =>
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(title),
              trailing: trailing ?? const Icon(Icons.chevron_right),
              onTap: () => Get.toNamed(session.path(path)),
            );

        return [
          SliverToBoxAdapter(
            child: StorefrontContent(
              maxWidth: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: AppSpacing.md),
                  Text(user.name, style: textTheme.titleLarge),
                  Text(user.email, style: textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(),
                  link(Icons.receipt_long_outlined, 'Your orders',
                      StorefrontPaths.orders),
                  link(Icons.notifications_outlined, 'Notifications',
                      StorefrontPaths.notifications,
                      trailing: Obx(() => notifications.unreadCount == 0
                          ? const Icon(Icons.chevron_right)
                          : Badge(
                              label: Text('${notifications.unreadCount}')))),
                  if (session.pages[StorePageKind.contact] != null)
                    link(Icons.help_outline, 'Contact ${store.name}',
                        StorefrontPaths.page(StorePageKind.contact)),
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.attach_money),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                          child: Text('Show prices in',
                              style: textTheme.bodyMedium)),
                      Obx(() {
                        final currency = Get.find<CurrencyService>();
                        return DropdownButton<String>(
                          value: currency.code.value,
                          underline: const SizedBox.shrink(),
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
                  const Divider(),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: () => _signOut(session),
                    child: const Text('Sign out'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DeleteAccountButton(
                      onDeleted: () => Get.offAllNamed(session.path())),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                      'Deleting removes your account with ${store.name}. '
                      'Order records are kept without your details.',
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.slate)),
                ],
              ),
            ),
          ),
        ];
      },
    );
  }
}
