import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_page.dart';
import '../../../data/models/store_page.dart';
import '../../storefront/shell/storefront_links.dart';
import 'store_pages_controller.dart';

/// Seller → Store pages: the list of the six pages and, once one is open,
/// its editor.
class StorePagesView extends GetView<StorePagesController> {
  const StorePagesView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final page = controller.editing.value;
      final dirty = controller.isDirty;
      return PopScope(
        // Back from the editor returns to the list first.
        canPop: page == null,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (dirty && !await _confirmDiscard()) return;
          controller.closeEditor();
        },
        child: page == null
            ? _list(context)
            : _PageEditor(key: ValueKey(page.kind), kind: page.kind),
      );
    });
  }

  Widget _list(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Store pages')),
      body: Obx(() {
        if (controller.isLoading.value) return const AppLoadingState();
        if (controller.loadError.value case final error?) {
          return AppErrorState(message: error, onRetry: controller.load);
        }
        final pages = controller.pages;
        return ResponsiveCenter(
          maxWidth: 720,
          child: ListView(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.md),
            children: [
              Text(
                  'Pages your customers can open from your storefront\'s menu '
                  'and footer. Nothing appears until you save it published.',
                  style: textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              for (final kind in StorePageKind.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(kind.isPolicy
                      ? Icons.policy_outlined
                      : kind == StorePageKind.contact
                          ? Icons.mail_outline
                          : Icons.info_outline),
                  title: Text(pages[kind]?.title ?? kind.defaultTitle),
                  subtitle: Text(switch (pages[kind]) {
                    null => 'Not written yet',
                    final p when !p.isPublished => 'Saved · hidden',
                    final p => p.updatedAt == null
                        ? 'Published'
                        : 'Published · updated ${Formatters.date(p.updatedAt!)}',
                  }),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => controller.edit(kind),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                  'Policies matter to customers deciding whether to buy, and '
                  'in some countries you must publish them. Sellora\'s '
                  'templates are a starting point, not legal advice.',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.slate)),
            ],
          ),
        );
      }),
    );
  }

  static Future<bool> _confirmDiscard() async =>
      await Get.dialog<bool>(AlertDialog(
        title: const Text('Discard your changes?'),
        content: const Text('Your edits to this page since the last save '
            'will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Keep editing')),
          TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Discard')),
        ],
      )) ==
      true;
}

class _PageEditor extends StatefulWidget {
  const _PageEditor({super.key, required this.kind});
  final StorePageKind kind;

  @override
  State<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<_PageEditor> {
  final controller = Get.find<StorePagesController>();
  late final StorePage _start = controller.editing.value!;
  late final _title = TextEditingController(text: _start.title);
  late final _body = TextEditingController(text: _start.body);
  late final _email = TextEditingController(text: _start.email ?? '');
  late final _phone = TextEditingController(text: _start.phone ?? '');
  List<String> _problems = const [];

  @override
  void dispose() {
    for (final c in [_title, _body, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  StorePage get _page => controller.editing.value!;

  void _set(StorePage page) => controller.change(page);

  String? _opt(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _useTemplate() async {
    if (_body.text.trim().isNotEmpty) {
      final ok = await Get.dialog<bool>(AlertDialog(
        title: const Text('Replace the text with the template?'),
        content: const Text('What you\'ve written here will be replaced.'),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Replace')),
        ],
      ));
      if (ok != true) return;
    }
    controller.useTemplate();
    _body.text = _page.body;
  }

  Future<void> _save() async {
    final problems = await controller.save();
    if (mounted) setState(() => _problems = problems);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final kind = widget.kind;
    final saved = controller.pages[kind];
    final slug = controller.scope.current.value?.slug;
    return Scaffold(
      appBar: AppBar(
        title: Text(kind.defaultTitle),
        actions: [
          if (saved != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'view' && slug != null) {
                  await launchUrl(
                      Uri.base.replace(
                          fragment: '/s/$slug/${StorefrontPaths.page(kind)}'),
                      mode: LaunchMode.externalApplication);
                }
                if (v == 'delete') await controller.delete(kind);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'view', child: Text('View on storefront')),
                PopupMenuItem(value: 'delete', child: Text('Delete page')),
              ],
            ),
        ],
      ),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: ListView(
          padding: EdgeInsets.symmetric(
              horizontal: context.pageHorizontalPadding,
              vertical: AppSpacing.md),
          children: [
            TextField(
              controller: _title,
              maxLength: StorePage.maxTitle,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (s) => _set(_page.copyWith(title: s)),
            ),
            if (kind == StorePageKind.contact) ...[
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Email for customers',
                    hintText: 'help@yourstore.com'),
                onChanged: (s) => _set(_page.copyWith(
                    email: _opt(s), clearEmail: _opt(s) == null)),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone or WhatsApp number',
                    hintText: '+254 711 000000',
                    helperText: 'Shown with call and WhatsApp buttons.'),
                onChanged: (s) => _set(_page.copyWith(
                    phone: _opt(s), clearPhone: _opt(s) == null)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Row(
              children: [
                Expanded(
                    child: Text(
                        kind == StorePageKind.contact ? 'Message' : 'Text',
                        style: textTheme.labelLarge)),
                TextButton.icon(
                  onPressed: _useTemplate,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Start from a template'),
                ),
              ],
            ),
            TextField(
              controller: _body,
              minLines: 10,
              maxLines: 24,
              maxLength: StorePage.maxBody,
              decoration: const InputDecoration(
                  hintText: 'Leave a blank line between paragraphs.',
                  alignLabelWithHint: true),
              onChanged: (s) => _set(_page.copyWith(body: s)),
            ),
            Obx(() {
              final page = controller.editing.value;
              if (page == null || !StorePageTemplates.hasBlanks(page.body)) {
                return const SizedBox.shrink();
              }
              return Text(
                  'Fill in the parts in [brackets] before publishing. They\'re '
                  'the details only you know.',
                  style: textTheme.bodySmall
                      ?.copyWith(color: AppColors.manifestGoldDeep));
            }),
            Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Published'),
                  subtitle: const Text(
                      'Hidden pages are kept here but customers can\'t see them.'),
                  value: controller.editing.value?.isPublished ?? true,
                  onChanged: (on) => _set(_page.copyWith(isPublished: on)),
                )),
            if (_problems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in _problems)
                      Text('• $p',
                          style: textTheme.bodySmall
                              ?.copyWith(color: AppColors.danger)),
                  ],
                ),
              ),
            Obx(() => ElevatedButton(
                  onPressed: controller.isSaving.value ? null : _save,
                  child:
                      Text(controller.isSaving.value ? 'Saving…' : 'Save page'),
                )),
          ],
        ),
      ),
    );
  }
}
