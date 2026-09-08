import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/validators.dart';
import '../controllers/auth_controller.dart';

class RegisterSellerView extends GetView<AuthController> {
  const RegisterSellerView({super.key});

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final storeCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Create your store')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Start selling on Sellora', style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Pick a plan next — you can list products the moment your subscription is active.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Your full name'),
                  validator: (v) => Validators.notEmpty(v, label: 'Name'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: storeCtrl,
                  decoration: const InputDecoration(labelText: 'Store name'),
                  validator: (v) => Validators.notEmpty(v, label: 'Store name'),
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
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'M-Pesa phone number', hintText: '07XXXXXXXX'),
                  validator: Validators.mpesaPhone,
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
                    child: Text(error, style: const TextStyle(color: AppColors.danger)),
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
                                controller.registerSeller(
                                  name: nameCtrl.text.trim(),
                                  email: emailCtrl.text.trim(),
                                  password: passwordCtrl.text,
                                  storeName: storeCtrl.text.trim(),
                                  phone: phoneCtrl.text.trim(),
                                );
                              }
                            },
                      child: controller.isLoading.value
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink),
                            )
                          : const Text('Continue to plans'),
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
