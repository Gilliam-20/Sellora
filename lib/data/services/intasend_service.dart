import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';

enum PaymentStatus { pending, completed, failed }

class PaymentResult {
  PaymentResult({required this.reference, required this.status, this.checkoutUrl});
  final String reference;
  final PaymentStatus status;
  final String? checkoutUrl; // for card/hosted checkout, opened via url_launcher
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
      reference: res['invoice_id']?.toString() ?? res['reference']?.toString() ?? '',
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
    final res = await _dio.get(ApiEndpoints.intasendStatus, query: {'reference': reference});
    return _statusFrom(res['state']?.toString());
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
