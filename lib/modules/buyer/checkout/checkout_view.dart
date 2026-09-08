import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import 'checkout_controller.dart';

class CheckoutView extends GetView<CheckoutController> {
  const CheckoutView({super.key});

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final addressCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: formKey,
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
                controller: addressCtrl,
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'Street, city, country'),
                validator: (v) => Validators.notEmpty(v, label: 'Address'),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Pay with M-Pesa', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: phoneCtrl,
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
      bottomNavigationBar: Obx(
        () => BottomActionBar(
          label: 'Pay & place order',
          isLoading: controller.isPlacingOrder.value,
          trailingText: Formatters.currency(controller.cartRepo.subtotal),
          onPressed: () {
            if (formKey.currentState!.validate()) {
              controller.placeOrder(address: addressCtrl.text.trim(), mpesaPhone: phoneCtrl.text.trim());
            }
          },
        ),
      ),
    );
  }
}
