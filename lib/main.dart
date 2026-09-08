import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'app/bindings/initial_binding.dart';
import 'app/routes/app_pages.dart';
import 'app/routes/app_routes.dart';
import 'app/theme/app_theme.dart';
import 'core/constants/app_constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  // Firebase is only initialized outside mock mode — see README.md for
  // the `flutterfire configure` step that generates firebase_options.dart.
  if (!AppConstants.useMockData) {
    // ignore: avoid_print
    print('Sellora: useMockData is false — make sure Firebase.initializeApp() '
        'is wired up in main.dart with your generated firebase_options.dart.');
    // import 'package:firebase_core/firebase_core.dart';
    // import 'firebase_options.dart';
    // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      initialRoute: Routes.splash,
      initialBinding: InitialBinding(),
      getPages: AppPages.pages,
      defaultTransition: Transition.cupertino,
    );
  }
}
