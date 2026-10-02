import '../../core/i18n/countries.dart';

enum PaymentStatus { pending, completed, failed }

/// What happens after a payment is started, so checkout can respond without
/// knowing which provider it's talking to.
sealed class PaymentStart {
  const PaymentStart();
}

/// The customer was sent a prompt (an M-Pesa STK push) and finishes paying
/// on their phone.
class PaymentPromptSent extends PaymentStart {
  const PaymentPromptSent(this.reference);
  final String reference;
}

/// The customer finishes paying on the provider's hosted page at [url].
class PaymentRedirect extends PaymentStart {
  const PaymentRedirect(this.url);
  final Uri url;
}

/// Takes payment for an order that `OrderRepository.placeOrder` already
/// created server-side. Every implementation goes through Sellora's `api`
/// Edge Function, which prices the charge from the order itself and holds
/// the provider's keys. Payment is only ever confirmed server-side (webhook
/// or [confirmOrderPayment]), never by the client.
///
/// Checkout depends on this, not on a concrete provider, so another
/// provider is a new implementation bound in InitialBinding rather than a
/// change to checkout. The server already records `orders.payment_provider`
/// and dispatches refunds on it (`supabase/functions/_shared/refunds.js`).
abstract class OrderPaymentProvider {
  /// Matches `orders.payment_provider`, e.g. `INTASEND`.
  String get id;

  /// Whether this provider can take [method] at all. Which methods a
  /// destination offers is [CountryConfig.paymentMethods].
  bool supports(PaymentMethodType method);

  /// Starts paying [orderId] by [method]. [phone] is required for
  /// [PaymentMethodType.mpesa]; [redirectUrl] is where a hosted page returns
  /// the customer.
  Future<PaymentStart> startOrderPayment({
    required String orderId,
    required PaymentMethodType method,
    String? phone,
    String? redirectUrl,
  });

  /// Asks the server whether [orderId] has been paid.
  Future<PaymentStatus> confirmOrderPayment(String orderId);
}
