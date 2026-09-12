import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_metrics.dart';
import '../../data/models/user_model.dart';

/// Sellora's loading indicator — used instead of the bare default
/// CircularProgressIndicator so it always matches the brand color.
class SelloraLoader extends StatelessWidget {
  const SelloraLoader({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(
            strokeWidth: 2.6, color: AppColors.manifestGold),
      ),
    );
  }
}

/// A small colored badge showing which portal a user belongs to.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (role) {
      UserRole.buyer => AppColors.buyerAccent,
      UserRole.seller => AppColors.sellerAccent,
      UserRole.admin => AppColors.adminAccent,
    };
    final String label = switch (role) {
      UserRole.buyer => 'Buyer',
      UserRole.seller => 'Seller',
      UserRole.admin => 'Admin',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadii.control)),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

/// A status pill — order/shipment/subscription status, colored via
/// [AppColors.statusColor] (or any caller-supplied tone color) at 15% alpha
/// with a bold label in the solid tone. Pulled out of `buyer_orders_view.dart`
/// where it was originally hand-built, so every status display (order lists,
/// seller/admin views) renders the same pill instead of each screen
/// reimplementing it slightly differently.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Section header used to introduce a group of content without resorting
/// to a tracked-out all-caps eyebrow label.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
      {super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

/// A single, reusable full-bleed primary action button pinned to the
/// bottom of a sheet/screen (checkout, subscribe, list product).
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.trailingText,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md,
          AppSpacing.md + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.cloud,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        // The bar's background spans full width (it reads as a toolbar),
        // but its content is capped and centered — on a wide desktop
        // window a single button stretched to 1600px looks broken. This
        // is a plain Row nested in a Row (not Center/Align) specifically
        // so its height still hugs its content the same way it did
        // un-wrapped: Flex widgets always size their cross axis to the
        // tallest child regardless of how loose the incoming height
        // constraint is, where Align/Center would instead try to fill it.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Row(
                  children: [
                    if (trailingText != null) ...[
                      Text(trailingText!,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isLoading ? null : onPressed,
                        child: isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.ink))
                            : Text(label),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
