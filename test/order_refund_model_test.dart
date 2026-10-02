import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/order_refund_model.dart';

void main() {
  OrderRefundInfo info({
    String paymentStatus = 'paid',
    String? provider = 'INTASEND',
    double? charged = 1300,
    double refunded = 0,
  }) =>
      OrderRefundInfo(
        orderId: 'o1',
        paymentProvider: provider,
        paymentStatus: paymentStatus,
        chargedAmount: charged,
        refundedAmount: refunded,
      );

  test('a paid order can be refunded in full', () {
    final i = info();
    expect(i.refusal, isNull);
    expect(i.remaining, 1300);
  });

  test('remaining subtracts earlier partial refunds', () {
    final i = info(paymentStatus: 'partially_refunded', refunded: 299.99);
    expect(i.remaining, closeTo(1000.01, 0.001));
    expect(i.refusal, isNull);
  });

  test('an unpaid or awaiting order is refused as not paid', () {
    expect(info(paymentStatus: 'pending').refusal, contains('never paid'));
    expect(info(paymentStatus: 'awaiting_confirmation').refusal,
        contains('never paid'));
  });

  test('a fully refunded order is refused as already refunded', () {
    expect(info(paymentStatus: 'refunded', refunded: 1300).refusal,
        contains('already been fully refunded'));
  });

  test('no provider charge means nothing to refund', () {
    expect(info(charged: null).refusal, contains('no recorded charge'));
    expect(info(provider: null).refusal, contains('no recorded charge'));
  });

  test('reads the admin_order_refunds row after fromRow', () {
    final i = OrderRefundInfo.fromMap({
      'id': 'o1',
      'paymentProvider': 'INTASEND',
      'paymentStatus': 'partially_refunded',
      'totalKes': 1300,
      'refundedAmount': 300,
      'refundStatus': 'FAILED',
      'refundError': 'Insufficient balance',
      'refunds': [
        {
          'amount': 300,
          'currency': 'KES',
          'reason': 'Unavailable',
          'createdAt': '2026-10-01T10:00:00.000Z',
        }
      ],
      'cjOrderStatus': 'PUSHED',
    });
    expect(i.remaining, 1000);
    expect(i.refundError, 'Insufficient balance');
    expect(i.refunds.single.reason, 'Unavailable');
    expect(i.refunds.single.createdAt, isNotNull);
    expect(i.shippedByCj, isTrue);
  });
}
