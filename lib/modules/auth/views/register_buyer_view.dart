import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/validators.dart';
import '../controllers/auth_controller.dart';

class RegisterBuyerView extends GetView<AuthController> {
  const RegisterBuyerView({super.key});

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Join Sellora', style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: AppSpacing.xs),
                Text('Shop products sourced from sellers worldwide.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) => Validators.notEmpty(v, label: 'Name'),
                ),
                const SizedBox(height: AppSpacing.md),
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
                const SizedBox(height: AppSpacing.md),
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
                                controller.registerBuyer(
                                  name: nameCtrl.text.trim(),
                                  email: emailCtrl.text.trim(),
                                  password: passwordCtrl.text,
                                );
                              }
                            },
                      child: controller.isLoading.value
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Create account'),
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
