import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/routes/app_routes.dart';
import '../../../core/i18n/countries.dart';
import '../../../core/i18n/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/discount_model.dart';
import '../../../data/models/freight_estimate.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/cart_repository.dart';
import '../../../data/repositories/discount_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/services/currency_service.dart';
import '../../../data/services/order_payment_provider.dart';

class CheckoutController extends GetxController {
  final CartRepository cartRepo = Get.find<CartRepository>();
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();
  final NotificationRepository _notificationRepo =
      Get.find<NotificationRepository>();
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final OrderPaymentProvider _payments = Get.find<OrderPaymentProvider>();
  final DiscountRepository _discountRepo = Get.find<DiscountRepository>();

  final isPlacingOrder = false.obs;
  final errorMessage = RxnString();

  /// Every CJ shipment type available for the whole cart to the currently
  /// selected destination, from one combined [ProductRepository.shippingOptions]
  /// call — the same call shape `createOrder` quotes from server-side, so a
  /// method picked here is guaranteed to still resolve there (barring a
  /// quote change in between).
  final shippingOptions = <FreightOption>[].obs;
  final selectedShippingOption = Rxn<FreightOption>();
  final isEstimatingShipping = false.obs;

  /// The buyer's chosen shipment cost, or 0 while nothing is selected yet
  /// (empty cart, still loading, or no option available for this address).
  /// Display-only in mock mode (charged as quoted); in real mode
  /// `createOrder` re-validates [selectedShippingOption]'s name and
  /// re-derives the price itself from CJ's own quote (see
  /// supabase/functions/_shared/orders.js) — this never trusts its own [cost] value.
  double get shippingFee => shippingFeeMoney.toMajor();

  /// CJ quotes freight in its own currency (USD) while the cart is priced in
  /// the listings' currency — converted here before the two are ever added,
  /// rather than summing two currencies' raw numbers.
  Money get shippingFeeMoney {
    final option = selectedShippingOption.value;
    if (option == null) return Money.zero(cartRepo.currency);
    return _toCartCurrency(option);
  }

  /// One quoted [option]'s cost in the cart's currency, for listing each
  /// shipment type.
  double optionCost(FreightOption option) => _toCartCurrency(option).toMajor();

  Money _toCartCurrency(FreightOption option) =>
      Get.find<CurrencyService>().convertMoney(
          Money.fromMajor(option.cost, option.currency), cartRepo.currency);

  double get total =>
      (cartRepo.subtotalMoney - discountMoney + shippingFeeMoney).toMajor();

  // ---- Discount code ------------------------------------------------------

  /// The code the buyer applied, as `storefront_discount` described it. A
  /// preview only: `createOrder` re-checks and re-prices it, and its answer
  /// is what the order carries.
  final appliedDiscount = Rxn<DiscountModel>();
  final discountError = RxnString();
  final isApplyingDiscount = false.obs;

  List<DiscountLine> get _discountLines => [
        for (final item in cartRepo.items)
          (productId: item.product.id, lineTotal: item.lineTotal),
      ];

  /// What the applied code takes off the current cart, in the cart's
  /// currency (the listings' own, which is also the code's).
  Money get discountMoney {
    final discount = appliedDiscount.value;
    if (discount == null) return Money.zero(cartRepo.currency);
    final quote = discount.quote(_discountLines);
    return Money.fromMajor(
        quote.refusal == null ? quote.amount : 0, cartRepo.currency);
  }

  double get discountAmount => discountMoney.toMajor();

  Future<void> applyDiscount(String raw) async {
    final code = DiscountModel.normalizeCode(raw);
    discountError.value = null;
    if (code.isEmpty) return;
    final storeId = cartRepo.storeId;
    if (!DiscountModel.codePattern.hasMatch(code) || storeId == null) {
      discountError.value = _invalidCode;
      return;
    }
    isApplyingDiscount.value = true;
    try {
      final discount = await _discountRepo.lookup(storeId, code);
      if (discount == null) {
        discountError.value = _invalidCode;
        return;
      }
      final quote = discount.quote(_discountLines);
      if (quote.refusal != null) {
        discountError.value = quote.refusal;
        return;
      }
      appliedDiscount.value = discount;
    } catch (_) {
      discountError.value = 'Couldn\'t check that code. Please try again.';
    } finally {
      isApplyingDiscount.value = false;
    }
  }

  void removeDiscount() {
    appliedDiscount.value = null;
    discountError.value = null;
  }

  static const _invalidCode = 'This discount code isn\'t valid';

  /// Re-quotes [shippingOptions] for [countryCode]. Called on load and
  /// whenever the buyer changes the destination country — never blocks or
  /// fails checkout itself, since it's only a display/selection breakdown.
  /// Keeps the buyer's current pick selected across a re-quote when that
  /// same method is still offered; otherwise defaults to the cheapest.
  Future<void> refreshShippingEstimate(String countryCode) async {
    if (cartRepo.items.isEmpty) {
      shippingOptions.clear();
      selectedShippingOption.value = null;
      return;
    }
    isEstimatingShipping.value = true;
    try {
      final products = cartRepo.items.map((item) {
        final vid = item.selectedVariant?.vid ??
            (item.product.variants.isNotEmpty
                ? item.product.variants.first.vid
                : item.product.cjProductId);
        return {'vid': vid, 'quantity': item.quantity};
      }).toList();
      final options = await _productRepo.shippingOptions(
        products: products,
        endCountryCode: countryCode,
      );
      shippingOptions.assignAll(options);

      final previousName = selectedShippingOption.value?.logisticName;
      FreightOption? next;
      if (previousName != null) {
        for (final option in options) {
          if (option.logisticName == previousName) {
            next = option;
            break;
          }
        }
      }
      next ??= options.isEmpty
          ? null
          : options.reduce((a, b) => a.cost <= b.cost ? a : b);
      selectedShippingOption.value = next;
    } catch (_) {
      shippingOptions.clear();
      selectedShippingOption.value = null;
    } finally {
      isEstimatingShipping.value = false;
    }
  }

