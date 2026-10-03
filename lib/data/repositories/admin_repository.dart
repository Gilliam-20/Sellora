import '../models/activity_models.dart';
import '../models/platform_metrics_model.dart';
import '../models/user_model.dart';

abstract class AdminRepository {
  Future<List<UserModel>> fetchSellers();
  Future<void> setSellerStatus(String sellerId, SellerStatus status);

  /// Takes one store offline (or back online) without touching its seller's
  /// account. [reason] is shown to the seller; it's cleared on lifting.
  Future<void> setStoreSuspended(String storeId,
      {required bool suspended, String? reason});

  /// KES platform totals over every paid order, plus a [days]-long daily
  /// series and subscription health — `admin_platform_metrics`.
  Future<PlatformMetrics> platformMetrics({int days = 30});

  /// The newest [limit] audit-log rows.
  Future<List<AuditLogEntry>> auditLog({int limit = 100});

  /// The newest [limit] client error reports.
  Future<List<ClientErrorReport>> clientErrors({int limit = 200});

  /// Triggers the server-side CJ catalog/category sync (writes the shared
  /// `catalog_products`/`catalog_categories` tables with the service role —
  /// see supabase/functions/api/index.ts's `runCatalogSync`). Returns how
  /// many products were written this run.
  Future<int> syncCjCatalog();
  DateTime? get lastSyncedAt;
}
