import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/store_design.dart';
import 'setting_fields.dart';
import 'store_builder_controller.dart';

/// The builder's side panel: whichever editor [StoreBuilderController.panel]
/// names.
class BuilderPanelView extends GetView<StoreBuilderController> {
  const BuilderPanelView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final design = controller.design.value;
      if (design == null) return const SizedBox.shrink();
      return switch (controller.panel.value) {
        RootPanel() => _RootPanel(design: design),
        ThemePanel() => _ThemePanel(theme: design.theme),
        AnnouncementPanel() => _AnnouncementPanel(bar: design.announcement),
        NavigationPanel() => _PanelScaffold(
            title: 'Menu',
            subtitle: 'Links under your store name, up to '
                '${StoreDesign.maxNavLinks}.',
            children: [
              LinksEditor(
                links: design.navigation,
                max: StoreDesign.maxNavLinks,
                idPrefix: 'nav',
                onChanged: controller.setNavigation,
              ),
            ],
          ),
        FooterPanel() => _FooterPanel(footer: design.footer),
        SectionPanel(:final sectionId) => switch (
              design.sectionById(sectionId)) {
            final section? => _SectionEditor(section: section),
            null => const _Gone(),
          },
        BlockPanel(:final sectionId, :final blockId) => switch (
              design.sectionById(sectionId)) {
            final section? => switch (
                  section.blocks.where((b) => b.id == blockId).firstOrNull) {
                final block? => _BlockEditor(section: section, block: block),
                null => const _Gone(),
              },
            null => const _Gone(),
          },
      };
    });
  }
}

class _Gone extends GetView<StoreBuilderController> {
  const _Gone();

  @override
  Widget build(BuildContext context) => _PanelScaffold(
        title: 'Not found',
        children: [
          TextButton(
              onPressed: () => controller.open(const RootPanel()),
              child: const Text('Back to the page')),
        ],
      );
}

/// A sub-panel: back arrow, title, then its fields.
class _PanelScaffold extends GetView<StoreBuilderController> {
  const _PanelScaffold(
      {required this.title,
      this.subtitle,
      required this.children,
      this.actions});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs, AppSpacing.sm, AppSpacing.sm, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: controller.back,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(child: Text(title, style: textTheme.titleMedium)),
              ...?actions,
            ],
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(subtitle!, style: textTheme.bodySmall),
          ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
            children: children,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Root: everything on the page
// ---------------------------------------------------------------------------

class _RootPanel extends GetView<StoreBuilderController> {
  const _RootPanel({required this.design});
  final StoreDesign design;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final problems = design.problems();
    Widget nav(IconData icon, String title, String subtitle, BuilderPanel to) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle:
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => controller.open(to),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        if (problems.isNotEmpty)
          Container(
            margin: const EdgeInsets.all(AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.manifestGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.stub),
              border: const Border(
                  left: BorderSide(color: AppColors.manifestGold, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fix before publishing', style: textTheme.titleSmall),
                for (final p in problems)
                  Text('• $p', style: textTheme.bodySmall),
              ],
            ),
          ),
        nav(
            Icons.palette_outlined,
            'Theme',
            '${design.theme.headingFont} / ${design.theme.bodyFont}',
            const ThemePanel()),
        nav(
            Icons.campaign_outlined,
            'Announcement bar',
            design.announcement.enabled ? design.announcement.text : 'Off',
            const AnnouncementPanel()),
        nav(Icons.menu, 'Menu', '${design.navigation.length} links',
            const NavigationPanel()),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          child: Text('Homepage', style: textTheme.titleSmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('Drag to reorder. Tap a section to edit it.',
              style: textTheme.bodySmall),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: controller.moveSection,
          children: [
            for (final (i, s) in design.sections.indexed)
              ListTile(
                key: ValueKey(s.id),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_indicator),
                ),
                title: Text(s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: s.enabled
                        ? null
                        : const TextStyle(color: AppColors.slate)),
                subtitle:
                    Text(s.enabled ? s.type.label : '${s.type.label} · hidden'),
                onTap: () => controller.open(SectionPanel(s.id)),
                trailing: IconButton(
                  tooltip: s.enabled ? 'Hide' : 'Show',
                  icon: Icon(s.enabled
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => controller.toggleSection(s.id),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: OutlinedButton.icon(
            onPressed: () => Get.bottomSheet(const _AddSectionSheet(),
                isScrollControlled: true, backgroundColor: AppColors.cloud),
            icon: const Icon(Icons.add),
            label: const Text('Add section'),
          ),
        ),
        const Divider(),
        nav(
            Icons.web_asset_outlined,
            'Footer & social links',
            design.footer.social.isEmpty
                ? 'No social links yet'
                : design.footer.social.keys.map((n) => n.label).join(', '),
            const FooterPanel()),
      ],
    );
  }
}

