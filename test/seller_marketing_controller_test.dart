import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/discount_model.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/repositories/auth_repository.dart';
import 'package:sellora/data/repositories/product_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';
import 'package:sellora/modules/seller/marketing/seller_marketing_controller.dart';
import 'package:sellora/modules/storefront/store_scope.dart';
import 'fakes/mock_discount_repository.dart';

// save/delete/validate never touch these; load() isn't run here.
class _Unused implements ProductRepository, AuthRepository, StoreRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late MockDiscountRepository repo;
  late SellerMarketingController controller;

  setUp(() {
    repo = MockDiscountRepository();
    final scope = StoreScope(repository: _Unused())
      ..current.value = StoreModel(
        id: 'store-1',
        slug: 'amina',
        sellerId: 's1',
        name: 'Amina',
        createdAt: DateTime(2026, 9, 1),
      );
    controller = SellerMarketingController(
      discountRepository: repo,
      productRepository: _Unused(),
      authRepository: _Unused(),
      scope: scope,
    );
  });

  DiscountModel draft({String code = 'SAVE10', double value = 10}) =>
      DiscountModel(
        storeId: 'store-1',
        code: code,
        kind: DiscountKind.percentage,
        value: value,
      );

  test('creates a code and lists it first', () async {
    expect(await controller.save(draft()), isNull);
    expect(await controller.save(draft(code: 'WELCOME')), isNull);
    expect(controller.discounts.map((d) => d.code), ['WELCOME', 'SAVE10']);
    expect(controller.discounts.first.id, isNotEmpty);
  });

  test('refuses a duplicate code with a message the seller can act on',
      () async {
    await controller.save(draft());
    expect(await controller.save(draft()), contains('already have a code'));
    expect(controller.discounts, hasLength(1));
  });

  test('validates before saving', () async {
    expect(await controller.save(draft(code: 'AB')), contains('3–32'));
    expect(await controller.save(draft(value: 0)), contains('how much'));
    expect(await controller.save(draft(value: 150)), contains('100'));
    expect(controller.discounts, isEmpty);
  });

  test('switching a code off updates it in place', () async {
    await controller.save(draft());
    final saved = controller.discounts.single;
    expect(await controller.setActive(saved, false), isNull);
    expect(controller.discounts.single.isActive, isFalse);
    expect(
        controller.statusOf(controller.discounts.single), DiscountStatus.off);
  });

  test('a used code is not deleted; an unused one is', () async {
    await controller.save(draft());
    await controller.save(draft(code: 'UNUSED'));
    final used = controller.discounts.firstWhere((d) => d.code == 'SAVE10');
    repo.uses[used.id] = 3;
    expect(await controller.delete(used), contains('Turn it off'));
    final unused = controller.discounts.firstWhere((d) => d.code == 'UNUSED');
    expect(await controller.delete(unused), isNull);
    expect(controller.discounts.map((d) => d.code), ['SAVE10']);
  });

  test('builds the store link from the slug', () {
    expect(controller.storeLink.toString(), endsWith('/#/s/amina'));
  });
}
