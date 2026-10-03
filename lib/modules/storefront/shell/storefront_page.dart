import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/image_data_url.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/store_design.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/store_page.dart';
import '../../../data/repositories/cart_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../design/storefront_theme.dart';
import '../storefront_session.dart';
import 'storefront_links.dart';

typedef StorefrontBuilder = Widget Function(
    BuildContext context, StoreModel store, StoreDesign design);

/// Loads the store named by the route's `:slug` (through
/// [StorefrontSession]), shows a loading, missing or closed state until it
/// can, then builds the page inside the store's theme with the browser tab
/// titled "[title] · Store". Every storefront page sits in one of these, so
/// any of them can be the first page a visitor opens.
class StorefrontFrame extends StatefulWidget {
  const StorefrontFrame({super.key, required this.builder, this.title});
  final StorefrontBuilder builder;

  /// The page's name for the browser tab; the store name alone if null.
  final String? title;

  @override
  State<StorefrontFrame> createState() => _StorefrontFrameState();
}

class _StorefrontFrameState extends State<StorefrontFrame> {
  final session = Get.find<StorefrontSession>();

  /// Read once: Get.parameters follows whichever route is on top.
  final slug = Get.parameters['slug'] ?? '';

  @override
  void initState() {
    super.initState();
    session.attach();
    // Deferred a frame: ensure() flips StoreScope Rx values this build
    // reads.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) session.ensure(slug);
    });
  }

  @override
  void dispose() {
    session.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Obx(() {
      final scope = session.scope;
      final store = scope.current.value;
      final design = session.design.value;
      if (store == null || design == null || !session.isReadyFor(slug)) {
        final error = scope.errorMessage.value;
        if (error != null && !scope.isResolving.value) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.storefront_outlined,
              title: l10n.storeLoadFailedTitle,
              message: error,
              actionLabel: l10n.tryAgain,
              onAction: () => session.ensure(slug),
            ),
          );
        }
        return Scaffold(body: AppLoadingState(label: l10n.storeLoading));
      }
      final theme = StorefrontTheme.of(Theme.of(context), design.theme);
      final title = widget.title;
      return Title(
        title: title == null ? store.name : '$title · ${store.name}',
        color: theme.colorScheme.primary,
        child: Theme(
          data: theme,
          child: store.isSuspended
              ? Scaffold(
                  appBar: AppBar(title: Text(store.name)),
                  // An admin took the store offline. Deliberately vague,
                  // like createOrder's refusal.
                  body: EmptyState(
                    icon: Icons.storefront_outlined,
                    title: l10n.storefrontClosedTitle,
                    message: l10n.storefrontClosedMessage,
                  ),
                )
              : Builder(
                  builder: (context) => widget.builder(context, store, design)),
        ),
      );
    });
  }
}

/// A storefront page: [StorefrontFrame] with the store's header (name,
/// search, cart, account), a drawer with its menu and pages, and either
/// [slivers] followed by the footer or a whole [body].
class StorefrontPage extends StatelessWidget {
  const StorefrontPage({
    super.key,
    this.title,
    this.slivers,
    this.body,
    this.bottomBar,
    this.onRefresh,
  }) : assert((slivers == null) != (body == null));

  final String? title;
  final List<Widget> Function(
      BuildContext context, StoreModel store, StoreDesign design)? slivers;

  /// For a page with its own scrolling and footer (the homepage).
  final StorefrontBuilder? body;
  final StorefrontBuilder? bottomBar;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return StorefrontFrame(
      title: title,
      builder: (context, store, design) {
        Widget content;
        if (body != null) {
          content = body!(context, store, design);
        } else {
          content = CustomScrollView(slivers: [
            ...slivers!(context, store, design),
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                  alignment: Alignment.bottomCenter, child: StoreFooter()),
            ),
          ]);
          if (onRefresh != null) {
            content = RefreshIndicator(onRefresh: onRefresh!, child: content);
          }
        }
        return Scaffold(
          appBar: StoreHeader(store: store),
          drawer: StoreDrawer(design: design),
          body: content,
          bottomNavigationBar: bottomBar?.call(context, store, design),
        );
      },
    );
  }
}

