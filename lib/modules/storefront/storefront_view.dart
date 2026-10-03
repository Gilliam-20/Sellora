import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_metrics.dart';
import '../../core/utils/image_data_url.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../buyer/shell/buyer_shell_controller.dart';
import 'design/storefront_renderer.dart';
import 'design/storefront_theme.dart';
import 'storefront_controller.dart';

/// The "Shop" tab of the store-scoped buyer shell (BuyerShellView), reached
/// by guests and signed-in buyers alike at the same `/s/{slug}` URL.
class StorefrontView extends GetView<StorefrontController> {
  const StorefrontView({super.key});

  @override
  Widget build(BuildContext context) => Obx(() {
        final design = controller.design.value;
        final scaffold = _scaffold(context);
        if (design == null) return scaffold;
        final theme = StorefrontTheme.of(Theme.of(context), design.theme);
        return Title(
          title: controller.scope.current.value?.name ?? 'Sellora',
          color: theme.colorScheme.primary,
          child: Theme(data: theme, child: scaffold),
        );
      });

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Obx(() => Text(controller.scope.current.value?.name ?? 'Sellora')),
        leading: Obx(() {
          final logoUrl = controller.scope.current.value?.logoUrl;
          if (logoUrl == null || logoUrl.isEmpty) {
            return const SizedBox.shrink();
          }
          ImageProvider? logoImage;
          if (isDataUrl(logoUrl)) {
            final logoBytes = decodeDataUrl(logoUrl);
            if (logoBytes != null) logoImage = MemoryImage(logoBytes);
          } else {
            logoImage = CachedNetworkImageProvider(logoUrl);
          }
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: CircleAvatar(
              backgroundImage: logoImage,
              backgroundColor: AppColors.mist,
            ),
          );
        }),
        actions: [
          Obx(() {
            final store = controller.scope.current.value;
            if (store == null) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: AppLocalizations.of(context).storefrontAccount,
              onPressed: () {
                final user = Get.find<AuthRepository>().cachedUser;
                final signedInHere = user != null &&
                    user.role == UserRole.buyer &&
                    user.storeId == store.id;
                if (signedInHere) {
                  // Already on this store's shell — just switch tabs
                  // rather than navigating to a new route.
                  Get.find<BuyerShellController>().changeTab(4);
                } else {
                  Get.toNamed('/s/${store.slug}/login');
                }
              },
            );
          }),
        ],
      ),
      body: Obx(() {
        final store = controller.scope.current.value;
        final design = controller.design.value;
        // An admin took the store offline: storefront_products hides its
        // catalog. Deliberately vague, like createOrder's refusal.
        if (store?.isSuspended == true) {
          return EmptyState(
            icon: Icons.storefront_outlined,
            title: AppLocalizations.of(context).storefrontClosedTitle,
            message: AppLocalizations.of(context).storefrontClosedMessage,
          );
        }
        if (design == null) return const AppLoadingState();
        return StorefrontRenderer(
          controller: controller,
          design: design,
          onOpenProduct: (product) {
            final slug = store?.slug;
            if (slug == null) return;
            Get.toNamed('/s/$slug/product', arguments: product);
          },
        );
      }),
    );
  }
}
