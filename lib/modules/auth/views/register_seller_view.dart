import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../controllers/auth_controller.dart';

class RegisterSellerView extends StatefulWidget {
  const RegisterSellerView({super.key});

  @override
  State<RegisterSellerView> createState() => _RegisterSellerViewState();
}

class _RegisterSellerViewState extends State<RegisterSellerView> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _storeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _storeCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Create your store')),
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
                  Text('Start selling on Sellora', style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Pick a plan next — you can list products the moment your subscription is active.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Your full name'),
                    validator: (v) => Validators.notEmpty(v, label: 'Name'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _storeCtrl,
                    decoration: const InputDecoration(labelText: 'Store name'),
                    validator: (v) => Validators.notEmpty(v, label: 'Store name'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: Validators.email,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'M-Pesa phone number', hintText: '07XXXXXXXX'),
                    validator: Validators.mpesaPhone,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _passwordCtrl,
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
                                if (_formKey.currentState!.validate()) {
                                  controller.registerSeller(
                                    name: _nameCtrl.text.trim(),
                                    email: _emailCtrl.text.trim(),
                                    password: _passwordCtrl.text,
                                    storeName: _storeCtrl.text.trim(),
                                    phone: _phoneCtrl.text.trim(),
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
      ),
    );
  }
}