class _AddSectionSheet extends GetView<StoreBuilderController> {
  const _AddSectionSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('Add a section',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final type in SectionType.values)
              ListTile(
                enabled: controller.canAdd(type),
                title: Text(type.label),
                subtitle: Text(controller.canAdd(type)
                    ? type.description
                    : 'Your page already has one.'),
                onTap: () {
                  Get.back();
                  controller.addSection(type);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

class _ThemePanel extends GetView<StoreBuilderController> {
  const _ThemePanel({required this.theme});
  final ThemeSettings theme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    DropdownButtonFormField<String> font(
            String label, String value, ValueChanged<String> set) =>
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final f in StoreFont.all)
              DropdownMenuItem(
                  value: f.family, child: Text('${f.family} (${f.style})')),
          ],
          onChanged: (v) {
            if (v != null) set(v);
          },
        );

    return _PanelScaffold(
      title: 'Theme',
      subtitle: 'Colors, fonts and buttons across your storefront.',
      children: [
        Text('Color palettes', style: textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final p in ThemePalette.all)
              ActionChip(
                avatar: _Swatches(colors: [p.accent, p.background, p.text]),
                label: Text(p.name),
                onPressed: () => controller.applyPalette(p),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _HexField(
            label: 'Accent (buttons, links)',
            hex: theme.accentHex,
            fieldId: 'accent',
            onChanged: (h) =>
                controller.setTheme(theme.copyWith(accentHex: h))),
        _HexField(
            label: 'Background',
            hex: theme.backgroundHex,
            fieldId: 'background',
            onChanged: (h) =>
                controller.setTheme(theme.copyWith(backgroundHex: h))),
        _HexField(
            label: 'Text',
            hex: theme.textHex,
            fieldId: 'text',
            onChanged: (h) => controller.setTheme(theme.copyWith(textHex: h))),
        if (_contrastWarning(theme) case final warning?)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(warning,
                style: textTheme.bodySmall?.copyWith(color: AppColors.danger)),
          ),
        const SizedBox(height: AppSpacing.sm),
        font('Headings font', theme.headingFont,
            (f) => controller.setTheme(theme.copyWith(headingFont: f))),
        const SizedBox(height: AppSpacing.sm),
        font('Body font', theme.bodyFont,
            (f) => controller.setTheme(theme.copyWith(bodyFont: f))),
        const SizedBox(height: AppSpacing.md),
        Text('Button shape', style: textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<ButtonShape>(
          segments: [
            for (final s in ButtonShape.values)
              ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {theme.buttonShape},
          onSelectionChanged: (s) =>
              controller.setTheme(theme.copyWith(buttonShape: s.first)),
        ),
        const SizedBox(height: AppSpacing.md),
        ImageField(
          label: 'Favicon',
          url: theme.faviconUrl,
          uploadKey: 'favicon',
          hint:
              'The small icon in the browser tab. A square PNG, 64×64 or larger.',
          onChanged: (u) => controller
              .setTheme(theme.copyWith(faviconUrl: u, clearFavicon: u == null)),
        ),
      ],
    );
  }

  /// Text that's hard to read on the background, by WCAG's 4.5:1.
  static String? _contrastWarning(ThemeSettings t) {
    final bg = hexToColor(t.backgroundHex), fg = hexToColor(t.textHex);
    if (bg == null || fg == null) return null;
    final a = bg.computeLuminance(), b = fg.computeLuminance();
    final ratio = (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
    return ratio < 4.5
        ? 'Text and background are hard to tell apart '
            '(contrast ${ratio.toStringAsFixed(1)}:1, aim for 4.5:1).'
        : null;
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.colors});
  final List<String> colors;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        child: Row(
          children: [
            for (final hex in colors)
              Container(
                width: 10,
                height: 18,
                color: hexToColor(hex),
              ),
          ],
        ),
      );
}

class _HexField extends StatefulWidget {
  const _HexField(
      {required this.label,
      required this.hex,
      required this.fieldId,
      required this.onChanged});
  final String label;
  final String hex;
  final String fieldId;
  final ValueChanged<String> onChanged;

  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late final _ctrl = TextEditingController(text: widget.hex);
  String? _error;

