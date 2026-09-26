import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sellora/data/models/order_model.dart';
import 'package:sellora/data/models/user_model.dart';
import 'package:sellora/data/repositories/admin_repository.dart';
import 'package:sellora/data/repositories/auth_repository.dart';
import 'fakes/mock_admin_repository.dart';
import 'fakes/mock_order_repository.dart';
import 'fakes/mock_store_repository.dart';
import 'fakes/mock_subscription_repository.dart';
import 'package:sellora/data/repositories/order_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';
import 'package:sellora/data/repositories/subscription_repository.dart';
import 'package:sellora/modules/admin/dashboard/admin_dashboard_controller.dart';

void main() {
  tearDown(Get.reset);

  test('load() separates seller GMV, service-fee revenue and subscription MRR',
      () async {
    Get.put<AdminRepository>(MockAdminRepository());
    final orders = MockOrderRepository();
    Get.put<OrderRepository>(orders);
    Get.put<StoreRepository>(MockStoreRepository());
    Get.put<SubscriptionRepository>(
        MockSubscriptionRepository(authRepository: _FakeAuthRepository()));

    // A paid order (counts toward GMV/fee revenue) and an unpaid one
    // (must not) — mirrors OrderModel's real fee snapshot shape.
    await orders.placeOrder(_order(
      id: 'o1',
      total: 4000,
      serviceFeeAmount: 80,
      paymentStatus: OrderPaymentStatus.paid,
    ));
    await orders.placeOrder(_order(
      id: 'o2',
      total: 1500,
      serviceFeeAmount: 30,
      paymentStatus: OrderPaymentStatus.pending,
    ));

    final controller = AdminDashboardController();
    await controller.load();

    // Only the paid order counts.
    expect(controller.totalGmv, 4000);
    expect(controller.serviceFeeRevenue, 80);

    // MockAdminRepository seeds one active seller on the 'growth' plan
    // (priceKes 3250) and one pending seller with no subscription.
    expect(controller.subscriptionMrr, 3250);
    expect(controller.totalPlatformRevenue, 80 + 3250);

    expect(controller.activeSellerCount, 1);
    expect(controller.pendingSellerCount, 1);
    expect(controller.suspendedSellerCount, 0);
    expect(controller.stores.length, 2);
  });
}

OrderModel _order({
  required String id,
  required double total,
  required double serviceFeeAmount,
  required OrderPaymentStatus paymentStatus,
}) {
  return OrderModel(
    id: id,
    code: id,
    buyerId: 'buyer-1',
    sellerId: 'mock-seller',
    storeId: 'store-aminas',
    items: const [],
    status: OrderStatus.pending,
    total: total,
    shippingAddress: ShippingAddress(countryCode: 'KE', line: '123 St'),
    createdAt: DateTime.now(),
    paymentStatus: paymentStatus,
    serviceFeeRate: 0.02,
    serviceFeeAmount: serviceFeeAmount,
    sellerRevenue: total - serviceFeeAmount,
  );
}

class _FakeAuthRepository implements AuthRepository {
  @override
  UserModel? get cachedUser => throw UnimplementedError();

  @override
  Stream<UserModel?> get userChanges => throw UnimplementedError();

  @override
  Future<UserModel?> refreshCurrentUser() => throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();

  @override
  Stream<void> get passwordRecoveries => throw UnimplementedError();

  @override
  bool get isRecoveringPassword => throw UnimplementedError();

  @override
  Future<UserModel> updatePassword(String newPassword) =>
      throw UnimplementedError();

  @override
  Future<bool> checkEmailVerified() => throw UnimplementedError();

  @override
  Future<void> resendVerificationEmail() => throw UnimplementedError();

  @override
  Future<UserModel> signIn(
          {required String email, required String password, String? storeId}) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<void> deleteAccount() => throw UnimplementedError();

  @override
  Future<UserModel> signUpBuyer(
          {required String name,
          required String email,
          required String password,
          required String storeId}) =>
      throw UnimplementedError();

  @override
  Future<UserModel> signUpSeller(
          {required String name,
          required String email,
          required String password,
          required String storeName,
          required String phone,
          required bool hasAcceptedTerms}) =>
      throw UnimplementedError();

  @override
  Future<void> updateUser(UserModel user) => throw UnimplementedError();
}
