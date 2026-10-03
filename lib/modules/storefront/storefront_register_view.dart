import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/theme/app_metrics.dart';
import '../../core/utils/validators.dart';
import '../../data/models/store_model.dart';
import '../auth/controllers/auth_controller.dart';
import 'shell/storefront_auth_scaffold.dart';
import 'shell/storefront_links.dart';

/// A buyer registers as a customer of one specific store, in that store's
/// theme — reached only from that store's own URL (`/s/{slug}/register`),
/// never from Sellora's own (seller-only) login. See
/// lib/modules/auth/views/login_view.dart.
class StorefrontRegisterView extends StatefulWidget {
  const StorefrontRegisterView({super.key});

  @override
  State<StorefrontRegisterView> createState() => _StorefrontRegisterViewState();
}

class _StorefrontRegisterViewState extends State<StorefrontRegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StorefrontAuthScaffold(
        title: 'Create account',
        heading: (store) => 'Join ${store.name}',
        subtitle: (_) => 'Create an account to check out and follow your '
            'orders.',
        form: _form,
      );

  Widget _form(BuildContext context, StoreModel store) {
    final controller = Get.find<AuthController>();
    final scheme = Theme.of(context).colorScheme;
    void submit() {
      if (controller.isLoading.value) return;
      if (_formKey.currentState!.validate()) {
        controller.registerBuyer(
          name: _nameCtrl.text.trim(),
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
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) => Validators.notEmpty(v, label: 'Name'),
            ),
            const SizedBox(height: AppSpacing.md),
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
              validator: Validators.newPassword,
              isNew: true,
              onSubmitted: submit,
            ),
            const SizedBox(height: AppSpacing.md),
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
                      : const Text('Create account'),
                )),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: TextButton(
                onPressed: () => Get.offNamed(
                    StorefrontPaths.keepReturn('/s/${store.slug}/login')),
                child: const Text('Already have an account? Sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
