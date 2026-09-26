import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../controllers/auth_controller.dart';

/// Where a password-recovery link lands. Supabase doesn't host a reset
/// page: the link signs the app in with a recovery session, SelloraApp
/// routes here, and this form sets the new password on that session. The
/// same screen serves every role, including the admin's first sign-in via
/// supabase/scripts/grant-admin.js.
class ResetPasswordView extends StatefulWidget {
  const ResetPasswordView({super.key});

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuthController>();
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
              child: controller.canResetPassword
                  ? _buildForm(context, controller)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('This link has expired',
                            style: textTheme.displaySmall),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Password reset links work once, for a limited '
                          'time. Request a new one with "Forgot password?" '
                          'on the page where you sign in.',
                          style: textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Get.offAllNamed(
                                kIsWeb ? Routes.marketing : Routes.roleSelect),
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

  Widget _buildForm(BuildContext context, AuthController controller) {
    final textTheme = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set a new password', style: textTheme.displaySmall),
          const SizedBox(height: AppSpacing.xs),
          Text('You\'ll be signed in once it\'s saved.',
              style: textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: 'New password'),
            validator: Validators.newPassword,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _confirmCtrl,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration:
                const InputDecoration(labelText: 'Confirm new password'),
            validator: (value) =>
                value != _passwordCtrl.text ? 'Passwords don\'t match' : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          Obx(() {
            final error = controller.errorMessage.value;
            if (error == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            );
          }),
          Obx(
            () => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: controller.isLoading.value
                    ? null
                    : () {
                        if (_formKey.currentState!.validate()) {
                          controller.completePasswordReset(_passwordCtrl.text);
                        }
                      },
                child: controller.isLoading.value
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save password'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
