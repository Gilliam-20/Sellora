import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/modules/admin/stores/admin_stores_controller.dart';
import 'fakes/mock_admin_repository.dart';
import 'fakes/mock_store_repository.dart';

void main() {
  late MockAdminRepository admin;
  late AdminStoresController controller;

  setUp(() async {
    admin = MockAdminRepository();
    controller = AdminStoresController(
        storeRepository: MockStoreRepository(), adminRepository: admin);
    await controller.load();
  });

  test('suspending needs a reason for the seller', () async {
    final store = controller.stores.first;
    final error =
        await controller.setSuspended(store, suspended: true, reason: '  ');
    expect(error, isNotNull);
    expect(admin.storeSuspensions, isEmpty);
  });

  test('suspends a store and shows it in the list', () async {
    final store = controller.stores.first;
    final error = await controller.setSuspended(store,
        suspended: true, reason: ' Counterfeit listings ');
    expect(error, isNull);
    expect(admin.storeSuspensions[store.id], (true, 'Counterfeit listings'));
    final updated = controller.stores.firstWhere((s) => s.id == store.id);
    expect(updated.isSuspended, isTrue);
    expect(updated.suspensionReason, 'Counterfeit listings');
    expect(updated.suspendedAt, isNotNull);
    expect(controller.updatingStoreId.value, isNull);
  });

  test('lifting clears the reason', () async {
    final store = controller.stores.first;
    await controller.setSuspended(store, suspended: true, reason: 'x');
    final suspended = controller.stores.firstWhere((s) => s.id == store.id);
    await controller.setSuspended(suspended, suspended: false);
    expect(admin.storeSuspensions[store.id], (false, null));
    final lifted = controller.stores.firstWhere((s) => s.id == store.id);
    expect(lifted.isSuspended, isFalse);
    expect(lifted.suspensionReason, isNull);
  });
}
