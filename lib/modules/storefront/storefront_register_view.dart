import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/theme/app_metrics.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../auth/controllers/auth_controller.dart';
import 'store_scope.dart';

/// A buyer registers as a customer of one specific store — reached only
/// from that store's own URL (`/s/{slug}/register`), never from Sellora's
/// own (seller-only) login. See lib/modules/auth/views/login_view.dart.
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
  final StoreScope _scope = Get.find<StoreScope>();

  @override
  void initState() {
    super.initState();
    final slug = Get.parameters['slug'];
    if (slug != null && slug.isNotEmpty) {
      // Deferred a frame: calling this synchronously here flips
      // StoreScope.isResolving (an Rx an Obx below depends on) while this
      // very widget is still mid-build (initState runs during Element.mount),
      // which throws "setState()/markNeedsBuild() called during build" and
      // leaves the page stuck on its loading spinner forever.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scope.resolveSlug(slug));
    }
  }

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

    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: SafeArea(
        child: Obx(() {
          if (_scope.isResolving.value) {
            return const Center(child: SelloraLoader());
          }
          final store = _scope.current.value;
          if (store == null) {
            return Center(
              child: Text(_scope.errorMessage.value ??
                  'This storefront could not be found.'),
            );
          }
          return SingleChildScrollView(
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
                    Text('Join ${store.name}',
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
                                      storeId: store.id,
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
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: TextButton(
                        onPressed: () => Get.offNamed('/s/${store.slug}/login'),
                        child: const Text('Already have an account? Sign in'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
