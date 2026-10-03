import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/store_model.dart';
import '../design/storefront_theme.dart';
import '../storefront_session.dart';
import 'storefront_page.dart';

/// The frame for a store's sign-in and sign-up pages (TODO §21): the
/// store's theme, its name in the top bar (back to its homepage), and a
/// narrow form under a [heading] and [subtitle]. No menu or cart, so
/// nothing leads away mid-form.
class StorefrontAuthScaffold extends StatelessWidget {
  const StorefrontAuthScaffold({
    super.key,
    required this.title,
    required this.heading,
    required this.subtitle,
    required this.form,
  });

  /// The browser tab's page name.
  final String title;
  final String Function(StoreModel store) heading;
  final String Function(StoreModel store) subtitle;
  final Widget Function(BuildContext context, StoreModel store) form;

  @override
  Widget build(BuildContext context) {
    return StorefrontFrame(
      title: title,
      builder: (context, store, design) {
        final style = StoreStyle.of(context);
        final textTheme = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              onTap: () =>
                  Get.offAllNamed(Get.find<StorefrontSession>().path()),
              child: Text(store.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.xl),
              child: ResponsiveCenter(
                maxWidth: 440,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(style.heading(heading(store)),
                        style: style.headingStyle(textTheme.headlineMedium)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(subtitle(store), style: textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.lg),
                    form(context, store),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A password field with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.validator,
    this.label = 'Password',
    this.isNew = false,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String? Function(String?) validator;
  final String label;

  /// A new password (sign-up) rather than an existing one, for autofill.
  final bool isNew;
  final VoidCallback? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  var _obscured = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _obscured,
        autofillHints: [
          widget.isNew ? AutofillHints.newPassword : AutofillHints.password
        ],
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => widget.onSubmitted?.call(),
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(
            tooltip: _obscured ? 'Show password' : 'Hide password',
            icon: Icon(_obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
        ),
        validator: widget.validator,
      );
}
