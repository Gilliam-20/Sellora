import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_page.dart';
import '../../../data/models/store_design.dart';
import '../../storefront/design/storefront_renderer.dart';
import '../../storefront/design/storefront_theme.dart';
import '../../storefront/storefront_controller.dart';
import 'builder_panels.dart';
import 'store_builder_controller.dart';

/// Store design (TODO §18): edit the storefront's sections on the left (or
/// the Edit tab), see the result on the right (or the Preview tab), save a
/// draft, publish it.
class StoreBuilderView extends GetView<StoreBuilderController> {
  const StoreBuilderView({super.key});

  static const _wide = 960.0;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final dirty = controller.isDirty;
      return PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final leave = await Get.dialog<bool>(AlertDialog(
            title: const Text('Leave without saving?'),
            content:
                const Text('Your changes since the last save will be lost.'),
            actions: [
              TextButton(
                  onPressed: () => Get.back(result: false),
                  child: const Text('Keep editing')),
              TextButton(
                  onPressed: () => Get.back(result: true),
                  child: const Text('Leave')),
            ],
          ));
          if (leave == true) {
            controller.discardChanges();
            Get.back();
          }
        },
        child: _page(context),
      );
    });
  }

  Widget _page(BuildContext context) {
    if (controller.isLoading.value) {
      return const Scaffold(body: AppLoadingState());
    }
    if (controller.loadError.value case final error?) {
      return Scaffold(
        appBar: AppBar(title: const Text('Store design')),
        body: AppErrorState(message: error, onRetry: controller.load),
      );
    }
    final wide = MediaQuery.of(context).size.width >= _wide;
    final appBar = AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Store design'),
          Text(_status(),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.slate)),
        ],
      ),
      actions: [
        if (wide) const _DeviceToggle(),
        TextButton(
          onPressed: controller.isDirty && !controller.isSaving.value
              ? controller.saveDraft
              : null,
          child: Text(controller.isSaving.value ? 'Saving…' : 'Save'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: ElevatedButton(
            onPressed: controller.isPublishing.value ||
                    (!controller.isDirty && !controller.hasUnpublishedChanges)
                ? null
                : () => _publish(context),
            child:
                Text(controller.isPublishing.value ? 'Publishing…' : 'Publish'),
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) => switch (v) {
            'view' => _openLive(),
            'discard' => controller.discardChanges(),
            'revert' => controller.revertToPublished(),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'view', child: Text('View live storefront')),
            if (controller.isDirty)
              const PopupMenuItem(
                  value: 'discard', child: Text('Discard unsaved changes')),
            if (controller.record.value?.published != null)
              const PopupMenuItem(
                  value: 'revert',
                  child: Text('Start over from the live design')),
          ],
        ),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            Container(
              width: 380,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.hairline)),
              ),
              child: const BuilderPanelView(),
            ),
            const Expanded(child: _Preview()),
          ],
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: appBar.title,
          actions: appBar.actions,
          bottom: const TabBar(tabs: [Tab(text: 'Edit'), Tab(text: 'Preview')]),
        ),
        body: const TabBarView(
          physics: NeverScrollableScrollPhysics(),
          children: [BuilderPanelView(), _Preview()],
        ),
      ),
    );
  }

  String _status() {
    final r = controller.record.value;
    if (controller.isDirty) return 'Unsaved changes';
    if (r?.published == null) return 'Draft saved · not published yet';
    if (controller.hasUnpublishedChanges) {
      return 'Draft saved · live is version ${r!.publishedVersion}';
    }
    return 'Live · version ${r!.publishedVersion}, '
        'published ${Formatters.date(r.publishedAt ?? DateTime.now())}';
  }

  Future<void> _publish(BuildContext context) async {
    final problems = await controller.publish();
    if (problems.isEmpty) return;
    await Get.dialog(AlertDialog(
      title: const Text('Fix these first'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final p in problems) Text('• $p')],
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('OK')),
      ],
    ));
  }

  void _openLive() {
    final slug = controller.scope.current.value?.slug;
    if (slug == null) return;
    launchUrl(Uri.base.replace(fragment: '/s/$slug'),
        mode: LaunchMode.externalApplication);
  }
}

class _DeviceToggle extends GetView<StoreBuilderController> {
  const _DeviceToggle();

  @override
  Widget build(BuildContext context) =>
      Obx(() => SegmentedButton<PreviewDevice>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: PreviewDevice.desktop,
                  icon: Icon(Icons.desktop_windows_outlined),
                  tooltip: 'Desktop'),
              ButtonSegment(
                  value: PreviewDevice.mobile,
                  icon: Icon(Icons.phone_iphone),
                  tooltip: 'Phone'),
            ],
            selected: {controller.device.value},
            onSelectionChanged: (s) => controller.device.value = s.first,
          ));
}

/// The working copy rendered by the storefront's own renderer, inside a
/// frame whose width (and so whose MediaQuery) is the chosen device's.
class _Preview extends GetView<StoreBuilderController> {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final catalog =
        Get.find<StorefrontController>(tag: StoreBuilderController.previewTag);
    return Container(
      color: AppColors.mist,
      padding: const EdgeInsets.all(AppSpacing.md),
      alignment: Alignment.topCenter,
      child: Obx(() {
        final design = controller.design.value;
        if (design == null) return const SizedBox.shrink();
        final phone = controller.device.value == PreviewDevice.mobile ||
            MediaQuery.of(context).size.width < StoreBuilderView._wide;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: phone ? 400 : double.infinity),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(phone ? 24 : AppRadii.stub),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.hairline),
                borderRadius: BorderRadius.circular(phone ? 24 : AppRadii.stub),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      size: Size(constraints.maxWidth, constraints.maxHeight)),
                  child: _PreviewPage(design: design, catalog: catalog),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _PreviewPage extends GetView<StoreBuilderController> {
  const _PreviewPage({required this.design, required this.catalog});
  final StoreDesign design;
  final StorefrontController catalog;

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  Widget _build(BuildContext context) {
    final store = controller.scope.current.value;
    final theme = StorefrontTheme.of(Theme.of(context), design.theme);
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(store?.name ?? ''),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Icon(Icons.person_outline),
            ),
          ],
        ),
        body: StorefrontRenderer(
          controller: catalog,
          design: design,
          selectedSectionId: controller.selectedSectionId,
          onSelectSection: (id) => controller.open(SectionPanel(id)),
        ),
      ),
    );
  }
}
