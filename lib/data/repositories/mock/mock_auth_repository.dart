import 'dart:async';
import 'package:get/get.dart';
import '../../models/user_model.dart';
import '../auth_repository.dart';

/// In-memory stand-in for [FirebaseAuthRepository] used when
/// [AppConstants.useMockData] is true. Accepts any email/password and
/// keeps a single fake user in memory for the session — good enough to
/// demo every screen in the app without a Firebase project.
class MockAuthRepository extends GetxService implements AuthRepository {
  final _controller = StreamController<UserModel?>.broadcast();
  UserModel? _current;

  @override
  UserModel? get cachedUser => _current;

  @override
  Stream<UserModel?> get userChanges => _controller.stream;

  @override
  Future<UserModel> signIn({required String email, required String password}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    // Demo convenience: an email containing "seller" or "admin" logs in
    // to that portal so reviewers can explore all three without a
    // backend. Any other email signs in as a buyer.
    final role = email.contains('admin')
        ? UserRole.admin
        : email.contains('seller')
            ? UserRole.seller
            : UserRole.buyer;

    final user = UserModel(
      uid: 'mock-${role.name}',
      name: role == UserRole.admin ? 'Sellora Admin' : (role == UserRole.seller ? 'Amina\'s Store' : 'Jane Buyer'),
      email: email,
      role: role,
      storeName: role == UserRole.seller ? "Amina's Curated Picks" : null,
      sellerStatus: role == UserRole.seller ? SellerStatus.active : null,
      subscriptionPlanId: role == UserRole.seller ? 'growth' : null,
      subscriptionActiveUntil: role == UserRole.seller ? DateTime.now().add(const Duration(days: 18)) : null,
      currencyCode: 'KES',
      createdAt: DateTime.now(),
    );
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<UserModel> signUpBuyer({required String name, required String email, required String password}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final user = UserModel(
      uid: 'mock-buyer-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      role: UserRole.buyer,
      currencyCode: 'KES',
      createdAt: DateTime.now(),
    );
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<UserModel> signUpSeller({
    required String name,
    required String email,
    required String password,
    required String storeName,
    required String phone,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final user = UserModel(
      uid: 'mock-seller-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      phone: phone,
      role: UserRole.seller,
      storeName: storeName,
      sellerStatus: SellerStatus.pendingApproval,
      currencyCode: 'KES',
      createdAt: DateTime.now(),
    );
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future.delayed(const Duration(milliseconds: 400));
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> updateUser(UserModel user) async {
    _current = user;
    _controller.add(user);
  }
}
