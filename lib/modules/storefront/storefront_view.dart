import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/store_page.dart';
import 'design/storefront_renderer.dart';
import 'shell/storefront_links.dart';
import 'shell/storefront_page.dart';
import 'storefront_controller.dart';
import 'storefront_session.dart';

/// A store's homepage, `/s/{slug}`: its published design, rendered section
/// by section, under the storefront header.
class StorefrontView extends StatelessWidget {
  const StorefrontView({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Get.find<StorefrontSession>();
    return StorefrontPage(
      // Built only once the store is loaded, so the controller (created on
      // first use) reads a resolved store.
      body: (context, store, design) => Obx(() {
        final pages = session.pages;
        return StorefrontRenderer(
          controller: Get.find<StorefrontController>(),
          design: design,
          pages: [
            for (final kind in StorePageKind.values)
              if (pages[kind] case final page?) page,
          ],
          onNavigate: openStoreLink,
          onOpenProduct: (product) => Get.toNamed(
              session.path(StorefrontPaths.product(product.id)),
              arguments: product),
        );
      }),
    );
  }
}
