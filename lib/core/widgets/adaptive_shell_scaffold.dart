import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../utils/responsive.dart';

/// One destination in an [AdaptiveShellScaffold] — described once and
/// rendered as either a [BottomNavigationBarItem] or a
/// [NavigationRailDestination] depending on viewport width, so every
/// portal shell (buyer/seller/admin) only has to list its tabs once.
class ShellDestination {
  const ShellDestination(
      {required this.icon, required this.label, this.selectedIcon});

  final Widget icon;
  final Widget? selectedIcon;
  final String label;
}

/// The buyer/seller/admin shells share this exact shape: an
/// [IndexedStack] of tab bodies plus navigation between them. Below
/// [AppBreakpoints.desktop] that navigation is the familiar bottom bar;
/// at desktop width it becomes a side [NavigationRail] instead, since a
/// 4-5 item bottom bar reads as a cramped, non-native pattern once
/// there's a full browser window to work with.
class AdaptiveShellScaffold extends StatelessWidget {
  const AdaptiveShellScaffold({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.tabs,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<ShellDestination> destinations;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(index: currentIndex, children: tabs);

    if (!context.isWide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onDestinationSelected,
          type: BottomNavigationBarType.fixed,
          items: [
            for (final d in destinations)
              BottomNavigationBarItem(
                  icon: d.icon,
                  activeIcon: d.selectedIcon ?? d.icon,
                  label: d.label),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavigationRail(
            selectedIndex: currentIndex,
            onDestinationSelected: onDestinationSelected,
            labelType: NavigationRailLabelType.all,
            backgroundColor: AppColors.cargoNavy,
            selectedIconTheme:
                const IconThemeData(color: AppColors.manifestGold),
            unselectedIconTheme:
                const IconThemeData(color: AppColors.slateLight),
            selectedLabelTextStyle: const TextStyle(
                color: AppColors.manifestGold, fontWeight: FontWeight.w600),
            unselectedLabelTextStyle:
                const TextStyle(color: AppColors.slateLight),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                    icon: d.icon,
                    selectedIcon: d.selectedIcon ?? d.icon,
                    label: Text(d.label)),
            ],
          ),
          const VerticalDivider(
              width: 1, thickness: 1, color: AppColors.hairline),
          Expanded(child: body),
        ],
      ),
    );
  }
}
