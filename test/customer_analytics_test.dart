import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/order_model.dart';
import 'package:sellora/data/models/store_customer_model.dart';
import 'package:sellora/modules/seller/customers/customer_analytics.dart';

void main() {
  final now = DateTime(2026, 10, 3);

  OrderModel order(
    String id,
    String buyer,
    double total,
    DateTime createdAt, {
    OrderPaymentStatus payment = OrderPaymentStatus.paid,
    String currency = 'KES',
    String name = '',
  }) =>
      OrderModel(
        id: id,
        code: id,
        buyerId: buyer,
        sellerId: 's1',
        storeId: 'store-1',
        items: const [],
        status: OrderStatus.processing,
        total: total,
        currency: currency,
        shippingAddress: ShippingAddress(countryCode: 'KE', fullName: name),
        createdAt: createdAt,
        paymentStatus: payment,
      );

  StoreCustomerModel member(String uid, String name, String email) =>
      StoreCustomerModel(
        storeId: 'store-1',
        uid: uid,
        name: name,
        email: email,
        createdAt: DateTime(2026, 8, 1),
      );

  // 1 USD = 100 KES, for the conversion check.
  double toKes(double amount, String currency) =>
      currency == 'USD' ? amount * 100 : amount;

  final analytics = CustomerAnalytics.build(
    now: now,
    toStoreCurrency: toKes,
    members: [
      member('amina', 'Amina', 'amina@x.com'),
      member('bob', 'Bob', 'bob@x.com'),
      member('cara', 'Cara', 'cara@x.com'),
    ],
    orders: [
      order('o1', 'amina', 1000, DateTime(2026, 8, 10)),
      order('o2', 'amina', 5, DateTime(2026, 9, 20), currency: 'USD'),
      order('o3', 'bob', 300, DateTime(2026, 9, 25)),
      order('o4', 'bob', 999, DateTime(2026, 9, 26),
          payment: OrderPaymentStatus.pending),
      order('o5', 'gone', 200, DateTime(2026, 9, 1), name: 'Dee'),
      order('o6', 'gone', 100, DateTime(2026, 9, 2),
          payment: OrderPaymentStatus.partiallyRefunded),
    ],
  );
  CustomerStat of(String uid) =>
      analytics.customers.firstWhere((c) => c.uid == uid);

  test('totals only paid orders, converted into the store currency', () {
    expect(of('amina').purchaseCount, 2);
    expect(of('amina').totalSpent, 1500);
    expect(of('amina').averageOrderValue, 750);
    expect(of('bob').purchaseCount, 1);
    expect(of('bob').totalSpent, 300);
    expect(of('bob').orders, hasLength(2));
  });

  test('a partly refunded order still counts as a purchase', () {
    expect(of('gone').purchaseCount, 2);
    expect(of('gone').isReturning, isTrue);
  });

  test('a buyer with no membership row is named from their order', () {
    expect(of('gone').name, 'Dee');
    expect(of('gone').email, '');
  });

  test('a registered customer with no orders is still listed', () {
    expect(of('cara').purchaseCount, 0);
    expect(of('cara').lastOrderAt, isNull);
  });

  test('summarizes customers, returning, new and average spend', () {
    final s = analytics.summary;
    expect(s.totalCustomers, 4);
    expect(s.purchasingCustomers, 3);
    expect(s.returningCustomers, 2);
    expect(s.repeatRate, closeTo(2 / 3, 1e-9));
    // First purchase within 30 days of Oct 3 (since Sep 3): only bob
    // (Sep 25). gone's was Sep 1, amina's Aug 10.
    expect(s.newCustomers, 1);
    expect(s.averageSpend, closeTo((1500 + 300 + 300) / 3, 1e-9));
  });

  test('lists the biggest spenders first, ties by most recent order', () {
    // bob and gone both spent 300; bob ordered more recently.
    expect(analytics.customers.map((c) => c.uid).toList(),
        ['amina', 'bob', 'gone', 'cara']);
  });

  test('filters by name or email and re-sorts', () {
    final all = analytics.customers;
    expect(
        CustomerAnalytics.filter(all, 'BOB@', CustomerSort.totalSpent)
            .map((c) => c.uid),
        ['bob']);
    expect(
        CustomerAnalytics.filter(all, '', CustomerSort.name).map((c) => c.name),
        ['Amina', 'Bob', 'Cara', 'Dee']);
    expect(CustomerAnalytics.filter(all, '', CustomerSort.recent).first.uid,
        'bob');
  });
}
