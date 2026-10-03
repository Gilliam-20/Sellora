import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sellora/core/utils/plan_change.dart';
import 'package:sellora/data/models/billing_history_entry_model.dart';
import 'package:sellora/data/models/billing_profile_model.dart';
import 'package:sellora/data/models/subscription_plan_model.dart';
import 'package:sellora/data/models/subscription_usage_model.dart';
import 'package:sellora/data/models/user_model.dart';
import 'package:sellora/data/repositories/auth_repository.dart';
import 'package:sellora/data/repositories/subscription_repository.dart';
import 'package:sellora/modules/seller/subscription/invoice.dart';
import 'package:sellora/modules/seller/subscription/seller_subscription_controller.dart';
import 'fakes/mock_auth_repository.dart';
import 'fakes/mock_store_repository.dart';

SubscriptionPlanModel _plan(
  String id, {
  double kes = 1300,
  int days = 30,
  int listings = 25,
  int orders = 100,
  int stores = 1,
  Map<String, bool> features = const {},
  PlanSupportLevel support = PlanSupportLevel.standard,
  bool active = true,
}) =>
    SubscriptionPlanModel(
      id: id,
      name: id[0].toUpperCase() + id.substring(1),
      priceUsd: 0,
      priceKes: kes,
      billingPeriodDays: days,
      listingLimit: listings,
      orderLimit: orders,
      storeLimit: stores,
      features: features,
      supportLevel: support,
      perks: const [],
      isActive: active,
    );

final _starter = _plan('starter');
final _growth = _plan('growth',
    kes: 4000,
    listings: 500,
    orders: 1000,
    stores: 3,
    features: const {'advancedAnalytics': true},
    support: PlanSupportLevel.priority);
final _pro = _plan('pro', kes: 10300, listings: -1, orders: -1, stores: 10);

BillingHistoryEntryModel _entry({
  String status = 'paid',
  String? invoice = 'INV-2026-000042',
  DateTime? created,
}) =>
    BillingHistoryEntryModel(
      id: 'bh-1',
      sellerId: 'seller-1',
      planId: 'growth',
      planName: 'Growth',
      amountKes: 4000,
      amountUsd: 31,
      billingPeriodDays: 30,
      status: status,
      paymentProvider: 'INTASEND',
      paymentReference: 'QX12AB',
      createdAt: created ?? DateTime(2026, 10, 1),
      paidAt: status == 'paid' ? DateTime(2026, 10, 1) : null,
      paymentMethod: 'MPESA',
      invoiceNumber: status == 'paid' ? invoice : null,
      periodStart: DateTime(2026, 10, 1),
      periodEnd: DateTime(2026, 10, 31),
    );

