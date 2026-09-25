import 'package:get/get.dart';
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

  @override
  Future<int> syncCjCatalog() async {
    // The real sync pipeline (categories + products + detail/variant
    // enrichment + stale-deactivation) runs entirely server-side, admin-
    // gated — see functions/index.js's runCatalogSync and
    // functions/lib/catalogSync.js — so there is nothing left for the
    // client to batch-write itself.
    final count = await _cj.runCatalogSync();
    _lastSyncedAt = DateTime.now();
    return count;
  }
}
