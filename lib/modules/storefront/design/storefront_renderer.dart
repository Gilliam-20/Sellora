import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/product_card.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_design.dart';
import '../../../data/models/store_page.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../storefront_controller.dart';
import 'storefront_theme.dart';

/// Renders a [StoreDesign]: announcement bar, menu, the homepage sections in
/// order, then the footer. Used by the live storefront and by the store
/// builder's preview, so what the seller previews is what buyers get.
///
/// Expects to sit inside [StorefrontTheme.of]'s theme.
class StorefrontRenderer extends StatefulWidget {
  const StorefrontRenderer({
    super.key,
    required this.controller,
    required this.design,
    this.onOpenProduct,
    this.selectedSectionId,
    this.onSelectSection,
    this.onNavigate,
    this.pages = const [],
  });

  final StorefrontController controller;
  final StoreDesign design;

  /// Null in the builder preview, where products don't open.
  final void Function(ProductModel product)? onOpenProduct;

  /// The builder outlines this section and reports taps on any section.
  final String? selectedSectionId;
  final void Function(String sectionId)? onSelectSection;

  /// Follows a link to another storefront page (collections, search, an
  /// About or policy page). Null in the builder preview, where they don't
  /// go anywhere.
  final void Function(LinkTarget target)? onNavigate;

  /// The store's published pages, linked from the footer.
  final List<StorePage> pages;

  @override
  State<StorefrontRenderer> createState() => StorefrontRendererState();
}

