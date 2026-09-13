import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';

enum PaymentStatus { pending, completed, failed }

class PaymentResult {
  PaymentResult(
      {required this.reference, required this.status, this.checkoutUrl});
  final String reference;
  final PaymentStatus status;
  final String?
      checkoutUrl; // for card/hosted checkout, opened via url_launcher
}

/// Wraps IntaSend for both seller subscription billing and buyer
/// checkout. The IntaSend secret key lives only in Cloud Functions
/// (see /functions/src/intasend.ts); the app just triggers a collection
/// request and polls/observes the resulting status.
class IntasendService extends GetxService {
  final DioClient _dio = Get.find<DioClient>();

  /// Triggers an M-Pesa STK push to [phone] (format 2547XXXXXXXX) for
  /// [amountKes]. Used both for seller subscription payments and for
  /// buyer checkout when they choose M-Pesa.
  Future<PaymentResult> collectMpesa({
    required String phone,
    required double amountKes,
    required String narrative,
  }) async {
    final res = await _dio.post(ApiEndpoints.intasendCollectMpesa, data: {
      'phone_number': phone,
      'amount': amountKes,
      'narrative': narrative,
    });
    return PaymentResult(
      reference:
          res['invoice_id']?.toString() ?? res['reference']?.toString() ?? '',
      status: _statusFrom(res['state']?.toString()),
    );
  }

  /// Hosted checkout link for card payments (used for buyers paying in
  /// USD/EUR/GBP outside Kenya, or sellers who prefer card billing).
  Future<PaymentResult> createCheckout({
    required double amount,
    required String currency,
    required String email,
    required String narrative,
  }) async {
    final res = await _dio.post(ApiEndpoints.intasendCheckout, data: {
      'amount': amount,
      'currency': currency,
      'email': email,
      'narrative': narrative,
    });
    return PaymentResult(
      reference: res['id']?.toString() ?? '',
      status: PaymentStatus.pending,
      checkoutUrl: res['url']?.toString(),
    );
  }

  Future<PaymentStatus> checkStatus(String reference) async {
    final res = await _dio
        .get(ApiEndpoints.intasendStatus, query: {'reference': reference});
    return _statusFrom(res['state']?.toString());
  }

  /// Starts an M-Pesa STK push for a pending subscription billing entry
  /// (see `SubscriptionRepository.subscribeSeller`) — the entry's id is the
  /// payment's reference, the same way an order id is for [collectMpesa].
  /// Calls the new billing-specific Cloud Functions (`{success,data}`
  /// envelope), not [collectMpesa]'s endpoint.
  Future<String> payBillingMpesa({
    required String billingEntryId,
    required String phone,
  }) async {
    final res = await _dio.post(ApiEndpoints.payBillingMpesa, data: {
      'billingEntryId': billingEntryId,
      'phoneNumber': phone,
    });
    final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
    return data['invoiceId']?.toString() ?? '';
  }

  /// Hosted checkout link for a pending subscription billing entry.
  /// [method] is `'CARD-PAYMENT'` or `'GOOGLE-PAY'`.
  Future<String?> payBillingCard({
    required String billingEntryId,
    required String method,
    String? redirectUrl,
  }) async {
    final res = await _dio.post(ApiEndpoints.payBillingCard, data: {
      'billingEntryId': billingEntryId,
      'method': method,
      'redirectUrl': redirectUrl,
    });
    final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
    return data['checkoutUrl']?.toString();
  }

  /// Re-checks a subscription billing entry's payment status directly with
  /// the server (never trusts a client-side guess).
  Future<PaymentStatus> confirmBillingPayment(String billingEntryId) async {
    final res = await _dio.post(ApiEndpoints.confirmBillingPayment, data: {
      'billingEntryId': billingEntryId,
    });
    final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
    if (data['paid'] == true) return PaymentStatus.completed;
    return _statusFrom(data['state']?.toString());
  }

  PaymentStatus _statusFrom(String? state) {
    switch ((state ?? '').toUpperCase()) {
      case 'COMPLETE':
      case 'COMPLETED':
        return PaymentStatus.completed;
      case 'FAILED':
        return PaymentStatus.failed;
      default:
        return PaymentStatus.pending;
    }
  }
}
