import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/models/subscription_plan_model.dart';
import 'package:sellora/data/models/user_model.dart';
import 'fakes/mock_auth_repository.dart';
import 'fakes/mock_store_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';
import 'package:sellora/data/repositories/subscription_repository.dart';
import 'package:sellora/modules/onboarding/controllers/seller_onboarding_controller.dart';

void main() {
  tearDown(Get.reset);

  Future<(MockAuthRepository, MockStoreRepository, UserModel)> signUp() async {
    final stores = MockStoreRepository();
    final auth = MockAuthRepository(storeRepository: stores);
    final seller = await auth.signUpSeller(
      name: 'Amina',
      email: 'amina@example.com',
      password: 'password123',
      storeName: "Amina's Store",
      phone: '0712345678',
      hasAcceptedTerms: true,
    );
    return (auth, stores, seller);
  }

  SellerOnboardingController build(
          MockAuthRepository auth, StoreRepository stores) =>
      SellerOnboardingController(
        subscriptionRepository: _FakeSubscriptionRepository(),
        authRepository: auth,
        storeRepository: stores,
      );

  Future<void> settle(SellerOnboardingController c) async {
    while (c.isLoading.value) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('a freshly signed-up seller starts on store setup, prefilled', () async {
    final (auth, stores, _) = await signUp();
    final c = build(auth, stores)..onInit();
    await settle(c);

    expect(c.step.value, OnboardingStep.storeSetup);
    expect(c.storeName.value, "Amina's Store");
    expect(c.countryCode.value, 'KE');
    expect(c.currencyCode.value, 'KES');
    expect(c.selectedPlanId.value, 'growth');
  });

  test('picking a country defaults the currency to that country\'s', () async {
    final (auth, stores, _) = await signUp();
    final c = build(auth, stores)..onInit();
    await settle(c);

    c.selectCountry('GB');
    expect(c.currencyCode.value, 'GBP');
    c.selectCountry('XX');
    expect(c.countryCode.value, 'GB', reason: 'unknown codes are ignored');
  });

  test('saving store setup updates the existing store and moves to plans',
      () async {
    final (auth, stores, seller) = await signUp();
    final c = build(auth, stores)..onInit();
    await settle(c);
    final slugBefore = c.store.value!.slug;

    c.storeName.value = 'Amina Home';
    c.category.value = 'home';
    c.selectCountry('US');
    await c.saveStoreSetup();

    expect(c.errorMessage.value, isNull);
    expect(c.step.value, OnboardingStep.choosePlan);
    final saved = (await stores.storesForSeller(seller.uid)).single;
    expect(saved.name, 'Amina Home');
    expect(saved.category, 'home');
    expect(saved.countryCode, 'US');
    expect(saved.currencyCode, 'USD');
    expect(saved.slug, slugBefore, reason: 'renaming keeps the address');
    expect(saved.isSetUp, isTrue);
    expect(auth.cachedUser!.storeName, 'Amina Home');
  });

  test('saving without a category is refused', () async {
    final (auth, stores, _) = await signUp();
    final c = build(auth, stores)..onInit();
    await settle(c);

    await c.saveStoreSetup();

    expect(c.errorMessage.value, isNotNull);
    expect(c.step.value, OnboardingStep.storeSetup);
  });

  test('creates the store when the seller has none', () async {
    final (auth, _, seller) = await signUp();
    // A store repository that has never heard of this seller.
    final empty = MockStoreRepository();
    final c = build(auth, empty)..onInit();
    await settle(c);
    expect(c.store.value, isNull);

    c.category.value = 'fashion';
    await c.saveStoreSetup();

    final created = (await empty.storesForSeller(seller.uid)).single;
    expect(created.id, 'store-${seller.uid}');
    expect(created.slug, 'aminas-store');
    expect(created.category, 'fashion');
    expect(c.step.value, OnboardingStep.choosePlan);
  });

  test('a seller whose store is already set up skips to plan selection',
      () async {
    final (auth, stores, seller) = await signUp();
    final store = (await stores.storesForSeller(seller.uid)).single;
    await stores
        .updateStore(store.copyWith(category: 'general', countryCode: 'KE'));

    final c = build(auth, stores)..onInit();
    await settle(c);

    expect(c.step.value, OnboardingStep.choosePlan);
    expect(c.previousStep, OnboardingStep.storeSetup);
  });

  test('createStoreForSeller picks the first free slug', () async {
    final stores = MockStoreRepository();
    final a = await createStoreForSeller(stores,
        sellerId: 's1', storeName: 'Duka Bora');
    final b = await createStoreForSeller(stores,
        sellerId: 's2', storeName: 'Duka Bora');
    final c = await createStoreForSeller(stores,
        sellerId: 's3', storeName: 'Duka Bora');
    expect(
        [a.slug, b.slug, c.slug], ['duka-bora', 'duka-bora-2', 'duka-bora-3']);
  });

  test('StoreModel round-trips its onboarding fields', () {
    final store = StoreModel(
      id: 's',
      slug: 'x',
      sellerId: 'u',
      name: 'X',
      category: 'beauty',
      countryCode: 'DE',
      currencyCode: 'EUR',
    );
    final copy = StoreModel.fromMap(store.toMap());
    expect(copy.category, 'beauty');
    expect(copy.countryCode, 'DE');
    expect(copy.isSetUp, isTrue);
    expect(StoreModel.fromMap({'id': 'old'}).isSetUp, isFalse);
  });
}

class _FakeSubscriptionRepository implements SubscriptionRepository {
  @override
  Future<List<SubscriptionPlanModel>> fetchPlans() async => [
        _plan('starter', popular: false),
        _plan('growth', popular: true),
      ];

  SubscriptionPlanModel _plan(String id, {required bool popular}) =>
      SubscriptionPlanModel(
        id: id,
        name: id,
        priceUsd: 10,
        priceKes: 999,
        billingPeriodDays: 30,
        listingLimit: 50,
        perks: const [],
        isPopular: popular,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