  @override
  void didUpdateWidget(_HexField old) {
    super.didUpdateWidget(old);
    // A palette changed it from outside.
    if (widget.hex.toUpperCase() != _ctrl.text.toUpperCase() &&
        _error == null) {
      _ctrl.text = widget.hex;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: _ctrl,
        inputFormatters: [LengthLimitingTextInputFormatter(7)],
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _error,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: hexToColor(widget.hex),
                border: Border.all(color: AppColors.hairline),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        onChanged: (s) {
          final hex = s.trim().startsWith('#') ? s.trim() : '#${s.trim()}';
          final ok = RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex);
          setState(() => _error = ok ? null : 'A color like #303F9F');
          if (ok) widget.onChanged(hex.toUpperCase());
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Announcement bar and footer
// ---------------------------------------------------------------------------

class _AnnouncementPanel extends GetView<StoreBuilderController> {
  const _AnnouncementPanel({required this.bar});
  final AnnouncementBar bar;

  @override
  Widget build(BuildContext context) {
    return _PanelScaffold(
      title: 'Announcement bar',
      subtitle: 'A strip above everything else, e.g. a sale or free delivery.',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show the announcement bar'),
          value: bar.enabled,
          onChanged: (on) =>
              controller.setAnnouncement(bar.copyWith(enabled: on)),
        ),
        TextFormField(
          key: const ValueKey('announcement.text'),
          initialValue: bar.text,
          maxLength: AnnouncementBar.maxText,
          decoration: const InputDecoration(
              labelText: 'Text',
              hintText: 'Free delivery on orders over KES 5,000'),
          onChanged: (s) => controller.setAnnouncement(bar.copyWith(text: s)),
        ),
        LinkPicker(
          label: 'Link (optional)',
          value: bar.link,
          fieldId: 'announcement.link',
          allowNone: true,
          onChanged: (t) => controller
              .setAnnouncement(bar.copyWith(link: t, clearLink: t == null)),
        ),
      ],
    );
  }
}

class _FooterPanel extends GetView<StoreBuilderController> {
  const _FooterPanel({required this.footer});
  final FooterSettings footer;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _PanelScaffold(
      title: 'Footer & social links',
      children: [
        TextFormField(
          key: const ValueKey('footer.about'),
          initialValue: footer.aboutText,
          maxLength: FooterSettings.maxAbout,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(labelText: 'About your store'),
          onChanged: (s) => controller.setFooter(footer.copyWith(aboutText: s)),
        ),
        Text('Footer links', style: textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        LinksEditor(
          links: footer.links,
          max: FooterSettings.maxLinks,
          idPrefix: 'footer',
          onChanged: (links) =>
              controller.setFooter(footer.copyWith(links: links)),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Social links', style: textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        for (final network in SocialNetwork.values)
          _SocialField(
            network: network,
            url: footer.social[network],
            onChanged: (url) {
              final social = Map.of(footer.social);
              if (url == null) {
                social.remove(network);
              } else {
                social[network] = url;
              }
              controller.setFooter(footer.copyWith(social: social));
            },
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show "Powered by Sellora"'),
          value: footer.showPoweredBy,
          onChanged: (on) =>
              controller.setFooter(footer.copyWith(showPoweredBy: on)),
        ),
      ],
    );
  }
}

class _SocialField extends StatefulWidget {
  const _SocialField(
      {required this.network, required this.url, required this.onChanged});
  final SocialNetwork network;
  final String? url;
  final ValueChanged<String?> onChanged;

