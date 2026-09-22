import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../controllers/auth_controller.dart';

/// Sellora's own sign-in — seller/admin only. There is no buyer path here
/// (or anywhere else in Sellora's own auth flow): a buyer signs in as a
/// customer of a specific store, from that store's own `/s/{slug}/login`
/// page (see lib/modules/storefront/storefront_login_view.dart).
///
/// Laid out as a single-purpose SaaS login: a marketing panel next to the
/// sign-in form on wide screens, form-only on narrow ones.
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
    final form = _SignInForm(
      formKey: _formKey,
      emailCtrl: _emailCtrl,
      passwordCtrl: _passwordCtrl,
      controller: controller,
    );

    return Scaffold(
      backgroundColor: AppColors.cloud,
      body: SafeArea(
        child: context.isWide
            ? Row(
                children: [
                  const Expanded(child: _MarketingPanel()),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
                        child: ResponsiveCenter(maxWidth: 420, child: form),
                      ),
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                    horizontal: context.pageHorizontalPadding,
                    vertical: AppSpacing.lg),
                child: ResponsiveCenter(maxWidth: 440, child: form),
              ),
      ),
    );
  }
}

class _SignInForm extends StatelessWidget {
  const _SignInForm({
    required this.formKey,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.controller,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome back', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: AppSpacing.xs),
          Text('Sign in to manage your storefront.',
              style: Theme.of(context).textTheme.bodyMedium),
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
                if (emailCtrl.text.trim().isEmpty ||
                    Validators.email(emailCtrl.text) != null) {
                  Get.snackbar('Enter your email first',
                      'Then tap "Forgot password" again.');
                  return;
                }
                await controller.sendReset(emailCtrl.text.trim());
                Get.snackbar('Check your email',
                    'We sent a password reset link to ${emailCtrl.text.trim()}.');
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                          controller.signIn(
                              email: emailCtrl.text.trim(),
                              password: passwordCtrl.text);
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
              onPressed: () => Get.toNamed(Routes.registerSeller),
              child: const Text('New seller? Create a store'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The left-hand panel on wide screens — hidden on narrow ones, same as
/// any single-purpose SaaS login (the form is the thing that matters on a
/// phone). Every claim here is pulled from copy already made elsewhere in
/// the app (see MarketingView) rather than invented for this panel.
class _MarketingPanel extends StatelessWidget {
  const _MarketingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      color: AppColors.cargoNavy,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => Get.offAllNamed(Routes.marketing),
              child: Text('Sellora',
                  style: GoogleFonts.fraunces(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: AppColors.cloud)),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              "You're live in minutes — no developer required.",
              style: GoogleFonts.fraunces(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                height: 1.15,
                color: AppColors.cloud,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.cloud,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.format_quote,
                      color: AppColors.manifestGoldDeep, size: 28),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "Listing products and getting paid just worked — I didn't "
                    'touch a line of code setting up my store.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic, height: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Amina',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text("Amina's Curated Picks",
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.slate)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _TrustBadge('M-Pesa & card checkout, built in'),
            const SizedBox(height: AppSpacing.sm),
            const _TrustBadge('Every order server-verified before it\'s paid'),
            const SizedBox(height: AppSpacing.sm),
            const _TrustBadge('Your own storefront at sellora.app/s/you'),
          ],
        ),
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: AppColors.horizonTeal, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(label,
              style:
                  const TextStyle(color: AppColors.slateLight, fontSize: 14)),
        ),
      ],
    );
  }
}
