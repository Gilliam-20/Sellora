import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import 'checkout_controller.dart';

class CheckoutView extends StatefulWidget {
  const CheckoutView({super.key});

  @override
  State<CheckoutView> createState() => _CheckoutViewState();
}

class _CheckoutViewState extends State<CheckoutView> {
  // Owned here rather than created in build() — a rebuild (e.g. from
  // the responsive width check below) would otherwise hand every field
  // a brand-new, empty controller and silently wipe what the buyer typed.
  final _formKey = GlobalKey<FormState>();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<CheckoutController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: context.pageHorizontalPadding, vertical: AppSpacing.lg),
        child: ResponsiveCenter(
          maxWidth: 560,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order summary', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Obx(
                  () => Column(
                    children: controller.cartRepo.items
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(child: Text('${item.quantity}x ${item.product.title}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                                Text(Formatters.currency(item.lineTotal)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const Divider(height: AppSpacing.lg),
                Obx(
                  () => Row(
                    children: [
                      Text('Total', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      Text(Formatters.currency(controller.cartRepo.subtotal), style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Shipping address', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Street, city, country'),
                  validator: (v) => Validators.notEmpty(v, label: 'Address'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Pay with M-Pesa', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: '07XXXXXXXX'),
                  validator: Validators.mpesaPhone,
                ),
                const SizedBox(height: AppSpacing.md),
                Obx(() {
                  final error = controller.errorMessage.value;
                  if (error == null) return const SizedBox.shrink();
                  return Text(error, style: const TextStyle(color: AppColors.danger));
                }),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Obx(
        () => BottomActionBar(
          label: 'Pay & place order',
          isLoading: controller.isPlacingOrder.value,
          trailingText: Formatters.currency(controller.cartRepo.subtotal),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              controller.placeOrder(address: _addressCtrl.text.trim(), mpesaPhone: _phoneCtrl.text.trim());
            }
          },
        ),
      ),
    );
  }
}