void main() {
  group('PlanChange', () {
    test('ranks plans by price per day', () {
      expect(PlanChange(from: null, to: _starter).kind, PlanChangeKind.start);
      expect(
          PlanChange(from: _starter, to: _starter).kind, PlanChangeKind.renew);
      expect(
          PlanChange(from: _starter, to: _growth).kind, PlanChangeKind.upgrade);
      expect(PlanChange(from: _pro, to: _growth).actionLabel, 'Downgrade');
      // A year of Growth costs more in one payment but less per day.
      final yearly = _plan('yearly', kes: 40000, days: 365);
      expect(
          PlanChange(from: _growth, to: yearly).kind, PlanChangeKind.downgrade);
      expect(PlanChange(from: _starter, to: _plan('twin')).kind,
          PlanChangeKind.switchPlan);
    });

    test('lists what an upgrade adds', () {
      final gains = PlanChange(from: _starter, to: _growth).gains;
      expect(gains, [
        '500 listed products (up from 25)',
        '1000 paid orders per month (up from 100)',
        '3 stores (up from 1)',
        'Advanced analytics (coming soon)',
        'Priority support instead of email support',
      ]);
      expect(PlanChange(from: _starter, to: _growth).losses, isEmpty);
    });

    test('lists what a downgrade takes away, unlimited included', () {
      final change = PlanChange(from: _pro, to: _starter);
      expect(change.gains, isEmpty);
      expect(change.losses, [
        '25 listed products (down from unlimited)',
        '100 paid orders per month (down from unlimited)',
        '1 store (down from 10)',
      ]);
      expect(
          PlanChange(from: _growth, to: _starter).losses,
          containsAll([
            'No advanced analytics',
            'Email support instead of priority support'
          ]));
    });

    test('a renewal or a first plan has nothing to compare', () {
      expect(PlanChange(from: _growth, to: _growth).gains, isEmpty);
      expect(PlanChange(from: null, to: _growth).losses, isEmpty);
    });

    test('suggests the cheapest plan with room for more', () {
      final plans = [_starter, _growth, _pro];
      expect(
          PlanChange.roomFor(plans,
                  current: _starter, limitOf: (p) => p.listingLimit, used: 24)
              ?.id,
          'growth');
      // Growth has 3 stores, but the seller already has 3.
      expect(
          PlanChange.roomFor(plans,
                  current: _starter, limitOf: (p) => p.storeLimit, used: 3)
              ?.id,
          'pro');
      expect(
          PlanChange.roomFor(plans,
              current: _pro, limitOf: (p) => p.listingLimit, used: 900),
          isNull);
      // A retired plan isn't suggested.
      expect(
          PlanChange.roomFor([_starter, _growth.copyWith(isActive: false)],
              current: _starter, limitOf: (p) => p.listingLimit, used: 24),
          isNull);
    });
  });

  group('billing models', () {
    test('an entry reads its invoice fields', () {
      final entry = BillingHistoryEntryModel.fromMap({
        'id': 'bh-9',
        'sellerId': 's',
        'planId': 'growth',
        'status': 'paid',
        'paymentMethod': 'CARD-PAYMENT',
        'invoiceNumber': 'INV-2026-000009',
        'periodStart': '2026-10-01T00:00:00.000Z',
        'periodEnd': '2026-10-31T00:00:00.000Z',
        'createdAt': '2026-10-01T00:00:00.000Z',
      });
      expect(entry.hasInvoice, isTrue);
      expect(entry.paymentMethodLabel, 'Card');
      expect(entry.periodEnd, DateTime.utc(2026, 10, 31));
      expect(_entry(status: 'pending').hasInvoice, isFalse);
    });

    test('usage reads a cancellation', () {
      final usage = SubscriptionUsageModel.fromMap({
        'subscriptionStatus': 'active',
        'listingCount': 1,
        'listingLimit': 25,
        'cancelAtPeriodEnd': true,
        'cancelledAt': '2026-10-02T09:00:00Z',
        'currentPeriodStart': '2026-10-01T00:00:00Z',
      });
      expect(usage.isEnding, isTrue);
      expect(usage.cancelledAt, isNotNull);
      expect(usage.currentPeriodStart, isNotNull);
      final old = SubscriptionUsageModel.fromMap(
          {'subscriptionStatus': 'active', 'listingCount': 0});
      expect(old.isEnding, isFalse);
    });

    test('a billing profile round-trips and shows the number locally', () {
      const profile = BillingProfileModel(
          sellerId: 's',
          mpesaPhone: '254712345678',
          billingName: 'Amina Ltd',
          taxId: 'P051234567X');
      final copy = BillingProfileModel.fromMap(profile.toMap());
      expect(copy.paymentMethod, BillingPaymentMethod.mpesa);
      expect(copy.mpesaPhoneDisplay, '0712 345 678');
      expect(copy.taxId, 'P051234567X');
      expect(
          BillingProfileModel.fromMap(
              {'sellerId': 's', 'paymentMethod': 'card'}).paymentMethod,
          BillingPaymentMethod.card);
    });
  });

  group('Invoice', () {
    final user = UserModel(
        uid: 'seller-1',
        name: 'Amina',
        email: 'amina@example.com',
        role: UserRole.seller);

    test('is made out to the billing name, else the seller', () {
      final named = Invoice.of(_entry(),
          user: user,
          profile: const BillingProfileModel(
              sellerId: 'seller-1', billingName: 'Amina Ltd', taxId: 'P05'));
      expect(named.billedTo, 'Amina Ltd');
      expect(named.taxId, 'P05');
      final plain = Invoice.of(_entry(),
          user: user,
          profile: const BillingProfileModel(
              sellerId: 'seller-1', billingName: '  '));
      expect(plain.billedTo, 'Amina');
      expect(plain.taxId, isNull);
    });

    test('describes the plan, period, amount and payment', () {
      final invoice = Invoice.of(_entry(), user: user);
      expect(invoice.number, 'INV-2026-000042');
      expect(invoice.description,
          'Growth plan, 1 month (1 Oct 2026 to 31 Oct 2026)');
      expect(invoice.amount, 'KES 4,000.00');
      expect(invoice.paidWith, 'M-Pesa, ref. QX12AB');
      expect(invoice.fileName, 'INV-2026-000042.pdf');
    });

    test('renders a PDF', () async {
      final bytes = await Invoice.of(_entry(), user: user).toPdf();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('SellerSubscriptionController', () {
    late _FakeSubscriptions repo;
    late SellerSubscriptionController controller;

    setUp(() async {
      Get.testMode = true;
      final auth = MockAuthRepository(storeRepository: MockStoreRepository());
      await auth.updateUser(UserModel(
        uid: 'seller-1',
        name: 'Amina',
        email: 'amina@example.com',
        role: UserRole.seller,
        subscriptionPlanId: 'starter',
        subscriptionActiveUntil: DateTime.now().add(const Duration(days: 9)),
      ));
      repo = _FakeSubscriptions();
      Get.put<AuthRepository>(auth);
      Get.put<SubscriptionRepository>(repo);
      controller = SellerSubscriptionController();
      await controller.load();
    });

    tearDown(Get.reset);

    test('loads plan, usage, history and the saved method', () {
      expect(controller.currentPlan?.id, 'starter');
      expect(
          controller.invoices.map((e) => e.invoiceNumber), ['INV-2026-000042']);
      expect(controller.pendingPayments, hasLength(1));
      expect(controller.billingProfile.value?.mpesaPhone, '254712345678');
    });

    test('suggests an upgrade near a limit, not before', () {
      repo.usage = _usage(listings: 15);
      return controller.load().then((_) {
        expect(controller.suggestedUpgrade, isNull);
        repo.usage = _usage(listings: 21);
        return controller.load();
      }).then((_) => expect(controller.suggestedUpgrade?.id, 'growth'));
    });

    testWidgets('cancels and resumes, reloading the state', (tester) async {
      // Both confirm with a snackbar, which needs an app to draw in.
      await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
      await controller.cancel(reason: 'Too expensive');
      expect(repo.cancelReason, 'Too expensive');
      expect(controller.usage.value?.isEnding, isTrue);
      await controller.resume();
      expect(controller.usage.value?.isEnding, isFalse);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    test('saves the payment method and invoice details as entered', () async {
      final saved = await controller.saveBillingProfile(
        method: BillingPaymentMethod.card,
        mpesaPhone: '',
        billingName: ' Amina Ltd ',
        taxId: '',
      );
      expect(saved, isTrue);
      final profile = repo.profile!;
      expect(profile.paymentMethod, BillingPaymentMethod.card);
      expect(profile.mpesaPhone, isNull);
      expect(profile.billingName, 'Amina Ltd');
      expect(profile.taxId, isNull);

      await controller.saveBillingProfile(
          method: BillingPaymentMethod.mpesa, mpesaPhone: '0712 345 678');
      expect(repo.profile!.mpesaPhone, '254712345678');
    });
  });
}

SubscriptionUsageModel _usage({int listings = 3, bool ending = false}) =>
    SubscriptionUsageModel(
      listingCount: listings,
      listingLimit: 25,
      orderCount: 4,
      orderLimit: 100,
      storeCount: 1,
      storeLimit: 1,
      subscriptionStatus: 'active',
      currentPeriodEnd: DateTime.now().add(const Duration(days: 9)),
      cancelAtPeriodEnd: ending,
    );

class _FakeSubscriptions implements SubscriptionRepository {
  SubscriptionUsageModel usage = _usage();
  BillingProfileModel? profile = const BillingProfileModel(
      sellerId: 'seller-1', mpesaPhone: '254712345678');
  String? cancelReason;

  @override
  Future<List<SubscriptionPlanModel>> fetchPlans() async =>
      [_starter, _growth, _pro];

  @override
  Future<SubscriptionUsageModel> fetchUsage(String sellerId) async => usage;

  @override
  Future<List<BillingHistoryEntryModel>> billingHistory(String sellerId,
          {int limit = 24}) async =>
      [_entry(status: 'pending', created: DateTime.now()), _entry()];

  @override
  Future<BillingProfileModel?> fetchBillingProfile(String sellerId) async =>
      profile;

  @override
  Future<void> saveBillingProfile(BillingProfileModel p) async => profile = p;

  @override
  Future<void> cancelSubscription({String? reason}) async {
    cancelReason = reason;
    usage = _usage(ending: true);
  }

  @override
  Future<void> resumeSubscription() async => usage = _usage();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
