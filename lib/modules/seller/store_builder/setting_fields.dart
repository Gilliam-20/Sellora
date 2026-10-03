import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../data/models/store_design.dart';
import '../../../data/models/store_page.dart';
import 'store_builder_controller.dart';

/// Editors for [SettingDef]s: one widget per [SettingKind], so every
/// section and block is edited by the same code its schema describes.
class SettingField extends StatelessWidget {
  const SettingField({
    super.key,
    required this.def,
    required this.value,
    required this.onChanged,
    required this.fieldId,
  });

  final SettingDef def;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  /// Unique per section/block and key, so a text field keeps its cursor
  /// while the design rebuilds around it.
  final String fieldId;

  @override
  Widget build(BuildContext context) {
    final field = switch (def.kind) {
      SettingKind.text || SettingKind.textarea => TextFormField(
          key: ValueKey(fieldId),
          initialValue: value as String? ?? '',
          maxLength: def.maxLength,
          minLines: def.kind == SettingKind.textarea ? 2 : 1,
          maxLines: def.kind == SettingKind.textarea ? 6 : 1,
          decoration: InputDecoration(
            labelText: def.required ? '${def.label} *' : def.label,
            helperText: def.hint,
          ),
          onChanged: onChanged,
        ),
      SettingKind.image => ImageField(
          label: def.label,
          url: value as String?,
          hint: def.hint,
          uploadKey: fieldId,
          onChanged: onChanged),
      SettingKind.select => DropdownButtonFormField<String>(
          key: ValueKey(fieldId),
          value: value as String?,
          decoration: InputDecoration(labelText: def.label),
          items: [
            for (final e in def.options.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: onChanged,
        ),
      SettingKind.toggle => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(def.label),
          value: value as bool? ?? false,
          onChanged: onChanged,
        ),
      SettingKind.link => LinkPicker(
          label: def.label,
          value: LinkTarget.parse(value),
          fieldId: fieldId,
          onChanged: (t) => onChanged(t?.serialize())),
      SettingKind.products => ProductsField(
          ids: List<String>.from(value as List? ?? const []),
          onChanged: onChanged),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: field,
    );
  }
}

/// A thumbnail with Upload/Remove, and a field for pasting a link.
class ImageField extends StatelessWidget {
  const ImageField({
    super.key,
    required this.label,
    required this.url,
    required this.uploadKey,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? url;
  final String uploadKey;
  final String? hint;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<StoreBuilderController>();
    final textTheme = Theme.of(context).textTheme;
    final u = url;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.stub),
              child: Container(
                width: 72,
                height: 48,
                color: AppColors.mist,
                child: u == null
                    ? const Icon(Icons.image_outlined, color: AppColors.slate)
                    : CachedNetworkImage(
                        imageUrl: u,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Obx(() {
              final busy = controller.uploadingKey.value == uploadKey;
              return OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final uploaded =
                            await controller.uploadImage(uploadKey);
                        if (uploaded != null) onChanged(uploaded);
                      },
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload, size: 18),
                label: Text(u == null ? 'Upload' : 'Replace'),
              );
            }),
            if (u != null)
              IconButton(
                tooltip: 'Remove image',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(hint!, style: textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// Picks where a link goes: home, all products, a category, a section on
/// the page, one of the storefront's pages, or a web address (http/https
/// only).
class LinkPicker extends StatelessWidget {
  const LinkPicker({
    super.key,
    required this.label,
    required this.value,
    required this.fieldId,
    required this.onChanged,
    this.allowNone = false,
  });

  final String label;
  final LinkTarget? value;
  final String fieldId;
  final ValueChanged<LinkTarget?> onChanged;
  final bool allowNone;

  static const _kinds = {
    LinkKind.home: 'Home',
    LinkKind.catalog: 'All products',
    LinkKind.category: 'A category',
    LinkKind.section: 'A section on the page',
    LinkKind.collections: 'Collections page',
    LinkKind.search: 'Search page',
    LinkKind.page: 'About, contact or a policy',
    LinkKind.url: 'A web address',
  };

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<StoreBuilderController>();
    final v = value;
    final sections = controller.design.value?.sections ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<LinkKind?>(
          key: ValueKey('$fieldId.kind.${v?.kind}'),
          value: v?.kind,
          decoration: InputDecoration(labelText: label),
          items: [
            if (allowNone)
              const DropdownMenuItem(value: null, child: Text('No link')),
            for (final e in _kinds.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (kind) => onChanged(switch (kind) {
            null => null,
            LinkKind.home => LinkTarget.home,
            LinkKind.catalog => LinkTarget.catalog,
            // Placeholders until the seller fills them in.
            LinkKind.category => LinkTarget.category('Fashion'),
            LinkKind.section => sections.isEmpty
                ? LinkTarget.catalog
                : LinkTarget.section(sections.first.id),
            LinkKind.collections => LinkTarget.collections,
            LinkKind.search => LinkTarget.search,
            LinkKind.page => LinkTarget.page(StorePageKind.about),
            LinkKind.url => LinkTarget.url('https://example.com'),
          }),
        ),
        if (v?.kind == LinkKind.category)
          TextFormField(
            key: ValueKey('$fieldId.category'),
            initialValue: v!.value,
            decoration: const InputDecoration(
                labelText: 'Category', hintText: 'e.g. Fashion'),
            onChanged: (s) {
              if (s.trim().isNotEmpty) onChanged(LinkTarget.category(s));
            },
          ),
        if (v?.kind == LinkKind.section)
          DropdownButtonFormField<String>(
            key: ValueKey('$fieldId.section'),
            value: sections.any((s) => s.id == v!.value) ? v!.value : null,
            decoration: const InputDecoration(labelText: 'Section'),
            items: [
              for (final s in sections)
                DropdownMenuItem(value: s.id, child: Text(s.title)),
            ],
            onChanged: (id) {
              if (id != null) onChanged(LinkTarget.section(id));
            },
          ),
        if (v?.kind == LinkKind.page)
          DropdownButtonFormField<StorePageKind>(
            key: ValueKey('$fieldId.page'),
            value: StorePageKind.parse(v!.value),
            decoration: const InputDecoration(
                labelText: 'Page',
                helperText: 'Write it in Store pages. Until it\'s published, '
                    'the link says the page isn\'t available.'),
            items: [
              for (final k in StorePageKind.values)
                DropdownMenuItem(value: k, child: Text(k.defaultTitle)),
            ],
            onChanged: (k) {
              if (k != null) onChanged(LinkTarget.page(k));
            },
          ),
        if (v?.kind == LinkKind.url)
          _UrlField(fieldId: fieldId, value: v!, onChanged: onChanged),
      ],
    );
  }
}

class _UrlField extends StatefulWidget {
  const _UrlField(
      {required this.fieldId, required this.value, required this.onChanged});
  final String fieldId;
  final LinkTarget value;
  final ValueChanged<LinkTarget?> onChanged;

  @override
  State<_UrlField> createState() => _UrlFieldState();
}

class _UrlFieldState extends State<_UrlField> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('${widget.fieldId}.url'),
      initialValue: widget.value.value,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
          labelText: 'Web address', hintText: 'https://…', errorText: _error),
      onChanged: (s) {
        final target = LinkTarget.url(s);
        setState(() => _error = target == null
            ? 'Use a full address starting with https://'
            : null);
        if (target != null) widget.onChanged(target);
      },
    );
  }
}

