import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_metrics.dart';
import '../../app/theme/app_typography.dart';

/// A "manifest stub" — Sellora's signature card treatment for anything
/// tied to an order, shipment, or stat. Flat-left edge with a color bar
/// (like a cargo tag) rather than the generic uniform rounded-card-with-
/// shadow used everywhere else in most SaaS UIs.
class ManifestStub extends StatelessWidget {
  const ManifestStub({
    super.key,
    required this.title,
    required this.code,
    this.subtitle,
    this.trailing,
    this.accentColor = AppColors.cargoNavy,
    this.onTap,
  });

  final String title;
  final String code;
  final String? subtitle;
  final Widget? trailing;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cloud,
      borderRadius: BorderRadius.circular(AppRadii.stub),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.stub),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.stub),
            border: Border.all(color: AppColors.hairline),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(AppRadii.stub)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(code,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.manifestCode()),
                              const SizedBox(height: 2),
                              Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
                            ],
                          ),
                        ),
                        if (trailing != null) trailing!,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact stat version of the manifest stub, used on dashboards.
class ManifestStatCard extends StatelessWidget {
  const ManifestStatCard({
    super.key,
    required this.label,
    required this.value,
    this.accentColor = AppColors.manifestGold,
    this.delta,
  });

  final String label;
  final String value;
  final Color accentColor;
  final String? delta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadii.stub),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(fontSize: 24)),
          if (delta != null) ...[
            const SizedBox(height: 4),
            Text(delta!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.horizonTealDeep)),
          ],
        ],
      ),
    );
  }
}
