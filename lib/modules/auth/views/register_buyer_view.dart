import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../controllers/auth_controller.dart';

class RegisterBuyerView extends StatefulWidget {
  const RegisterBuyerView({super.key});

  @override
  State<RegisterBuyerView> createState() => _RegisterBuyerViewState();
}

class _RegisterBuyerViewState extends State<RegisterBuyerView> {
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
  Widget build(BuildContext context) {
    final controller = Get.find<AuthController>();
    final args = Get.arguments as Map?;
    final storeId = args?['storeId'] as String?;
    final storeName = args?['storeName'] as String?;

    // Reached this screen without picking a store first (e.g. a stale
    // deep link) — send them to the picker rather than register a buyer
    // with nowhere to shop.
    if (storeId == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Get.offNamed(Routes.storeSelect));
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: context.pageHorizontalPadding,
              vertical: AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 440,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Join ${storeName ?? 'the store'}',
                      style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Create a buyer account to shop here.',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) => Validators.notEmpty(v, label: 'Name'),
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
                      child: Text(error,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
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
                                  controller.registerBuyer(
                                    name: _nameCtrl.text.trim(),
                                    email: _emailCtrl.text.trim(),
                                    password: _passwordCtrl.text,
                                    storeId: storeId,
                                  );
                                }
                              },
                        child: controller.isLoading.value
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
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
      ),
    );
  }
}