/// "3 products chosen" and a sheet to pick them, in order.
class ProductsField extends StatelessWidget {
  const ProductsField({super.key, required this.ids, required this.onChanged});
  final List<String> ids;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Products'),
      subtitle: Text(ids.isEmpty
          ? 'None chosen yet'
          : '${ids.length} chosen (up to ${SettingDef.maxProducts})'),
      trailing: OutlinedButton(
        onPressed: () async {
          final controller = Get.find<StoreBuilderController>();
          await controller.loadPickerProducts();
          final picked = await Get.bottomSheet<List<String>>(
            _ProductPickerSheet(initial: ids),
            isScrollControlled: true,
            backgroundColor: AppColors.cloud,
          );
          if (picked != null) onChanged(picked);
        },
        child: const Text('Choose'),
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.initial});
  final List<String> initial;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  late final List<String> _picked = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<StoreBuilderController>();
    final products = controller.pickerProducts;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            ListTile(
              title: Text('Choose products',
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(
                  '${_picked.length} of ${SettingDef.maxProducts} chosen. They show in the order you pick them.'),
              trailing: ElevatedButton(
                  onPressed: () => Get.back(result: _picked),
                  child: const Text('Done')),
            ),
            const Divider(height: 1),
            Expanded(
              child: products.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                          'List some products first. Only listed products can be featured.'),
                    ))
                  : ListView(
                      children: [
                        for (final p in products)
                          CheckboxListTile(
                            value: _picked.contains(p.id),
                            title: Text(p.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(p.category),
                            onChanged: (on) => setState(() {
                              if (on == true) {
                                if (_picked.length < SettingDef.maxProducts) {
                                  _picked.add(p.id);
                                }
                              } else {
                                _picked.remove(p.id);
                              }
                            }),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edits a list of menu links: label, target, order, add and remove.
class LinksEditor extends StatelessWidget {
  const LinksEditor({
    super.key,
    required this.links,
    required this.max,
    required this.idPrefix,
    required this.onChanged,
  });

  final List<StoreLink> links;
  final int max;
  final String idPrefix;
  final ValueChanged<List<StoreLink>> onChanged;

  @override
  Widget build(BuildContext context) {
    void replace(int i, StoreLink link) => onChanged([...links]..[i] = link);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, link) in links.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.hairline),
              borderRadius: BorderRadius.circular(AppRadii.stub),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        // Keyed by position and count, so removing a link
                        // rebuilds the fields below it with their own text.
                        key: ValueKey('$idPrefix.$i.${links.length}.label'),
                        initialValue: link.label,
                        maxLength: 40,
                        decoration: const InputDecoration(
                            labelText: 'Label', counterText: ''),
                        onChanged: (s) => replace(
                            i, StoreLink(label: s, target: link.target)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Move up',
                      onPressed: i == 0
                          ? null
                          : () => onChanged([...links]
                            ..removeAt(i)
                            ..insert(i - 1, link)),
                      icon: const Icon(Icons.arrow_upward, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => onChanged([...links]..removeAt(i)),
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ),
                LinkPicker(
                  label: 'Goes to',
                  value: link.target,
                  fieldId: '$idPrefix.$i.${links.length}.target',
                  onChanged: (t) => replace(i,
                      StoreLink(label: link.label, target: t ?? link.target)),
                ),
              ],
            ),
          ),
        if (links.length < max)
          OutlinedButton.icon(
            onPressed: () => onChanged([
              ...links,
              const StoreLink(label: 'Shop all', target: LinkTarget.catalog),
            ]),
            icon: const Icon(Icons.add),
            label: const Text('Add link'),
          ),
      ],
    );
  }
}
