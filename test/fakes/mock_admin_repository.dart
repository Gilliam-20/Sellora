import 'package:get/get.dart';
import 'package:sellora/data/models/user_model.dart';
import 'package:sellora/data/repositories/admin_repository.dart';

class MockAdminRepository extends GetxService implements AdminRepository {
  DateTime? _lastSyncedAt;

  final List<UserModel> _sellers = [
    UserModel(
      uid: 'mock-seller',
      name: 'Amina Otieno',
      email: 'amina@example.com',
      role: UserRole.seller,
      phone: '254712345678',
      storeName: "Amina's Curated Picks",
      sellerStatus: SellerStatus.active,
      subscriptionPlanId: 'growth',
      subscriptionActiveUntil: DateTime.now().add(const Duration(days: 18)),
      currencyCode: 'KES',
      createdAt: DateTime.now().subtract(const Duration(days: 40)),
    ),
    UserModel(
      uid: 'mock-seller-2',
      name: 'Brian Kiptoo',
      email: 'brian@example.com',
      role: UserRole.seller,
      phone: '254701234567',
      storeName: 'Brian\'s Gadget Hub',
      sellerStatus: SellerStatus.pendingApproval,
      currencyCode: 'KES',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

  @override
  DateTime? get lastSyncedAt => _lastSyncedAt;

  @override
  Future<List<UserModel>> fetchSellers() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _sellers;
  }

  @override
  Future<void> setSellerStatus(String sellerId, SellerStatus status) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _sellers.indexWhere((s) => s.uid == sellerId);
    if (index != -1)
      _sellers[index] = _sellers[index].copyWith(sellerStatus: status);
  }

  @override
  Future<int> syncCjCatalog() async {
    await Future.delayed(const Duration(seconds: 1));
    _lastSyncedAt = DateTime.now();
    return 6; // matches MockSeedData.catalog() length
  }
}
