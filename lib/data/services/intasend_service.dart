import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';

enum PaymentStatus { pending, completed, failed }

/// Wraps IntaSend for both seller subscription billing and buyer
/// order checkout. The IntaSend secret key lives only in Cloud Functions
/// (see /functions/index.js); the app just triggers a collection request
/// and polls/observes the resulting status.
///
/// Order-checkout payment (this section) always acts on an order id that
/// `OrderRepository.placeOrder` already created server-side — the server
/// derives the amount from that order itself, never from a client-supplied
/// figure. Billing payment (below) is the structurally identical mirror for
/// a pending `billing_history` entry instead of an order.
class IntasendService extends GetxService {
  final DioClient _dio = Get.find<DioClient>();

  /// Triggers an M-Pesa STK push to [phoneNumber] (format 2547XXXXXXXX) for
  /// the already-created order [orderId]. Returns the IntaSend invoice id;
  /// call [confirmOrderPayment] afterwards (or wait for the webhook) to
  /// learn whether it actually completed.
  Future<String> payOrderMpesa({
    required String orderId,
    required String phoneNumber,
  }) async {
    final res = await _dio.post(ApiEndpoints.payOrderMpesa, data: {
      'orderId': orderId,
      'phoneNumber': phoneNumber,
    });
    final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
    return data['invoiceId']?.toString() ?? '';
  }

  /// Hosted checkout link for order [orderId]. [method] is
  /// `'CARD-PAYMENT'` or `'GOOGLE-PAY'`. IntaSend redirects to
  /// [redirectUrl] when done; call [confirmOrderPayment] afterwards.
  Future<String?> payOrderCard({
    required String orderId,
    required String method,
    String? redirectUrl,
  }) async {
    final res = await _dio.post(ApiEndpoints.payOrderCard, data: {
      'orderId': orderId,
      'method': method,
      'redirectUrl': redirectUrl,
    });
    final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
    return data['checkoutUrl']?.toString();
  }

  /// Re-checks order [orderId]'s payment status directly with the server
  /// (never trusts a client-side guess); a `completed` result means the
  /// order has also just been marked paid and pushed to CJ server-side.
  Future<PaymentStatus> confirmOrderPayment(String orderId) async {
    final res = await _dio.post(ApiEndpoints.confirmIntasendPayment, data: {
      'orderId': orderId,
    });
    final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
    if (data['paid'] == true) return PaymentStatus.completed;
    return _statusFrom(data['state']?.toString());
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
