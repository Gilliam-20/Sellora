import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/theme/app_metrics.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../auth/controllers/auth_controller.dart';
import 'store_scope.dart';

/// A buyer's sign-in as a customer of one specific store — reached only
/// from that store's own URL (`/s/{slug}/login`), never from Sellora's own
/// (seller-only) login. See lib/modules/auth/views/login_view.dart.
class StorefrontLoginView extends StatefulWidget {
  const StorefrontLoginView({super.key});

  @override
  State<StorefrontLoginView> createState() => _StorefrontLoginViewState();
}

class _StorefrontLoginViewState extends State<StorefrontLoginView> {
  final _formKey = GlobalKey<FormState>();
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
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
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
                    Text('Welcome back',
                        style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text('Sign in to keep shopping at ${store.name}.',
                        style: Theme.of(context).textTheme.bodyMedium),
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
                                    controller.signInToStore(
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
                              : const Text('Sign in'),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Center(
                      child: TextButton(
                        onPressed: () =>
                            Get.toNamed('/s/${store.slug}/register'),
                        child: const Text('New here? Create an account'),
                      ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: () => Get.offNamed('/s/${store.slug}'),
                        child: Text('Back to ${store.name}'),
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
