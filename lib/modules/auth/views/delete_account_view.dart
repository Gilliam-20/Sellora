import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../controllers/delete_account_controller.dart';

/// The public account-deletion page (`/#/delete-account` on the web build),
/// which the Play Console's data-safety form links to. Works for buyers and
/// sellers alike, without the app installed.
class DeleteAccountView extends StatefulWidget {
  const DeleteAccountView({super.key});

  @override
  State<DeleteAccountView> createState() => _DeleteAccountViewState();
}

class _DeleteAccountViewState extends State<DeleteAccountView> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _confirmed = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<DeleteAccountController>();

    return Scaffold(
      backgroundColor: AppColors.cloud,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.xl),
            child: ResponsiveCenter(
              maxWidth: 420,
              child: Obx(() => controller.deleted.value
                  ? _buildDone(context)
                  : _buildForm(context, controller)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your account is deleted', style: textTheme.displaySmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your profile and personal details have been removed, and the '
          'account can no longer sign in.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () =>
                Get.offAllNamed(kIsWeb ? Routes.marketing : Routes.roleSelect),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context, DeleteAccountController controller) {
    final textTheme = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delete your Sellora account', style: textTheme.displaySmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This works for shopper and seller accounts. You can also do it '
            'in the app, from your profile.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('What\'s removed', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your name, email, phone number, photo, delivery addresses, '
            'notifications and sign-in. For a seller, every product is '
            'unlisted, store images are removed and the plan is cancelled.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('What\'s kept', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Records of past orders and payments, without your name or '
            'address, because tax and payment law requires them. If a paid '
            'order is still on its way, you can delete once it arrives.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            validator: Validators.email,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Password'),
            validator: Validators.password,
          ),
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            value: _confirmed,
            onChanged: (value) => setState(() => _confirmed = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I understand this can\'t be undone'),
          ),
          const SizedBox(height: AppSpacing.md),
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
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: controller.isLoading.value || !_confirmed
                    ? null
                    : () {
                        if (_formKey.currentState!.validate()) {
                          controller.deleteAccount(
                              email: _emailCtrl.text,
                              password: _passwordCtrl.text);
                        }
                      },
                child: controller.isLoading.value
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Delete my account'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