  /// The buyer picking a shipment type from [shippingOptions] in the UI.
  void selectShippingOption(FreightOption option) {
    selectedShippingOption.value = option;
  }

  /// Places the order and starts payment by [method]. [mpesaPhone] is
  /// required for [PaymentMethodType.mpesa] and ignored otherwise. A method
  /// the destination country doesn't support (M-Pesa outside Kenya) is
  /// refused here too, not just hidden in the UI.
  Future<void> placeOrder({
    required ShippingAddress address,
    required PaymentMethodType method,
    String? mpesaPhone,
  }) async {
    final user = _authRepo.cachedUser;
    if (user == null || cartRepo.items.isEmpty) return;
    if (!Countries.resolve(address.countryCode).paymentMethods.contains(method) ||
        !_payments.supports(method)) {
      errorMessage.value =
          '${method.label} isn\'t available for this shipping country.';
      return;
    }

    isPlacingOrder.value = true;
    errorMessage.value = null;
    try {
      // A real multi-seller cart would split into one order per seller.
      // Simplified here to a single order against the first item's
      // seller — matches supabase/functions/_shared/orders.js's createOrder, which
      // rejects a cart mixing sellers rather than silently misattributing
      // it.
      final sellerId =
          cartRepo.items.first.product.sellerId ?? 'unknown-seller';
      final items = cartRepo.items
          .map((i) => OrderItem(
                productId: i.product.id,
                cjProductId: i.product.cjProductId,
                title: i.product.title,
                imageUrl: i.product.imageUrl,
                quantity: i.quantity,
                unitPrice: i.product.sellPrice,
                variantId: i.selectedVariant?.vid,
                variantLabel: i.selectedVariant?.label,
              ))
          .toList();

      // Create the order server-side — re-priced from listings, ignoring
      // whatever total this draft carries — *before* starting payment, so
      // the server-assigned order id can be the payment's orderId. See
      // SupabaseOrderRepository.placeOrder and supabase/functions/api/index.ts's
      // intasendWebhook, which is what actually confirms payment and
      // starts CJ fulfillment; this controller does neither itself.
      final draft = OrderModel(
        id: '',
        code: '',
        buyerId: user.uid,
        sellerId: sellerId,
        storeId: cartRepo.storeId,
        items: items,
        status: OrderStatus.pending,
        total: total,
        currency: cartRepo.currency,
        shippingAddress: address,
        paymentMethod: method.orderLabel,
        createdAt: DateTime.now(),
        shippingFee: shippingFee,
        logisticName: selectedShippingOption.value?.logisticName,
        discountCode: appliedDiscount.value?.code,
      );
      final OrderModel order;
      try {
        order = await _orderRepo.placeOrder(draft);
      } on ApiException catch (e) {
        // A 4xx from createOrder (a refused address, an unavailable item)
        // is written for the buyer; anything else isn't.
        final status = e.statusCode ?? 0;
        errorMessage.value = status >= 400 && status < 500
            ? e.message
            : 'Couldn\'t place your order. Please try again.';
        return;
      }
      await _notificationRepo.notifyOrderPlaced(order);

      // Like the order itself, completion is confirmed server-side (the
      // provider's webhook), not by this client.
      final started = await _payments.startOrderPayment(
        orderId: order.id,
        method: method,
        phone: method == PaymentMethodType.mpesa
            ? Formatters.toMpesaFormat(mpesaPhone ?? '')
            : null,
        // Back to the storefront (hash routing), not this checkout page —
        // the cart is already cleared by then.
        redirectUrl: kIsWeb
            ? Uri.base
                .replace(fragment: '/s/${Get.parameters['slug'] ?? ''}')
                .toString()
            : null,
      );
      switch (started) {
        case PaymentPromptSent():
          _onOrderPlaced(order.code,
              'Order ${order.code} placed — complete the ${method.label} prompt on your phone to finish payment.');
        case PaymentRedirect(:final url):
          await launchUrl(url, mode: LaunchMode.externalApplication);
          _onOrderPlaced(order.code,
              'Order ${order.code} placed — finish paying in the page that just opened.');
      }
    } catch (e) {
      errorMessage.value = method == PaymentMethodType.mpesa
          ? 'Payment didn\'t go through. Check the number and try again.'
          : 'Couldn\'t start card payment. Please try again.';
    } finally {
      isPlacingOrder.value = false;
    }
  }

  void _onOrderPlaced(String code, String message) {
    cartRepo.clear();
    final slug = Get.parameters['slug'];
    Get.offAllNamed(
      slug != null && slug.isNotEmpty ? '/s/$slug' : Routes.marketing,
      arguments: {'tab': 2},
    );
    Get.snackbar('Order placed', message);
  }
}
