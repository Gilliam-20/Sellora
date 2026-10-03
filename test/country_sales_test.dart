import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/order_model.dart';
import 'package:sellora/modules/seller/dashboard/dashboard_models.dart';

void main() {
  OrderModel order(String id, String country, double total, String currency) =>
      OrderModel(
        id: id,
        code: id,
        buyerId: 'b',
        sellerId: 's',
        items: const [],
        status: OrderStatus.processing,
        total: total,
        currency: currency,
        shippingAddress: ShippingAddress(countryCode: country, line1: 'x'),
        createdAt: DateTime(2026, 10, 3),
        paymentStatus: OrderPaymentStatus.paid,
      );

  // 1 GBP = 160 KES, 1 USD = 130 KES; KES passes through.
  double toKes(double amount, String currency) => switch (currency) {
        'GBP' => amount * 160,
        'USD' => amount * 130,
        _ => amount,
      };

  test('groups paid orders by destination in the store currency', () {
    final sales = CountrySales.fromOrders([
      order('1', 'KE', 2000, 'KES'),
      order('2', 'GB', 20, 'GBP'),
      order('3', 'ke', 1000, 'KES'),
      order('4', 'DE', 10, 'USD'),
    ], toKes);

    expect(sales.map((s) => s.countryCode), ['GB', 'KE', 'DE']);
    expect(sales[0].revenue, 3200);
    expect(sales[0].countryName, 'United Kingdom');
    expect(sales[1].orders, 2);
    expect(sales[1].revenue, 3000);
    expect(sales[2].countryName, 'Germany');
  });

  test('names an order with no country Unknown, and keeps unlisted codes', () {
    final sales = CountrySales.fromOrders(
        [order('1', '', 100, 'KES'), order('2', 'CA', 50, 'KES')], toKes);
    expect(sales.map((s) => s.countryName), ['Unknown', 'CA']);
  });

  test('nothing in, nothing out', () {
    expect(CountrySales.fromOrders(const [], toKes), isEmpty);
  });
}