  @override
  State<_SocialField> createState() => _SocialFieldState();
}

class _SocialFieldState extends State<_SocialField> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextFormField(
        key: ValueKey('social.${widget.network.name}'),
        initialValue: widget.url ?? '',
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: widget.network.label,
          hintText: 'https://${widget.network.domain}/…',
          errorText: _error,
        ),
        onChanged: (s) {
          if (s.trim().isEmpty) {
            setState(() => _error = null);
            widget.onChanged(null);
            return;
          }
          final url = safeUrl(s);
          setState(() => _error =
              url == null ? 'Use a full address starting with https://' : null);
          if (url != null) widget.onChanged(url);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sections and blocks
// ---------------------------------------------------------------------------

class _SectionEditor extends GetView<StoreBuilderController> {
  const _SectionEditor({required this.section});
  final StoreSection section;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final schema = section.type.blocks;
    return _PanelScaffold(
      title: section.type.label,
      subtitle: section.type.description,
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) => switch (v) {
            'toggle' => controller.toggleSection(section.id),
            'duplicate' => controller.duplicateSection(section.id),
            'remove' => controller.removeSection(section.id),
            _ => null,
          },
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'toggle',
                child: Text(section.enabled ? 'Hide section' : 'Show section')),
            if (!section.type.isSingleton)
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
            if (controller.canRemove(section))
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ],
      children: [
        if (!section.enabled)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('Hidden: buyers won\'t see this section.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.slate)),
          ),
        for (final def in section.type.settings)
          if (def.isVisible(section.settings))
            SettingField(
              def: def,
              value: section.settings[def.key],
              fieldId: '${section.id}.${def.key}',
              onChanged: (v) =>
                  controller.setSectionSetting(section.id, def.key, v),
            ),
        if (section.type == SectionType.newsletter) const _SubscribersCard(),
        if (schema != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('${schema.label}s (${section.blocks.length} of ${schema.max})',
              style: textTheme.labelMedium),
          for (final (i, b) in section.blocks.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_blockTitle(schema, b),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => controller.open(BlockPanel(section.id, b.id)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: i == 0
                        ? null
                        : () => controller.moveBlock(section.id, i, i - 1),
                    icon: const Icon(Icons.arrow_upward, size: 18),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          if (section.blocks.length < schema.max)
            OutlinedButton.icon(
              onPressed: () => controller.addBlock(section.id),
              icon: const Icon(Icons.add),
              label: Text('Add ${schema.label.toLowerCase()}'),
            ),
        ],
        if (section.type == SectionType.catalog)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
                'Every storefront keeps this section so buyers can reach all '
                'your products. You can move it, but not remove it.',
                style: textTheme.bodySmall),
          ),
      ],
    );
  }

  static String _blockTitle(BlockSchema schema, SectionBlock b) {
    final t = schema.titleKey == null ? null : b.settings[schema.titleKey];
    if (t is String && t.trim().isNotEmpty) return t;
    final fallback = b.settings['category'] ?? b.settings['quote'];
    return fallback is String && fallback.trim().isNotEmpty
        ? fallback
        : schema.label;
  }
}

class _BlockEditor extends GetView<StoreBuilderController> {
  const _BlockEditor({required this.section, required this.block});
  final StoreSection section;
  final SectionBlock block;

  @override
  Widget build(BuildContext context) {
    final schema = section.type.blocks!;
    return _PanelScaffold(
      title: schema.label,
      subtitle: 'In ${section.title}',
      actions: [
        if (controller.canRemoveBlock(section))
          IconButton(
            tooltip: 'Remove',
            onPressed: () => controller.removeBlock(section.id, block.id),
            icon: const Icon(Icons.delete_outline),
          ),
      ],
      children: [
        for (final def in schema.settings)
          SettingField(
            def: def,
            value: block.settings[def.key],
            fieldId: '${block.id}.${def.key}',
            onChanged: (v) =>
                controller.setBlockSetting(section.id, block.id, def.key, v),
          ),
      ],
    );
  }
}

class _SubscribersCard extends StatefulWidget {
  const _SubscribersCard();

  @override
  State<_SubscribersCard> createState() => _SubscribersCardState();
}

class _SubscribersCardState extends State<_SubscribersCard> {
  final controller = Get.find<StoreBuilderController>();

  @override
  void initState() {
    super.initState();
    controller.loadSubscribers();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Obx(() {
      final list = controller.subscribers;
      return Container(
        margin: const EdgeInsets.only(top: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.hairline),
          borderRadius: BorderRadius.circular(AppRadii.stub),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      '${list.length} subscriber${list.length == 1 ? '' : 's'}',
                      style: textTheme.titleSmall),
                ),
                if (list.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: list.map((s) => s.email).join('\n')));
                      Get.snackbar('Copied',
                          '${list.length} addresses copied, one per line.');
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy all'),
                  ),
              ],
            ),
            Text(
                'Sellora collects these for you; it doesn\'t email them. '
                'Remove anyone who asks to be taken off.',
                style: textTheme.bodySmall),
            for (final s in list.take(50))
              Row(
                children: [
                  Expanded(
                    child: Text(s.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium),
                  ),
                  Text(Formatters.date(s.createdAt),
                      style: textTheme.bodySmall),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => controller.removeSubscriber(s),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            if (list.length > 50)
              Text('…and ${list.length - 50} more (Copy all includes them).',
                  style: textTheme.bodySmall),
          ],
        ),
      );
    });
  }
}
