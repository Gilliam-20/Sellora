import 'package:flutter/material.dart';

import '../../app/theme/app_metrics.dart';
import '../utils/responsive.dart';
import 'common.dart';
import 'empty_state.dart';

/// Consistent page framing for seller/admin screens. It deliberately owns
/// only structure, leaving each feature responsible for its data and actions.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.maxWidth = 1120,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: ResponsiveCenter(
        maxWidth: maxWidth,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.pageHorizontalPadding,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(title: title, subtitle: subtitle, actions: actions),
              const SizedBox(height: AppSpacing.lg),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) Wrap(spacing: AppSpacing.sm, children: actions),
      ],
    );
  }
}

class AppSearchField extends StatelessWidget {
  const AppSearchField({super.key, this.controller, this.onChanged, this.hintText = 'Search'});

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search),
        ),
      );
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.label = 'Loading…'});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SelloraLoader(),
            const SizedBox(height: AppSpacing.sm),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.error_outline,
        title: 'Something needs attention',
        message: message,
        actionLabel: onRetry == null ? null : 'Try again',
        onAction: onRetry,
      );
}