/// The storefront's top bar: the store (back to its homepage), search,
/// the cart with its count, and the visitor's account.
class StoreHeader extends StatelessWidget implements PreferredSizeWidget {
  const StoreHeader({super.key, required this.store});
  final StoreModel store;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final session = Get.find<StorefrontSession>();
    final cart = Get.find<CartRepository>();
    final l10n = AppLocalizations.of(context);
    final logo = _logo(store.logoUrl);
    return AppBar(
      title: InkWell(
        key: const ValueKey('store-header-home'),
        onTap: () => Get.offAllNamed(session.path()),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo != null) ...[
              CircleAvatar(radius: 16, backgroundImage: logo),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: Text(store.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: () => Get.toNamed(session.path(StorefrontPaths.search)),
        ),
        IconButton(
          tooltip: l10n.navCart,
          onPressed: () => Get.toNamed(session.path(StorefrontPaths.cart)),
          icon: Obx(() => Badge(
                isLabelVisible: cart.itemCount > 0,
                label: Text('${cart.itemCount}'),
                child: const Icon(Icons.shopping_bag_outlined),
              )),
        ),
        IconButton(
          tooltip: l10n.storefrontAccount,
          icon: const Icon(Icons.person_outline),
          onPressed: () => Get.toNamed(session.path(StorefrontPaths.account)),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  static ImageProvider? _logo(String? url) {
    if (url == null || url.isEmpty) return null;
    if (isDataUrl(url)) {
      final bytes = decodeDataUrl(url);
      return bytes == null ? null : MemoryImage(bytes);
    }
    return CachedNetworkImageProvider(url);
  }
}

/// The menu: the seller's links, then every way into the catalog, the
/// store's own pages and the visitor's account.
class StoreDrawer extends StatelessWidget {
  const StoreDrawer({super.key, required this.design});
  final StoreDesign design;

  @override
  Widget build(BuildContext context) {
    final session = Get.find<StorefrontSession>();
    final textTheme = Theme.of(context).textTheme;
    void go(String path) {
      Get.back(); // the drawer
      Get.toNamed(session.path(path));
    }

    return Drawer(
      child: SafeArea(
        child: Obx(() {
          final pages = session.pages;
          return ListView(
            children: [
              ListTile(
                title: Text(session.store?.name ?? '',
                    style: textTheme.titleLarge),
              ),
              for (final link in design.navigation)
                ListTile(
                  title: Text(link.label),
                  onTap: () {
                    Get.back();
                    openStoreLink(link.target);
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.grid_view_outlined),
                title: const Text('Shop all'),
                onTap: () => go(StorefrontPaths.shop),
              ),
              if (session.categories.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.collections_bookmark_outlined),
                  title: const Text('Collections'),
                  onTap: () => go(StorefrontPaths.collections),
                ),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Search'),
                onTap: () => go(StorefrontPaths.search),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Your orders'),
                onTap: () => go(StorefrontPaths.orders),
              ),
              if (pages.isNotEmpty) const Divider(),
              for (final kind in StorePageKind.values)
                if (pages[kind] case final page?)
                  ListTile(
                    dense: true,
                    title: Text(page.title),
                    onTap: () => go(StorefrontPaths.page(kind)),
                  ),
            ],
          );
        }),
      ),
    );
  }
}

/// The footer on every page but the homepage (whose design has its own):
/// the store's pages, its social profiles, and "Powered by Sellora" if the
/// seller keeps it.
class StoreFooter extends StatelessWidget {
  const StoreFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Get.find<StorefrontSession>();
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);
    final footer = session.design.value?.footer ?? const FooterSettings();
    return Obx(() {
      final pages = session.pages;
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: AppSpacing.xl),
        padding: EdgeInsets.symmetric(
            horizontal: centeredSliverPadding(context).horizontal / 2,
            vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.store?.name ?? '', style: textTheme.titleMedium),
            if (pages.isNotEmpty)
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final kind in StorePageKind.values)
                    if (pages[kind] case final page?)
                      TextButton(
                        onPressed: () => Get.toNamed(
                            session.path(StorefrontPaths.page(kind))),
                        child: Text(page.title),
                      ),
                ],
              ),
            if (footer.social.isNotEmpty)
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final e in footer.social.entries)
                    TextButton(
                      onPressed: () => launchUrl(Uri.parse(e.value),
                          mode: LaunchMode.externalApplication),
                      child: Text(e.key.label),
                    ),
                ],
              ),
            if (footer.showPoweredBy) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Powered by Sellora',
                  style: textTheme.labelSmall?.copyWith(color: muted)),
            ],
          ],
        ),
      );
    });
  }
}

/// A page's content column: centered, at most [maxWidth] wide, with the
/// storefront's side padding.
class StorefrontContent extends StatelessWidget {
  const StorefrontContent(
      {super.key, required this.child, this.maxWidth = 1100});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.pageHorizontalPadding, vertical: AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      );
}
