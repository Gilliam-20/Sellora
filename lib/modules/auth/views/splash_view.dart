import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/widgets/common.dart';
import '../controllers/auth_controller.dart';

class SplashView extends GetView<AuthController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => controller.checkSession());

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/sellora-app-logo.png',
              width: 108,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 8),
            Image.asset(
              'assets/images/sellora-splash-logo.png',
              width: 340,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 28),
            const SelloraLoader(size: 28),
          ],
        ),
      ),
    );
  }
}
