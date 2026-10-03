import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/i18n/countries.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/currency_service.dart';
import '../../storefront/store_scope.dart';
import 'checkout_controller.dart';
import '../../storefront/shell/storefront_links.dart';
import '../../storefront/shell/storefront_page.dart';

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
  late final _nameCtrl =
      TextEditingController(text: Get.find<AuthRepository>().cachedUser?.name);
  late final _contactPhoneCtrl =
      TextEditingController(text: Get.find<AuthRepository>().cachedUser?.phone);
  final _line1Ctrl = TextEditingController();
  final _line2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  // M-Pesa: the account's phone, when it's one M-Pesa can charge.
  late final _phoneCtrl = TextEditingController(text: () {
    final phone = Get.find<AuthRepository>().cachedUser?.phone;
    return phone != null && Validators.mpesaPhone(phone) == null ? phone : '';
  }());
  final _discountCtrl = TextEditingController();

  /// Fills the address from the customer's last order here, once loaded.
  Worker? _savedAddressWorker;

  /// Whether the address form was filled from that order.
  var _prefilled = false;

  /// Only into an untouched form: never over what the buyer typed.
  void _prefill(ShippingAddress? address) {
    if (address == null || !mounted || _prefilled) return;
    if (_line1Ctrl.text.isNotEmpty || _cityCtrl.text.isNotEmpty) return;
    final country =
        _countries.where((c) => c.code == address.countryCode).firstOrNull;
    // A country the store no longer ships to would be refused anyway.
    if (country == null) return;
    if (address.fullName.isNotEmpty) _nameCtrl.text = address.fullName;
    if (address.phone.isNotEmpty) _contactPhoneCtrl.text = address.phone;
    _line1Ctrl.text = address.line1;
    _line2Ctrl.text = address.line2 ?? '';
    _cityCtrl.text = address.city;
    _provinceCtrl.text = address.province ?? '';
    _zipCtrl.text = address.zip ?? '';
    _prefilled = true;
    if (country.code != _countryCode) {
      _selectCountry(country.code);
      Get.find<CheckoutController>().refreshShippingEstimate(country.code);
    } else {
      setState(() {});
    }
  }

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
        final controller = Get.find<CheckoutController>();
        controller.refreshShippingEstimate(_countryCode);
        _prefill(controller.savedAddress.value);
        _savedAddressWorker = ever(controller.savedAddress, _prefill);
      }
    });
  }

  @override
  void dispose() {
    _savedAddressWorker?.dispose();
    for (final ctrl in [
      _nameCtrl,
      _contactPhoneCtrl,
      _line1Ctrl,
      _line2Ctrl,
      _cityCtrl,
      _provinceCtrl,
      _zipCtrl,
      _phoneCtrl,
      _discountCtrl,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  /// In the store's theme and on its own: no store menu, so nothing
  /// leads away from paying.
  @override
  Widget build(BuildContext context) => StorefrontFrame(
        title: 'Checkout',
        builder: (context, store, design) => _build(context),
      );

  Widget _build(BuildContext context) {
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
          onAction: () => Get.toNamed(
              '/s/$slug/${StorefrontPaths.loginThen('/s/$slug/${StorefrontPaths.checkout}')}'),
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
                      if (controller.appliedDiscount.value != null) ...[
                        const SizedBox(height: 6),
                        _CostRow(
                          label:
                              'Discount (${controller.appliedDiscount.value!.code})',
                          value: '− ${currencyService.format(
                            controller.discountAmount,
                            fromCode: currency,
                          )}',
                        ),
                      ],
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
                const SizedBox(height: AppSpacing.md),
                _DiscountCodeField(
                    controller: controller, textController: _discountCtrl),
                const SizedBox(height: AppSpacing.lg),
                Text('Shipping address',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_prefilled)
                  Text('Filled in from your last order. Check it\'s still '
                      'right.',
                      style: Theme.of(context).textTheme.bodySmall),
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
                // Everything CJ needs to ship the parcel; createOrder
                // refuses an order missing name, phone, street or city.
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  maxLength: 100,
                  decoration: const InputDecoration(
                      labelText: 'Full name', counterText: ''),
                  validator: (v) => Validators.notEmpty(v, label: 'Name'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _contactPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                      labelText: 'Phone',
                      helperText: 'For the courier, if they need to reach you'),
                  validator: Validators.phone,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _line1Ctrl,
                  autofillHints: const [AutofillHints.streetAddressLine1],
                  maxLength: 200,
                  decoration: const InputDecoration(
                      labelText: 'Street address', counterText: ''),
                  validator: (v) =>
                      Validators.notEmpty(v, label: 'Street address'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _line2Ctrl,
                  autofillHints: const [AutofillHints.streetAddressLine2],
                  maxLength: 200,
                  decoration: const InputDecoration(
                      labelText: 'Apartment, building, floor (optional)',
                      counterText: ''),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.addressCity],
                  maxLength: 100,
                  decoration: const InputDecoration(
                      labelText: 'City / town', counterText: ''),
                  validator: (v) => Validators.notEmpty(v, label: 'City'),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _provinceCtrl,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.addressState],
                        maxLength: 100,
                        decoration: const InputDecoration(
                            labelText: 'County / state (optional)',
                            counterText: ''),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _zipCtrl,
                        autofillHints: const [AutofillHints.postalCode],
                        maxLength: 20,
                        decoration: const InputDecoration(
                            labelText: 'Postal code (optional)',
                            counterText: ''),
                      ),
                    ),
                  ],
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
                  address: ShippingAddress(
                    countryCode: _countryCode,
                    fullName: _nameCtrl.text.trim(),
                    phone: _contactPhoneCtrl.text.trim(),
                    email: Get.find<AuthRepository>().cachedUser?.email,
                    line1: _line1Ctrl.text.trim(),
                    line2: _line2Ctrl.text.trim(),
                    city: _cityCtrl.text.trim(),
                    province: _provinceCtrl.text.trim(),
                    zip: _zipCtrl.text.trim(),
                  ),
                  method: _method,
                  mpesaPhone: _phoneCtrl.text.trim());
            }
          },
        ),
      ),
    );
  }
}

/// Entry for one of the store's discount codes. Once applied it shows the
/// code and what it's worth, with a way to take it off again.
class _DiscountCodeField extends StatelessWidget {
  const _DiscountCodeField(
      {required this.controller, required this.textController});

  final CheckoutController controller;
  final TextEditingController textController;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final applied = controller.appliedDiscount.value;
      if (applied != null) {
        return Row(
          children: [
            const Icon(Icons.local_offer_outlined,
                size: 18, color: AppColors.horizonTeal),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('${applied.code} applied — ${applied.summary}',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            TextButton(
              onPressed: () {
                textController.clear();
                controller.removeDiscount();
              },
              child: const Text('Remove'),
            ),
          ],
        );
      }
      final busy = controller.isApplyingDiscount.value;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: textController,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: busy ? null : controller.applyDiscount,
              decoration: InputDecoration(
                labelText: 'Discount code',
                errorText: controller.discountError.value,
                errorMaxLines: 2,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: OutlinedButton(
              onPressed: busy
                  ? null
                  : () => controller.applyDiscount(textController.text),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Apply'),
            ),
          ),
        ],
      );
    });
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
