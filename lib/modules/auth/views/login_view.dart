import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/validators.dart';
import '../controllers/auth_controller.dart';

class LoginView extends GetView<AuthController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments as Map?;
    final intent = args?['intent'] as String? ?? 'buyer';
    final formKey = GlobalKey<FormState>();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back', style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  intent == 'seller' ? 'Sign in to manage your storefront.' : 'Sign in to keep shopping.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: Validators.email,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: Validators.password,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      if (emailCtrl.text.trim().isEmpty || Validators.email(emailCtrl.text) != null) {
                        Get.snackbar('Enter your email first', 'Then tap "Forgot password" again.');
                        return;
                      }
                      await Get.find<AuthController>().sendReset(emailCtrl.text.trim());
                      Get.snackbar('Check your email', 'We sent a password reset link to ${emailCtrl.text.trim()}.');
                    },
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Obx(() {
                  final error = controller.errorMessage.value;
                  if (error == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  );
                }),
                Obx(
                  () => SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: controller.isLoading.value
                          ? null
                          : () {
                              if (formKey.currentState!.validate()) {
                                controller.signIn(email: emailCtrl.text.trim(), password: passwordCtrl.text);
                              }
                            },
                      child: controller.isLoading.value
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Sign in'),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: TextButton(
                    onPressed: () => Get.toNamed(
                      intent == 'seller' ? Routes.registerSeller : Routes.registerBuyer,
                    ),
                    child: Text(
                      intent == 'seller' ? "New seller? Create a store" : "New here? Create an account",
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
