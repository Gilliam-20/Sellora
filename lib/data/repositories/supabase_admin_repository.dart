import 'package:get/get.dart';
import '../models/activity_models.dart';
import '../models/platform_metrics_model.dart';
import '../models/user_model.dart';
import '../services/cj_dropshipping_service.dart';
import '../services/supabase_service.dart';
import 'admin_repository.dart';

class SupabaseAdminRepository extends GetxService implements AdminRepository {
  final SupabaseService _db = Get.find<SupabaseService>();
  final CjDropshippingService _cj = Get.find<CjDropshippingService>();

  DateTime? _lastSyncedAt;

  @override
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// RLS lets only the admin (app_metadata.role) read other profiles.
  @override
  Future<List<UserModel>> fetchSellers() async {
    final rows = await _db.profiles.select().eq('role', 'seller');
    return rows.map((r) => UserModel.fromMap(fromRow(r))).toList();
  }

  @override
  Future<void> setSellerStatus(String sellerId, SellerStatus status) async {
    await _db.profiles
        .update({'seller_status': status.name}).eq('uid', sellerId);
  }

  /// The `stores_guard_update` trigger lets only an admin write these.
  @override
  Future<void> setStoreSuspended(String storeId,
      {required bool suspended, String? reason}) async {
    await _db.stores.update({
      'is_suspended': suspended,
      'suspension_reason': suspended ? reason : null,
      'suspended_at':
          suspended ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', storeId);
  }

  @override
  Future<PlatformMetrics> platformMetrics({int days = 30}) async {
    final result = await _db.client
        .rpc('admin_platform_metrics', params: {'p_days': days});
    return result is Map
        ? PlatformMetrics.fromMap(Map<String, dynamic>.from(result))
        : PlatformMetrics.empty;
  }

  @override
  Future<List<AuditLogEntry>> auditLog({int limit = 100}) async {
    final rows = await _db.auditLogs
        .select()
        .order('occurred_at', ascending: false)
        .limit(limit);
    return rows.map((r) => AuditLogEntry.fromMap(fromRow(r))).toList();
  }

  @override
  Future<List<ClientErrorReport>> clientErrors({int limit = 200}) async {
    final rows = await _db.clientErrors
        .select()
        .order('occurred_at', ascending: false)
        .limit(limit);
    return rows.map((r) => ClientErrorReport.fromMap(fromRow(r))).toList();
  }

  @override
  Future<int> syncCjCatalog() async {
    // The real sync pipeline (categories + products + detail/variant
    // enrichment + stale-deactivation) runs entirely server-side, admin-
    // gated — see supabase/functions/api/index.ts's runCatalogSync and
    // supabase/functions/_shared/catalogSync.js — so there is nothing left for the
    // client to batch-write itself.
    final count = await _cj.runCatalogSync();
    _lastSyncedAt = DateTime.now();
    return count;
  }
}