class StorefrontRendererState extends State<StorefrontRenderer> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  StoreSection? get _catalog => widget.design.sections
      .where((s) => s.type == SectionType.catalog && s.enabled)
      .firstOrNull;

  /// Follows a button or menu link. Internal targets scroll this page;
  /// URLs open outside the app.
  Future<void> openLink(LinkTarget? target) async {
    if (target == null) return;
    switch (target.kind) {
      case LinkKind.home:
        await _scroll.animateTo(0,
            duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      case LinkKind.catalog:
        if (_catalog case final c?) await scrollTo(c.id);
      case LinkKind.category:
        widget.controller.selectCategory(target.value);
        if (_catalog case final c?) await scrollTo(c.id);
      case LinkKind.section:
        await scrollTo(target.value);
      case LinkKind.url:
        await launchUrl(Uri.parse(target.value),
            mode: LaunchMode.externalApplication);
      case LinkKind.collections:
      case LinkKind.search:
      case LinkKind.page:
        widget.onNavigate?.call(target);
    }
  }

  /// Slivers far below may not be built yet, so this steps down a screen
  /// at a time until the section exists, then brings it into view.
  Future<void> scrollTo(String sectionId) async {
    final key = _keyFor(sectionId);
    for (var i = 0; i < 12 && key.currentContext == null; i++) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.pixels >= pos.maxScrollExtent) break;
      _scroll.jumpTo(
          (pos.pixels + pos.viewportDimension).clamp(0, pos.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
    final context = key.currentContext;
    if (context != null && context.mounted) {
      await Scrollable.ensureVisible(context,
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final design = widget.design;
    final pad = centeredSliverPadding(context);
    return RefreshIndicator(
      onRefresh: widget.controller.refreshAll,
      child: CustomScrollView(
        controller: _scroll,
        cacheExtent: 2000,
        slivers: [
          if (design.announcement.enabled &&
              design.announcement.text.trim().isNotEmpty)
            SliverToBoxAdapter(
              child: _AnnouncementBar(
                  bar: design.announcement,
                  theme: design.theme,
                  onTap: () => openLink(design.announcement.link)),
            ),
          if (design.navigation.isNotEmpty)
            SliverToBoxAdapter(
              child: _MenuBar(
                  links: design.navigation, onTap: (l) => openLink(l.target)),
            ),
          for (final section in design.sections)
            if (section.enabled) ..._section(context, section, pad),
          SliverToBoxAdapter(
            child: _Footer(
                footer: design.footer,
                storeName: widget.controller.scope.current.value?.name ?? '',
                pages: widget.pages,
                onTap: (l) => openLink(l.target)),
          ),
        ],
      ),
    );
  }

  /// Wraps a section's leading box so the builder can select it, and so
  /// links can scroll to it.
  Widget _frame(StoreSection section, Widget child) {
    final selected = widget.selectedSectionId == section.id;
    Widget framed = KeyedSubtree(key: _keyFor(section.id), child: child);
    if (widget.onSelectSection != null) {
      framed = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => widget.onSelectSection!(section.id),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary, width: 2)
                : null,
          ),
          child: framed,
        ),
      );
    }
    return framed;
  }

  List<Widget> _section(
      BuildContext context, StoreSection section, EdgeInsets pad) {
    final h = pad.horizontal / 2;
    final style = StoreStyle.of(context);
    Widget boxed(Widget child) => SliverPadding(
          padding: EdgeInsets.fromLTRB(h, style.sectionGap, h, 0),
          sliver: SliverToBoxAdapter(child: _frame(section, child)),
        );

    switch (section.type) {
      case SectionType.hero:
        // Full-bleed, unlike the rest.
        return [
          SliverToBoxAdapter(
            child: _frame(
                section,
                _Hero(
                    section: section,
                    horizontal: h,
                    onButton: () => openLink(
                        LinkTarget.parse(section.settings['buttonLink'])))),
          ),
        ];
      case SectionType.featuredProducts:
        return [
          boxed(_SectionTitle(section.text('title'))),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(h, AppSpacing.sm, h, 0),
            sliver: Obx(() {
              final products = widget.controller.featuredFor(section);
              if (products == null) {
                return const SliverToBoxAdapter(
                    child: SizedBox(
                        height: 120,
                        child: Center(child: CircularProgressIndicator())));
              }
              if (products.isEmpty) {
                return SliverToBoxAdapter(
                  child: Text(
                    section.settings['source'] == 'selected'
                        ? 'Choose products to feature.'
                        : 'Products you list will show here.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              return SliverGrid(
                gridDelegate: productGridDelegate(
                    childAspectRatio: style.productCard.tileAspectRatio),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => ProductCard(
                    product: products[i],
                    style: style.productCard,
                    onTap: () => widget.onOpenProduct?.call(products[i]),
                  ),
                  childCount: products.length,
                ),
              );
            }),
          ),
        ];
      case SectionType.catalog:
        return _catalogSlivers(context, section, pad);
      case SectionType.collectionList:
        return [
          boxed(_CollectionList(
              section: section,
              onOpen: (category) => openLink(LinkTarget.category(category)))),
        ];
      case SectionType.imageBanner:
        return [
          boxed(_Banners(
              section: section,
              onOpen: (link) => openLink(LinkTarget.parse(link)))),
        ];
      case SectionType.testimonials:
        return [boxed(_Testimonials(section: section))];
      case SectionType.newsletter:
        return [
          boxed(_Newsletter(section: section, controller: widget.controller))
        ];
      case SectionType.richText:
        return [boxed(_RichText(section: section))];
    }
  }

  List<Widget> _catalogSlivers(
      BuildContext context, StoreSection section, EdgeInsets pad) {
    final controller = widget.controller;
    final l10n = AppLocalizations.of(context);
    final h = pad.horizontal / 2;
    final style = StoreStyle.of(context);
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(h, style.sectionGap, h, 0),
        sliver: SliverToBoxAdapter(
          child: _frame(
            section,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionTitle(section.text('title')),
                if (section.flag('showSearch')) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppSearchField(
                    hintText: l10n.storefrontSearchHint,
                    onChanged: controller.search,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      if (section.flag('showCategories'))
        SliverPadding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          sliver: SliverToBoxAdapter(
            child: SizedBox(
              height: 36,
              child: Obx(() {
                final categories = controller.categories;
                final selectedValue = controller.selectedCategory.value;
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: h),
                  itemCount: categories.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final selected = selectedValue == category;
                    final scheme = Theme.of(context).colorScheme;
                    return ChoiceChip(
                      label: Text(category),
                      selected: selected,
                      selectedColor: scheme.primary,
                      labelStyle: TextStyle(
                        color: selected ? scheme.onPrimary : scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => controller.selectCategory(category),
                    );
                  },
                );
              }),
            ),
          ),
        ),
      Obx(() {
        if (controller.isLoading.value) {
          return const SliverToBoxAdapter(
              child: SizedBox(height: 240, child: AppLoadingState()));
        }
        if (controller.scope.errorMessage.value != null) {
          return SliverToBoxAdapter(
            child: AppErrorState(
              message: controller.scope.errorMessage.value!,
              onRetry: controller.load,
            ),
          );
        }
        // Snapshot the RxList inside Obx's tracked scope — the sliver's
        // itemBuilder runs later during layout, outside that scope.
        final items = List.of(controller.items);
        if (items.isEmpty) {
          return SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.inventory_2_outlined,
              title: l10n.storefrontEmptyTitle,
              message: l10n.storefrontEmptyMessage,
            ),
          );
        }
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(h, AppSpacing.md, h, AppSpacing.md),
          sliver: SliverGrid(
            gridDelegate: productGridDelegate(
                childAspectRatio: style.productCard.tileAspectRatio),
            delegate: SliverChildBuilderDelegate(
              (context, index) => ProductCard(
                product: items[index],
                style: style.productCard,
                onTap: () => widget.onOpenProduct?.call(items[index]),
              ),
              childCount: items.length,
            ),
          ),
        );
      }),
      Obx(() {
        if (controller.isLoading.value || !controller.hasMore.value) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Center(
              child: controller.isLoadingMore.value
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: controller.loadMore,
                      child: Text(l10n.loadMore),
                    ),
            ),
          ),
        );
      }),
    ];
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final style = StoreStyle.of(context);
    return Text(style.heading(text),
        style: style.headingStyle(Theme.of(context).textTheme.headlineSmall));
  }
}

