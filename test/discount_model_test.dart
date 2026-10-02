import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/discount_model.dart';

void main() {
  DiscountModel discount({
    DiscountKind kind = DiscountKind.percentage,
    double value = 10,
    double minSubtotal = 0,
    List<String> productIds = const [],
    DateTime? startsAt,
    DateTime? endsAt,
    int? usageLimit,
    bool isActive = true,
  }) =>
      DiscountModel(
        id: 'd1',
        storeId: 'store-1',
        code: 'SAVE10',
        kind: kind,
        value: value,
        minSubtotal: minSubtotal,
        productIds: productIds,
        startsAt: startsAt ?? DateTime(2026, 10, 1),
        endsAt: endsAt,
        usageLimit: usageLimit,
        isActive: isActive,
      );
  final lines = <DiscountLine>[
    (productId: 'a', lineTotal: 30),
    (productId: 'b', lineTotal: 20),
  ];

  group('quote mirrors the server\'s priceDiscount', () {
    test('a percentage comes off the whole subtotal', () {
      expect(discount().quote(lines), (amount: 5.0, refusal: null));
    });

    test('a fixed amount never exceeds the goods', () {
      expect(
          discount(kind: DiscountKind.fixedAmount, value: 7.5)
              .quote(lines)
              .amount,
          7.5);
      expect(
          discount(kind: DiscountKind.fixedAmount, value: 500)
              .quote(lines)
              .amount,
          50);
    });

    test('a product-specific code only discounts those lines', () {
      expect(discount(productIds: ['b']).quote(lines).amount, 2);
      expect(discount(productIds: ['z']).quote(lines).refusal,
          DiscountModel.notApplicable);
    });

    test('the minimum is measured on the whole subtotal', () {
      expect(discount(minSubtotal: 50.01).quote(lines).refusal,
          contains('USD 50.01'));
      expect(
          discount(minSubtotal: 50, productIds: ['b']).quote(lines).amount, 2);
    });
  });

  group('statusAt', () {
    final now = DateTime(2026, 10, 3, 12);

    test('reads off, ended, used up, scheduled and active', () {
      expect(discount(isActive: false).statusAt(now), DiscountStatus.off);
      expect(discount(endsAt: DateTime(2026, 10, 2)).statusAt(now),
          DiscountStatus.ended);
      expect(discount(usageLimit: 2).statusAt(now, uses: 2),
          DiscountStatus.usedUp);
      expect(discount(startsAt: DateTime(2026, 10, 4)).statusAt(now),
          DiscountStatus.scheduled);
      expect(discount(usageLimit: 2).statusAt(now, uses: 1),
          DiscountStatus.active);
    });
  });

  test('reads the storefront_discount() answer, which has no id or limits', () {
    final parsed = DiscountModel.fromMap({
      'code': 'SAVE10',
      'kind': 'fixed_amount',
      'value': 5.5,
      'minSubtotal': 20,
      'productIds': ['a'],
      'endsAt': '2026-10-10T20:59:59+00:00',
      'oncePerCustomer': true,
    });
    expect(parsed.kind, DiscountKind.fixedAmount);
    expect(parsed.value, 5.5);
    expect(parsed.minSubtotal, 20);
    expect(parsed.productIds, ['a']);
    expect(parsed.usageLimit, isNull);
    expect(parsed.endsAt!.toUtc(), DateTime.utc(2026, 10, 10, 20, 59, 59));
    expect(parsed.summary, 'USD 5.50 off');
  });

  test('writes the kind as the column stores it', () {
    expect(discount(kind: DiscountKind.fixedAmount).toMap()['kind'],
        'fixed_amount');
    expect(discount().summary, '10% off');
  });

  test('normalizes codes the way the table stores them', () {
    expect(DiscountModel.normalizeCode('  welcome10 '), 'WELCOME10');
    expect(DiscountModel.codePattern.hasMatch('WELCOME10'), isTrue);
    expect(DiscountModel.codePattern.hasMatch('AB'), isFalse);
    expect(DiscountModel.codePattern.hasMatch('NO SPACES'), isFalse);
  });
}
