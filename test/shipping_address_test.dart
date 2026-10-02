import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/order_model.dart';

void main() {
  test('sends the fields createOrder requires and drops empty optionals', () {
    final map = ShippingAddress(
      countryCode: 'KE',
      fullName: 'Wanjiru K',
      phone: '+254712345678',
      line1: '12 Moi Ave',
      line2: '',
      city: 'Nairobi',
      zip: '00100',
    ).toMap();
    expect(map, {
      'countryCode': 'KE',
      'fullName': 'Wanjiru K',
      'phone': '+254712345678',
      'line1': '12 Moi Ave',
      'city': 'Nairobi',
      'zip': '00100',
    });
  });

  test('round-trips through toMap/fromMap', () {
    final a = ShippingAddress.fromMap(ShippingAddress(
      countryCode: 'GB',
      fullName: 'Sam Lee',
      phone: '+447700900123',
      email: 'sam@example.com',
      line1: '1 High St',
      line2: 'Flat 2',
      city: 'Leeds',
      province: 'West Yorkshire',
      zip: 'LS1 1AA',
    ).toMap());
    expect(a.email, 'sam@example.com');
    expect(a.summary, '1 High St, Flat 2, Leeds, West Yorkshire, LS1 1AA, GB');
  });

  test('reads an order stored with the old {countryCode, line} shape', () {
    final a = ShippingAddress.fromMap({'countryCode': 'KE', 'line': 'Moi Ave'});
    expect(a.line1, 'Moi Ave');
    expect(a.summary, 'Moi Ave, KE');
  });
}
