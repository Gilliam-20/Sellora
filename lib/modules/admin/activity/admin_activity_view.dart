import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/manifest_stub.dart';
import '../../../data/models/activity_models.dart';
import 'admin_activity_controller.dart';

class AdminActivityView extends GetView<AdminActivityController> {
  const AdminActivityView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Activity'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Audit log'),
            Tab(text: 'App errors'),
          ]),
        ),
        body: Obx(() {
          if (controller.isLoading.value) return const SelloraLoader();
          final error = controller.errorMessage.value;
          if (error != null) {
            return EmptyState(
              icon: Icons.error_outline,
              title: error,
              message: 'Check your connection and try again.',
              actionLabel: 'Retry',
              onAction: controller.load,
            );
          }
          return const TabBarView(children: [_AuditTab(), _ErrorsTab()]);
        }),
      ),
    );
  }
}

class _AuditTab extends GetView<AdminActivityController> {
  const _AuditTab();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.auditEntries.isEmpty) {
        return const EmptyState(
          icon: Icons.history,
          title: 'No activity yet',
          message: 'Admin edits, refunds, plan changes and order moves '
              'are recorded here as they happen.',
        );
      }
      final entries = controller.visibleAudit;
      return RefreshIndicator(
        onRefresh: controller.load,
        child: ResponsiveCenter(
          maxWidth: 820,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.md),
            itemCount: entries.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              if (index == 0) return _filters();
              final entry = entries[index - 1];
              final fields = entry.changedFields;
              return ManifestStub(
                code: entry.action,
                title: '${entry.entityType} ${entry.entityId}',
                subtitle: [
                  _actorLabel(entry),
                  Formatters.dateTime(entry.occurredAt),
                  if (fields.isNotEmpty) fields.join(', '),
                ].join(' · '),
                accentColor: _actorColor(entry.actorRole),
                onTap: () => _showDetails(
                    context, entry.action, entry.details, entry.occurredAt),
              );
            },
          ),
        ),
      );
    });
  }

  Widget _filters() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: ChoiceChip(
                label: const Text('Everything'),
                selected: controller.entityFilter.value == null,
                onSelected: (_) => controller.filterEntity(null),
              ),
            ),
            for (final type in controller.entityTypes)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: ChoiceChip(
                  label: Text(type),
                  selected: controller.entityFilter.value == type,
                  onSelected: (_) => controller.filterEntity(type),
                ),
              ),
          ],
        ),
      );

  String _actorLabel(AuditLogEntry entry) => switch (entry.actorRole) {
        'admin' => 'Admin',
        'user' => 'User ${_short(entry.actorId)}',
        'service' => 'Backend',
        _ => 'System',
      };

  Color _actorColor(String role) => switch (role) {
        'admin' => AppColors.adminAccent,
        'user' => AppColors.manifestGold,
        'service' => AppColors.cargoNavy,
        _ => AppColors.slate,
      };
}

class _ErrorsTab extends GetView<AdminActivityController> {
  const _ErrorsTab();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final groups = controller.errorGroups;
      if (groups.isEmpty) {
        return const EmptyState(
          icon: Icons.check_circle_outline,
          title: 'No app errors',
          message: 'Uncaught errors from the last 30 days show up here, '
              'grouped by message.',
        );
      }
      return RefreshIndicator(
        onRefresh: controller.load,
        child: ResponsiveCenter(
          maxWidth: 820,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.md),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final group = groups[index];
              final latest = group.latest;
              final route = latest.context['route'];
              return ManifestStub(
                code: '×${group.count}',
                title: latest.headline,
                subtitle: [
                  'Last ${Formatters.relative(latest.occurredAt)}',
                  '${group.affectedUsers} signed-in user'
                      '${group.affectedUsers == 1 ? '' : 's'}',
                  if (route is String && route.isNotEmpty) route,
                ].join(' · '),
                accentColor: AppColors.danger,
                onTap: () => _showDetails(
                  context,
                  latest.headline,
                  {
                    'message': latest.message,
                    if (latest.stack != null) 'stack': latest.stack,
                    'context': latest.context,
                  },
                  latest.occurredAt,
                ),
              );
            },
          ),
        ),
      );
    });
  }
}

String _short(String? id) =>
    id == null ? '' : (id.length > 8 ? id.substring(0, 8) : id);

void _showDetails(BuildContext context, String title,
    Map<String, dynamic> details, DateTime at) {
  final text = details.entries.map((e) {
    final value = e.value;
    return value is String
        ? '${e.key}:\n$value'
        : '${e.key}:\n${const JsonEncoder.withIndent('  ').convert(value)}';
  }).join('\n\n');
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(Formatters.dateTime(at),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.slate)),
          const SizedBox(height: AppSpacing.md),
          SelectableText(
            text.isEmpty ? 'No details recorded.' : text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
