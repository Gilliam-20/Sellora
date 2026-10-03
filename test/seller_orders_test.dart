import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/fee_settings.dart';
import 'package:sellora/data/models/order_model.dart';
import 'package:sellora/data/models/order_timeline.dart';
import 'package:sellora/modules/seller/orders/order_filters.dart';

OrderModel _order({
  String id = 'o1',
  OrderStatus status = OrderStatus.pending,
  OrderPaymentStatus payment = OrderPaymentStatus.pending,
  String? cjStatus,
  String name = 'Amina Wanjiru',
}) =>
    OrderModel(
      id: id,
      code: 'SLR-$id',
      buyerId: 'b',
      sellerId: 's',
      items: [
        OrderItem(
            productId: 'p',
            title: 'Lamp',
            imageUrl: '',
            quantity: 2,
            unitPrice: 10),
      ],
      status: status,
      paymentStatus: payment,
      total: 25,
      shippingAddress: ShippingAddress(
          countryCode: 'KE', fullName: name, phone: '0712', email: 'a@x.com'),
      createdAt: DateTime(2026, 10, 3),
      cjOrderStatus: cjStatus,
    );

void main() {
  group('OrderFilter', () {
    final orders = {
      'unpaid': _order(),
      'paid': _order(
          status: OrderStatus.processing, payment: OrderPaymentStatus.paid),
      'shipped':
          _order(status: OrderStatus.shipped, payment: OrderPaymentStatus.paid),
      'cancelled': _order(status: OrderStatus.cancelled),
      'refunded': _order(
          status: OrderStatus.cancelled,
          payment: OrderPaymentStatus.partiallyRefunded),
    };
    Set<String> matching(OrderFilter f) => orders.entries
        .where((e) => f.matches(e.value))
        .map((e) => e.key)
        .toSet();

    test('each filter picks the right orders', () {
      expect(matching(OrderFilter.all), orders.keys.toSet());
      expect(matching(OrderFilter.unpaid), {'unpaid'});
      expect(matching(OrderFilter.paid), {'paid', 'shipped'});
      expect(matching(OrderFilter.pending), {'unpaid'});
      expect(matching(OrderFilter.processing), {'paid'});
      expect(matching(OrderFilter.fulfilled), {'shipped'});
      expect(matching(OrderFilter.cancelled), {'cancelled', 'refunded'});
      expect(matching(OrderFilter.refunded), {'refunded'});
    });
  });

  group('SellerOrderView', () {
    test('search matches code, name, email and phone', () {
      final order = _order();
      for (final q in ['slr-o1', 'amina', 'A@X.COM', '0712', '']) {
        expect(order.matchesQuery(q), isTrue, reason: q);
      }
      expect(order.matchesQuery('nobody'), isFalse);
    });

    test('fulfilment folds in CJ', () {
      expect(_order().fulfillmentLabel, 'Unfulfilled');
      expect(
          _order(
                  status: OrderStatus.processing,
                  payment: OrderPaymentStatus.paid,
                  cjStatus: 'PUSHED')
              .fulfillmentLabel,
          'With CJ');
      expect(
          _order(
                  status: OrderStatus.processing,
                  payment: OrderPaymentStatus.paid,
                  cjStatus: 'NEEDS_RECONCILIATION')
              .fulfillmentLabel,
          'On hold');
    });

    test('only an unpaid pending order can be cancelled by the seller', () {
      expect(_order().sellerCanCancel, isTrue);
      expect(
          _order(payment: OrderPaymentStatus.failed).sellerCanCancel, isTrue);
      expect(
          _order(
                  status: OrderStatus.processing,
                  payment: OrderPaymentStatus.paid)
              .sellerCanCancel,
          isFalse);
      expect(_order(status: OrderStatus.cancelled).sellerCanCancel, isFalse);
    });

    test('a nameless order still has a customer label', () {
      expect(_order(name: ' ').customerName, 'Customer');
    });

    test('totals come from the lines', () {
      expect(_order().itemsSubtotal, 20);
      expect(_order().itemCount, 2);
    });
  });

  group('OrderModel', () {
    test('reads the seller-only and tracking fields', () {
      final order = OrderModel.fromMap({
        'id': 'o1',
        'buyerId': 'b',
        'sellerId': 's',
        'status': 'processing',
        'serviceFeeBase': 'subtotal_and_shipping',
        'refundedAmount': 5,
        'cjOrderStatus': 'PUSHED',
        'cjOrderNumber': 'CJ123',
        'tracking': {
          'status': 'IN_TRANSIT',
          'trackingNumber': 'TRK1',
          'events': [
            {
              'at': '2026-10-03',
              'description': 'Departed',
              'location': 'Shenzhen'
            },
            'garbage',
          ],
        },
      });
      expect(order.serviceFeeBase, 'subtotal_and_shipping');
      expect(order.refundedAmount, 5);
      expect(order.cjStatusLabel, 'Placed with CJ (#CJ123)');
      expect(order.tracking?.statusLabel, 'In transit');
      expect(order.tracking?.events.single.location, 'Shenzhen');
    });

    test('defaults when the seller-only fields are absent', () {
      final order =
          OrderModel.fromMap({'id': 'o1', 'buyerId': 'b', 'sellerId': 's'});
      expect(order.serviceFeeBase, 'subtotal');
      expect(order.tracking, isNull);
      expect(order.cjStatusLabel, 'Sent to CJ once paid');
    });
  });

  group('OrderTimelineEntry', () {
    test('turns audited changes into lines', () {
      final entry = OrderTimelineEntry.fromRow({
        'occurred_at': '2026-10-03T10:00:00Z',
        'kind': 'change',
        'actor_role': 'service',
        'details': {
          'status': ['pending', 'processing'],
          'payment_status': ['awaiting_confirmation', 'paid'],
          'cj_order_status': ['NOT_PUSHED', 'PUSHED'],
          'tracking_number': [null, 'TRK1'],
          'refunded_amount': [0, 5],
          'something_else': [1, 2],
        },
      });
      expect(entry.describe(currency: 'USD'), [
        'Marked processing',
        'Payment received',
        'Sent to CJ Dropshipping for fulfilment',
        'Tracking number TRK1',
        'Refunded \$5.00',
      ]);
      expect(entry.actorLabel, 'Sellora');
    });

    test('creation and notes', () {
      expect(
          OrderTimelineEntry(
              at: DateTime(2026),
              kind: 'created',
              actorRole: 'buyer',
              details: {'total': 25, 'currency': 'USD'}).describe(),
          ['Order placed for \$25.00']);
      final note = OrderTimelineEntry(
          at: DateTime(2026),
          kind: 'note',
          actorRole: 'seller',
          details: {'body': 'Called the buyer'});
      expect(note.describe(), ['Called the buyer']);
      expect(note.actorLabel, 'You');
    });

    test('an uninteresting change describes to nothing', () {
      final entry = OrderTimelineEntry(
          at: DateTime(2026),
          kind: 'change',
          actorRole: 'system',
          details: {
            'refund_status': ['NONE', 'REFUNDED'],
          });
      expect(entry.describe(), isEmpty);
    });
  });

  group('FeeSettings', () {
    test('defaults to 7% on the goods only', () {
      expect(FeeSettings.fromMap(null).serviceFeeRate, 0.07);
      expect(FeeSettings.fromMap(null).chargeOnShipping, isFalse);
      expect(FeeSettings.defaults.percentLabel, '7');
    });

    test('an out-of-range rate falls back to the default', () {
      expect(FeeSettings.fromMap({'serviceFeeRate': 0.5}).serviceFeeRate, 0.07);
      expect(FeeSettings.fromMap({'serviceFeeRate': -1}).serviceFeeRate, 0.07);
    });

    test('charges shipping only when configured', () {
      const goodsOnly = FeeSettings(serviceFeeRate: 0.07);
      const withShipping =
          FeeSettings(serviceFeeRate: 0.07, chargeOnShipping: true);
      expect(goodsOnly.feeOn(100, shipping: 10), 7);
      expect(withShipping.feeOn(100, shipping: 10), 7.7);
      expect(const FeeSettings(serviceFeeRate: 0.065).percentLabel, '6.5');
    });
  });
}
