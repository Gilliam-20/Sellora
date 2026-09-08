import 'package:flutter/material.dart';
import '../../app/theme/app_metrics.dart';

/// Breakpoints used across Sellora to adapt layout between phone, tablet
/// and desktop/web widths. Kept in one place so "is this screen wide"
/// always means the same thing everywhere — shells, grids, forms.
class AppBreakpoints {
  AppBreakpoints._();

  static const double tablet = 600;
  static const double desktop = 900;
}

enum ScreenSize { mobile, tablet, desktop }

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  ScreenSize get screenSize {
    final width = screenWidth;
    if (width >= AppBreakpoints.desktop) return ScreenSize.desktop;
    if (width >= AppBreakpoints.tablet) return ScreenSize.tablet;
    return ScreenSize.mobile;
  }

  bool get isMobile => screenSize == ScreenSize.mobile;
  bool get isTablet => screenSize == ScreenSize.tablet;
  bool get isDesktop => screenSize == ScreenSize.desktop;

  /// True from tablet width up — the point where shells switch from a
  /// bottom nav bar to a side rail, and single-column content gains
  /// margins instead of running edge-to-edge.
  bool get isWide => screenWidth >= AppBreakpoints.desktop;

  /// Picks a value based on the current breakpoint, falling back down
  /// (desktop → tablet → mobile) so callers only override what changes.
  T responsiveValue<T>({required T mobile, T? tablet, T? desktop}) {
    switch (screenSize) {
      case ScreenSize.desktop:
        return desktop ?? tablet ?? mobile;
      case ScreenSize.tablet:
        return tablet ?? mobile;
      case ScreenSize.mobile:
        return mobile;
    }
  }

  /// Horizontal page padding that grows a little with the viewport, so
  /// content doesn't hug the edge of a tablet or desktop window the way
  /// it should on a phone.
  double get pageHorizontalPadding => responsiveValue(mobile: AppSpacing.md, tablet: AppSpacing.lg, desktop: AppSpacing.xl);
}

/// Centers page content and caps its width once the viewport is wider
/// than a phone/tablet, so text, forms and lists don't stretch edge to
/// edge on desktop web. A no-op below [maxWidth] — phone layouts are
/// completely unaffected.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
  }
}

/// For sliver-based screens where a [ResponsiveCenter] can't wrap
/// individual slivers: symmetric horizontal padding that keeps content
/// under [maxContentWidth] on wide screens by eating the extra width as
/// margin, while staying at [minHorizontal] below that.
EdgeInsets centeredSliverPadding(
  BuildContext context, {
  double maxContentWidth = 1100,
  double minHorizontal = AppSpacing.md,
}) {
  final width = context.screenWidth;
  if (width <= maxContentWidth) return EdgeInsets.symmetric(horizontal: minHorizontal);
  final extra = (width - maxContentWidth) / 2;
  return EdgeInsets.symmetric(horizontal: minHorizontal + extra);
}

/// A responsive product-grid delegate: a fixed max tile width lets
/// Flutter compute however many columns fit, so the grid is 2-up on a
/// narrow phone and grows on its own toward tablet/desktop instead of
/// staying pinned at a hardcoded column count.
SliverGridDelegateWithMaxCrossAxisExtent productGridDelegate({
  double maxCrossAxisExtent = 220,
  double childAspectRatio = 0.62,
  double spacing = AppSpacing.md,
}) {
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: maxCrossAxisExtent,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
    childAspectRatio: childAspectRatio,
  );
}
