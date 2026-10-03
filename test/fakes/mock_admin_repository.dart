import 'package:get/get.dart';
import 'package:sellora/data/models/activity_models.dart';
import 'package:sellora/data/models/platform_metrics_model.dart';
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

  /// What [platformMetrics] returns; tests set it.
  PlatformMetrics metrics = const PlatformMetrics(
    days: 30,
    lifetime: PlatformTotals(
        gmvKes: 4000, serviceFeesKes: 280, refundsKes: 0, paidOrders: 1),
    window: PlatformTotals(
        gmvKes: 4000, serviceFeesKes: 280, refundsKes: 0, paidOrders: 1),
    series: [],
    subscriptions: SubscriptionHealth(active: 1, lapsed30d: 0, mrrKes: 3250),
  );
  int? lastMetricsDays;

  /// Store id -> (suspended, reason), as [setStoreSuspended] last left it.
  final storeSuspensions = <String, (bool, String?)>{};
  final auditEntries = <AuditLogEntry>[];
  final errorReports = <ClientErrorReport>[];

  @override
  Future<void> setStoreSuspended(String storeId,
      {required bool suspended, String? reason}) async {
    storeSuspensions[storeId] = (suspended, suspended ? reason : null);
  }

  @override
  Future<PlatformMetrics> platformMetrics({int days = 30}) async {
    lastMetricsDays = days;
    return metrics;
  }

  @override
  Future<List<AuditLogEntry>> auditLog({int limit = 100}) async =>
      auditEntries.take(limit).toList();

  @override
  Future<List<ClientErrorReport>> clientErrors({int limit = 200}) async =>
      errorReports.take(limit).toList();

  @override
  Future<int> syncCjCatalog() async {
    await Future.delayed(const Duration(seconds: 1));
    _lastSyncedAt = DateTime.now();
    return 6; // matches MockSeedData.catalog() length
  }
}
