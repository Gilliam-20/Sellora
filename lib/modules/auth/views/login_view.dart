import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../controllers/auth_controller.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  // Owned by State rather than created in build() — build() re-runs on
  // any rebuild (a responsive layout reads MediaQuery, which is exactly
  // that trigger), and a fresh TextEditingController each time would
  // silently wipe whatever the user had typed.
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuthController>();
    final args = Get.arguments as Map?;
    final intent = args?['intent'] as String? ?? 'buyer';

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: context.pageHorizontalPadding, vertical: AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 440,
            child: Form(
              key: _formKey,
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
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: Validators.email,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: Validators.password,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        if (_emailCtrl.text.trim().isEmpty || Validators.email(_emailCtrl.text) != null) {
                          Get.snackbar('Enter your email first', 'Then tap "Forgot password" again.');
                          return;
                        }
                        await controller.sendReset(_emailCtrl.text.trim());
                        Get.snackbar('Check your email', 'We sent a password reset link to ${_emailCtrl.text.trim()}.');
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
                                if (_formKey.currentState!.validate()) {
                                  controller.signIn(email: _emailCtrl.text.trim(), password: _passwordCtrl.text);
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
                        intent == 'seller' ? 'New seller? Create a store' : 'New here? Create an account',
                      ),
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
