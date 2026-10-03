import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/theme/app_metrics.dart';
import '../../core/utils/validators.dart';
import '../../data/models/store_model.dart';
import '../auth/controllers/auth_controller.dart';
import 'shell/storefront_auth_scaffold.dart';
import 'shell/storefront_links.dart';

/// A buyer's sign-in as a customer of one specific store, in that store's
/// theme — reached only from that store's own URL (`/s/{slug}/login`),
/// never from Sellora's own (seller-only) login. See
/// lib/modules/auth/views/login_view.dart.
class StorefrontLoginView extends StatefulWidget {
  const StorefrontLoginView({super.key});

  @override
  State<StorefrontLoginView> createState() => _StorefrontLoginViewState();
}

class _StorefrontLoginViewState extends State<StorefrontLoginView> {
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
  Widget build(BuildContext context) => StorefrontAuthScaffold(
        title: 'Sign in',
        heading: (_) => 'Welcome back',
        subtitle: (store) => 'Sign in to keep shopping at ${store.name}.',
        form: _form,
      );

  Widget _form(BuildContext context, StoreModel store) {
    final controller = Get.find<AuthController>();
    final scheme = Theme.of(context).colorScheme;
    void submit() {
      if (controller.isLoading.value) return;
      if (_formKey.currentState!.validate()) {
        controller.signInToStore(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          storeId: store.id,
        );
      }
    }

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: Validators.email,
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordField(
              controller: _passwordCtrl,
              validator: Validators.password,
              onSubmitted: submit,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  if (_emailCtrl.text.trim().isEmpty ||
                      Validators.email(_emailCtrl.text) != null) {
                    Get.snackbar('Enter your email first',
                        'Then tap "Forgot password" again.');
                    return;
                  }
                  await controller.sendReset(_emailCtrl.text.trim());
                  Get.snackbar('Check your email',
                      'We sent a password reset link to ${_emailCtrl.text.trim()}.');
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
                child: Text(error, style: TextStyle(color: scheme.error)),
              );
            }),
            Obx(() => ElevatedButton(
                  onPressed: controller.isLoading.value ? null : submit,
                  child: controller.isLoading.value
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: scheme.onPrimary),
                        )
                      : const Text('Sign in'),
                )),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: TextButton(
                onPressed: () => Get.offNamed(
                    StorefrontPaths.keepReturn('/s/${store.slug}/register')),
                child: const Text('New here? Create an account'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Get.offAllNamed('/s/${store.slug}'),
                child: Text('Back to ${store.name}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
