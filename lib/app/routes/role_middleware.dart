import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import 'app_routes.dart';

/// Guards the buyer/seller/admin shells so a signed-in buyer can never
/// land on the seller dashboard by typing a route, and vice versa.
class RoleMiddleware extends GetMiddleware {
  RoleMiddleware(this.requiredRole);

  final UserRole requiredRole;

  @override
  RouteSettings? redirect(String? route) {
    final auth = Get.find<AuthRepository>();
    final user = auth.cachedUser;

    if (user == null) return const RouteSettings(name: Routes.roleSelect);

    if (user.role != requiredRole) {
      final home = switch (user.role) {
        UserRole.buyer => Routes.buyerShell,
        UserRole.seller => Routes.sellerShell,
        UserRole.admin => Routes.adminShell,
      };
      return RouteSettings(name: home);
    }

    // A seller without an active subscription is routed to onboarding
    // instead of the dashboard, so they can't browse-and-list for free.
    if (requiredRole == UserRole.seller &&
        !user.hasActiveSubscription &&
        route != Routes.sellerOnboarding) {
      return const RouteSettings(name: Routes.sellerOnboarding);
    }

    return null;
  }
}
