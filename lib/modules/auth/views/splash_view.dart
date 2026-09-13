import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/common.dart';
import '../controllers/auth_controller.dart';

class SplashView extends GetView<AuthController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => controller.checkSession());

    return Scaffold(
      backgroundColor: AppColors.cargoNavy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sellora',
              style: GoogleFonts.fraunces(
                color: AppColors.cloud,
                fontSize: 40,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Sourced globally. Sold locally.',
              style: GoogleFonts.inter(
                color: AppColors.slateLight,
                fontSize: 14,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 28),
            const SelloraLoader(size: 28),
          ],
        ),
      ),
    );
  }
}
