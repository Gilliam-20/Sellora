import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../controllers/auth_controller.dart';

class SplashView extends GetView<AuthController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.checkSession());

    return const Scaffold(
      backgroundColor: AppColors.cargoNavy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sellora',
              style: TextStyle(color: AppColors.manifestGold, fontSize: 34, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 12),
            Text(
              'source anywhere. sell everywhere.',
              style: TextStyle(color: AppColors.slateLight, fontSize: 13, letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}
