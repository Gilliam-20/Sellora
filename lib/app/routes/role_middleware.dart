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

    if (user == null) {
      // A buyer route has no store context to send an unauthenticated
      // visitor back to (this route carries no :slug) — Sellora's own
      // login is seller/admin-only, so a buyer never lands there.
      return RouteSettings(
        name: requiredRole == UserRole.buyer
            ? Routes.marketing
            : Routes.login,
      );
    }

    if (user.role != requiredRole) {
      // A buyer only ever has a store-scoped home (`/s/{slug}`), and this
      // synchronous redirect() has no cheap way to look up their slug — this
      // branch only fires if a signed-in buyer manually navigates to a
      // seller/admin URL, so send them to marketing rather than stall on an
      // async store lookup or a dead route name.
      final home = switch (user.role) {
        UserRole.buyer => Routes.marketing,
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