/// An image from a design: network images only (the model drops any URL
/// that isn't http(s)), with a tinted placeholder.
class _DesignImage extends StatelessWidget {
  const _DesignImage({this.url, this.height});
  final String? url;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
        height: height,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12));
    final u = url;
    if (u == null || u.isEmpty) return placeholder;
    return CachedNetworkImage(
      imageUrl: u,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
    );
  }
}

class _AnnouncementBar extends StatelessWidget {
  const _AnnouncementBar(
      {required this.bar, required this.theme, required this.onTap});
  final AnnouncementBar bar;
  final ThemeSettings theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = StorefrontTheme.accent(theme);
    final fg = StorefrontTheme.onColor(bg);
    return Material(
      color: bg,
      child: InkWell(
        onTap: bar.link == null ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Text(
            bar.text,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _MenuBar extends StatelessWidget {
  const _MenuBar({required this.links, required this.onTap});
  final List<StoreLink> links;
  final void Function(StoreLink link) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.08))),
      ),
      height: 44,
      child: Center(
        child: ListView(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          children: [
            for (final link in links)
              TextButton(onPressed: () => onTap(link), child: Text(link.label)),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero(
      {required this.section,
      required this.horizontal,
      required this.onButton});
  final StoreSection section;
  final double horizontal;
  final VoidCallback onButton;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final style = StoreStyle.of(context);
    final mobile = context.screenWidth < 600;
    final height = switch (section.text('height')) {
          'small' => 240.0,
          'large' => 480.0,
          _ => 360.0,
        } *
        (mobile ? 0.8 : 1);
    final imageUrl = section.settings['imageUrl'] as String?;
    final hasImage = imageUrl != null;
    final centered = section.text('alignment') == 'center';
    final fg = hasImage ? Colors.white : scheme.onPrimary;
    final button = section.text('buttonLabel');

    // The height is a minimum: a long name or text on a phone grows the
    // hero rather than overflowing it.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: hasImage
                ? _DesignImage(url: imageUrl)
                : ColoredBox(color: scheme.primary),
          ),
          if (hasImage)
            const Positioned.fill(
                child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xAA000000), Color(0x22000000)],
                ),
              ),
            )),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: horizontal + AppSpacing.md,
                vertical: AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: centered
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Text(style.heading(section.text('heading')),
                    textAlign: centered ? TextAlign.center : TextAlign.start,
                    style: style
                        .headingStyle(mobile
                            ? textTheme.headlineMedium
                            : textTheme.displaySmall)
                        ?.copyWith(color: fg)),
                if (section.text('subheading').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(section.text('subheading'),
                        textAlign:
                            centered ? TextAlign.center : TextAlign.start,
                        style: textTheme.bodyLarge?.copyWith(color: fg)),
                  ),
                ],
                if (button.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    style: hasImage
                        ? null
                        : ElevatedButton.styleFrom(
                            backgroundColor: scheme.onPrimary,
                            foregroundColor: scheme.primary),
                    onPressed: onButton,
                    child: Text(button),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionList extends StatelessWidget {
  const _CollectionList({required this.section, required this.onOpen});
  final StoreSection section;
  final void Function(String category) onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(StoreStyle.of(context).smallRadius);
    final tiles = section.blocks.where(
        (b) => (b.settings['category'] as String? ?? '').trim().isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(section.text('title')),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(builder: (context, constraints) {
          final columns = (constraints.maxWidth / 200).floor().clamp(2, 4);
          final width =
              (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final b in tiles)
                SizedBox(
                  width: width,
                  child: InkWell(
                    onTap: () => onOpen(b.settings['category'] as String),
                    borderRadius: radius,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: radius,
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _DesignImage(
                                url: b.settings['imageUrl'] as String?),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          [b.settings['label'], b.settings['category']]
                              .whereType<String>()
                              .firstWhere((s) => s.trim().isNotEmpty),
                          style: textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}

class _Banners extends StatelessWidget {
  const _Banners({required this.section, required this.onOpen});
  final StoreSection section;
  final void Function(Object? link) onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = StoreStyle.of(context).largeRadius;
    Widget banner(SectionBlock b) {
      final s = b.settings;
      final button = s['buttonLabel'] as String? ?? '';
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _DesignImage(url: s['imageUrl'] as String?, height: 220),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => onOpen(s['link']),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['heading'] as String? ?? '',
                            style: textTheme.titleLarge
                                ?.copyWith(color: Colors.white)),
                        if ((s['text'] as String? ?? '').isNotEmpty)
                          Text(s['text'] as String,
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: Colors.white)),
                        if (button.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          ElevatedButton(
                              onPressed: () => onOpen(s['link']),
                              child: Text(button)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final blocks = section.blocks;
    if (context.screenWidth < 700 || blocks.length == 1) {
      return Column(children: [
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: banner(b),
          ),
      ]);
    }
    return Row(
      children: [
        for (final (i, b) in blocks.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: banner(b)),
        ],
      ],
    );
  }
}

class _Testimonials extends StatelessWidget {
  const _Testimonials({required this.section});
  final StoreSection section;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final style = StoreStyle.of(context);
    final quotes = section.blocks
        .where((b) => (b.settings['quote'] as String? ?? '').trim().isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(section.text('title')),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(builder: (context, constraints) {
          final columns = (constraints.maxWidth / 320).floor().clamp(1, 3);
          final width =
              (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final b in quotes)
                Container(
                  width: width,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  // A flat theme tints the quote; the others use its card.
                  decoration: style.panel(
                      radius: style.smallRadius,
                      color: style.cardStyle == CardStyle.flat
                          ? scheme.primary.withValues(alpha: 0.06)
                          : null),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (int.tryParse('${b.settings['rating']}')
                          case final stars? when stars > 0)
                        Row(children: [
                          for (var i = 0; i < stars; i++)
                            Icon(Icons.star, size: 16, color: scheme.primary),
                        ]),
                      const SizedBox(height: AppSpacing.xs),
                      Text('“${b.settings['quote']}”',
                          style: textTheme.bodyLarge),
                      if ((b.settings['author'] as String? ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text('— ${b.settings['author']}',
                            style: textTheme.labelLarge),
                      ],
                    ],
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}

class _Newsletter extends StatefulWidget {
  const _Newsletter({required this.section, required this.controller});
  final StoreSection section;
  final StorefrontController controller;

  @override
  State<_Newsletter> createState() => _NewsletterState();
}

class _NewsletterState extends State<_Newsletter> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.controller.subscribe(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _done = error == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(StoreStyle.of(context).largeRadius),
      ),
      child: Column(
        children: [
          Text(s.text('heading'),
              textAlign: TextAlign.center, style: textTheme.headlineSmall),
          if (s.text('text').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(s.text('text'),
                textAlign: TextAlign.center, style: textTheme.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _done
                ? Text(
                    widget.controller.previewMode
                        ? 'Preview: sign-ups are collected on your live storefront.'
                        : 'Thanks! You\'re on the list.',
                    textAlign: TextAlign.center,
                    style: textTheme.titleSmall)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                              hintText: 'you@example.com', errorText: _error),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(s.text('buttonLabel').isEmpty
                            ? 'Subscribe'
                            : s.text('buttonLabel')),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RichText extends StatelessWidget {
  const _RichText({required this.section});
  final StoreSection section;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final centered = section.text('alignment') == 'center';
    final align = centered ? TextAlign.center : TextAlign.start;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment:
              centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            if (section.text('heading').isNotEmpty)
              Text(section.text('heading'),
                  textAlign: align, style: textTheme.headlineSmall),
            if (section.text('body').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(section.text('body'),
                  textAlign: align, style: textTheme.bodyLarge),
            ],
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer(
      {required this.footer,
      required this.storeName,
      required this.pages,
      required this.onTap});
  final FooterSettings footer;
  final String storeName;
  final List<StorePage> pages;
  final void Function(StoreLink link) onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);
    return Container(
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
          Text(storeName, style: textTheme.titleMedium),
          if (footer.aboutText.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(footer.aboutText,
                style: textTheme.bodySmall?.copyWith(color: muted)),
          ],
          if (footer.links.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final link in footer.links)
                  TextButton(
                      onPressed: () => onTap(link), child: Text(link.label)),
              ],
            ),
          ],
          if (pages.isNotEmpty)
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final page in pages)
                  TextButton(
                      onPressed: () => onTap(StoreLink(
                          label: page.title,
                          target: LinkTarget.page(page.kind))),
                      child: Text(page.title)),
              ],
            ),
          if (footer.social.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final e in footer.social.entries)
                  OutlinedButton(
                    onPressed: () => launchUrl(Uri.parse(e.value),
                        mode: LaunchMode.externalApplication),
                    child: Text(e.key.label),
                  ),
              ],
            ),
          ],
          if (footer.showPoweredBy) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Powered by Sellora',
                style: textTheme.labelSmall?.copyWith(color: muted)),
          ],
        ],
      ),
    );
  }
}
