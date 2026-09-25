import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/i18n/countries.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/currency_service.dart';
import '../../storefront/store_scope.dart';
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

  /// Only the countries in the store's enabled shipping zones (see
  /// `StoreModel.shippingZones`), Kenya first. Falls back to every
  /// configured country if a store somehow has no zones, rather than
  /// leaving checkout with an empty dropdown.
  late final List<CountryConfig> _countries = () {
    final zones = ShippingZone.parseAll(
        Get.find<StoreScope>().current.value?.shippingZones ??
            StoreModel.allShippingZoneIds);
    final countries = Countries.forZones(zones);
    return countries.isEmpty
        ? Countries.forZones(ShippingZone.values)
        : countries;
  }();
  late String _countryCode = _countries.first.code;
  late PaymentMethodType _method =
      Countries.resolve(_countryCode).paymentMethods.first;

  void _selectCountry(String code) {
    final methods = Countries.resolve(code).paymentMethods;
    setState(() {
      _countryCode = code;
      if (!methods.contains(_method)) _method = methods.first;
    });
  }

  @override
  void initState() {
    super.initState();
    // Quote shipping for the default country as soon as the screen opens,
    // rather than leaving the breakdown at $0 until the buyer touches the
    // country dropdown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Get.find<CheckoutController>().refreshShippingEstimate(_countryCode);
      }
    });
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<CheckoutController>();
    final user = Get.find<AuthRepository>().cachedUser;
    final slug = Get.parameters['slug'];
    final signedInHere = user != null &&
        user.role == UserRole.buyer &&
        controller.cartRepo.storeId != null &&
        user.storeId == controller.cartRepo.storeId;

    if (!signedInHere) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sign in to complete your order',
          message: 'Your cart is saved — sign in as a customer of this '
              'store to finish checking out.',
          actionLabel: 'Sign in',
          onAction: () => Get.toNamed('/s/$slug/login'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
            horizontal: context.pageHorizontalPadding, vertical: AppSpacing.lg),
        child: ResponsiveCenter(
          maxWidth: 560,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order summary',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Obx(
                  () => Column(
                    children: controller.cartRepo.items
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text(
                                        '${item.quantity}x ${item.product.title}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                                Text(Get.find<CurrencyService>().format(
                                    item.lineTotal,
                                    fromCode: item.product.currency)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const Divider(height: AppSpacing.lg),
                Obx(() {
                  final currencyService = Get.find<CurrencyService>();
                  final currency = controller.cartRepo.currency;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CostRow(
                        label: 'Subtotal',
                        value: currencyService.format(
                            controller.cartRepo.subtotal,
                            fromCode: currency),
                      ),
                      const SizedBox(height: 6),
                      _CostRow(
                        label: 'Shipping',
                        value: controller.isEstimatingShipping.value
                            ? 'Calculating…'
                            : currencyService.format(controller.shippingFee,
                                fromCode: currency),
                      ),
                      const Divider(height: AppSpacing.lg),
                      Row(
                        children: [
                          Text('Total',
                              style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          Text(
                              currencyService.format(controller.total,
                                  fromCode: currency),
                              style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                    ],
                  );
                }),
                const SizedBox(height: AppSpacing.lg),
                Text('Shipping address',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  value: _countryCode,
                  decoration: const InputDecoration(labelText: 'Country'),
                  items: _countries
                      .map((c) => DropdownMenuItem(
                            value: c.code,
                            child: Text(c.name),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _selectCountry(v);
                      controller.refreshShippingEstimate(v);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Obx(() {
                  if (controller.isEstimatingShipping.value) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Text('Finding shipping options…'),
                    );
                  }
                  if (controller.shippingOptions.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final currencyService = Get.find<CurrencyService>();
                  final currency = controller.cartRepo.currency;
                  final selected = controller.selectedShippingOption.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Shipment type',
                          style: Theme.of(context).textTheme.titleMedium),
                      ...controller.shippingOptions.map(
                        (option) => RadioListTile<String>(
                          value: option.logisticName,
                          groupValue: selected?.logisticName,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (_) =>
                              controller.selectShippingOption(option),
                          title: Text(option.logisticName),
                          subtitle: option.estimatedDelivery != null
                              ? Text(option.estimatedDelivery!)
                              : null,
                          secondary: Text(currencyService.format(
                              controller.optionCost(option),
                              fromCode: currency)),
                        ),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Street, city'),
                  validator: (v) => Validators.notEmpty(v, label: 'Address'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Payment', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                ...Countries.resolve(_countryCode).paymentMethods.map(
                      (m) => RadioListTile<PaymentMethodType>(
                        value: m,
                        groupValue: _method,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) {
                          if (v != null) setState(() => _method = v);
                        },
                        title: Text(m.label),
                        subtitle: Text(m == PaymentMethodType.mpesa
                            ? 'STK push to a Kenyan Safaricom number'
                            : 'Visa or Mastercard, on a secure payment page'),
                      ),
                    ),
                if (_method == PaymentMethodType.mpesa) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'M-Pesa number', hintText: '07XXXXXXXX'),
                    validator: Validators.mpesaPhone,
                  ),
                ],
                Obx(() {
                  final currency = controller.cartRepo.currency;
                  final display = Get.find<CurrencyService>();
                  if (!display.isConverted(currency)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(
                      'Prices are shown in ${display.code.value}, converted '
                      'from $currency at an indicative rate. The amount '
                      'charged is confirmed on the payment step.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }),
                const SizedBox(height: AppSpacing.md),
                Obx(() {
                  final error = controller.errorMessage.value;
                  if (error == null) return const SizedBox.shrink();
                  return Text(error,
                      style: const TextStyle(color: AppColors.danger));
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
          trailingText: Get.find<CurrencyService>()
              .format(controller.total, fromCode: controller.cartRepo.currency),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              controller.placeOrder(
                  address: _addressCtrl.text.trim(),
                  countryCode: _countryCode,
                  method: _method,
                  mpesaPhone: _phoneCtrl.text.trim());
            }
          },
        ),
      ),
    );
  }
}

/// One line of the checkout cost breakdown (Subtotal / Shipping / Total).
class _CostRow extends StatelessWidget {
  const _CostRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
