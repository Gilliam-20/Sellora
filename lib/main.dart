import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'app/bindings/initial_binding.dart';
import 'app/routes/app_pages.dart';
import 'app/routes/app_routes.dart';
import 'app/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/i18n/app_locales.dart';
import 'core/config/supabase_config.dart';
import 'core/utils/auth_link_error.dart';
import 'data/repositories/auth_repository.dart';
import 'data/services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  // Every repository is Supabase-backed (see InitialBinding). Unlike
  // Firebase, one config serves every platform — see SupabaseConfig.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  // A bad auth link (expired, already used) comes back as
  // `#error=...&error_code=...`, which supabase_flutter leaves in the URL -
  // and hash routing would read it as a route no page matches. Note it for
  // the error screen and drop it from the address bar before the router
  // reads its initial route.
  if (kIsWeb) {
    AuthLinkError.atLaunch = AuthLinkError.fromUri(Uri.base);
    if (AuthLinkError.atLaunch != null) {
      await SystemNavigator.routeInformationUpdated(
          uri: Uri(path: Routes.authLinkError), replace: true);
    }
  }

  runApp(const SelloraApp());
}

class SelloraApp extends StatelessWidget {
  const SelloraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      localizationsDelegates: AppLocales.delegates,
      supportedLocales: AppLocales.supported,
      // Web opens straight on the marketing/landing page, matching how a
      // browser homepage behaves. Mobile leads with the branded splash,
      // which (once its session check finds nobody signed in) continues to
      // role select and then sign-in — a mobile-app-only affordance, since
      // there's no address bar to hand a first-time visitor a store's URL.
      initialRoute: AuthLinkError.atLaunch != null
          ? Routes.authLinkError
          : kIsWeb
              ? Routes.marketing
              : Routes.splash,
      initialBinding: InitialBinding(),
      // A password-recovery link signs the app in with a recovery session
      // rather than landing on a hosted page, so the app routes itself to
      // the reset form — for the link it was launched with (replayed to
      // this late listener) and any that arrive while it's running.
      //
      // A link that can't be used (expired, already used, opened on another
      // device) goes to a screen that says so, rather than nowhere.
      onReady: () {
        Get.find<AuthRepository>()
            .passwordRecoveries
            .listen((_) => Get.offAllNamed(Routes.resetPassword));
        void showLinkError(AuthLinkError error) {
          if (Get.currentRoute == Routes.authLinkError) return;
          Get.offAllNamed(Routes.authLinkError, arguments: error);
        }

        final authService = Get.find<AuthService>();
        authService.linkErrors.listen(showLinkError);
        final missed = authService.takeUnheardLinkError();
        if (missed != null) showLinkError(missed);
      },
      getPages: AppPages.pages,
      defaultTransition: Transition.cupertino,
    );
  }
}
