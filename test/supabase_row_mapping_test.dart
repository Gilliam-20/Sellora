import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/services/supabase_service.dart';

void main() {
  test('toRow snake_cases top-level keys only', () {
    final row = toRow({
      'sellerId': 's1',
      'primaryColorHex': '#fff',
      'uid': 'u1',
      'shippingAddress': {'countryCode': 'KE'},
    });
    expect(
        row.keys,
        containsAll(
            ['seller_id', 'primary_color_hex', 'uid', 'shipping_address']));
    expect(row['shipping_address'], {'countryCode': 'KE'});
  });

  test('toRow omits by model key', () {
    final row = toRow({'id': 'x', 'createdAt': null, 'name': 'n'},
        omit: const {'id', 'createdAt'});
    expect(row, {'name': 'n'});
  });

  test('offset-less local timestamps are sent as the same instant in UTC', () {
    final local = DateTime(2026, 9, 26, 13, 30);
    final sent =
        toRow({'createdAt': local.toIso8601String()})['created_at'] as String;
    expect(sent, endsWith('Z'));
    expect(DateTime.parse(sent).isAtSameMomentAs(local), isTrue);
  });

  test('Postgres timestamptz comes back as local time, same instant', () {
    const fromDb = '2026-09-26T10:30:00.123456+00:00';
    final map = fromRow({'created_at': fromDb});
    final parsed = DateTime.parse(map['createdAt'] as String);
    expect(parsed.isUtc, isFalse);
    expect(parsed.isAtSameMomentAs(DateTime.parse(fromDb)), isTrue);
  });

  test('a StoreModel round-trips through a row', () {
    final store = StoreModel(
      id: 'store-u1',
      slug: 'aminas-store',
      sellerId: 'u1',
      name: "Amina's Store",
      shippingZones: const ['kenya'],
      createdAt: DateTime(2026, 9, 26, 9),
    );
    // Simulate Postgres echoing the row back with a UTC offset.
    final echoed = toRow(store.toMap()).map((key, value) => MapEntry(
        key,
        value is String && value.endsWith('Z')
            ? value.replaceFirst('Z', '+00:00')
            : value));
    final back = StoreModel.fromMap(fromRow(echoed));
    expect(back.sellerId, 'u1');
    expect(back.shippingZones, ['kenya']);
    expect(back.createdAt, store.createdAt);
  });
}
