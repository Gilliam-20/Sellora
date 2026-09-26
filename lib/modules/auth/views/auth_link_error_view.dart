import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/auth_link_error.dart';
import '../../../core/utils/responsive.dart';

/// Where an expired, already-used or wrong-device auth email link lands
/// (see SelloraApp), instead of a blank page or a route GetX can't match.
/// The error comes in as the route argument, or — for a web launch —
/// [AuthLinkError.atLaunch].
class AuthLinkErrorView extends StatelessWidget {
  const AuthLinkErrorView({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments;
    final error = args is AuthLinkError
        ? args
        : AuthLinkError.atLaunch ?? const AuthLinkError();
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.cloud,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.xl),
            child: ResponsiveCenter(
              maxWidth: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error.title, style: textTheme.displaySmall),
                  const SizedBox(height: AppSpacing.sm),
                  Text(error.message, style: textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        AuthLinkError.atLaunch = null;
                        Get.offAllNamed(
                            kIsWeb ? Routes.marketing : Routes.roleSelect);
                      },
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
