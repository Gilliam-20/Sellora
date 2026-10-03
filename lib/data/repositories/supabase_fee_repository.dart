import 'package:get/get.dart';
import '../models/fee_settings.dart';
import '../services/supabase_service.dart';
import 'fee_repository.dart';

class SupabaseFeeRepository extends GetxService implements FeeRepository {
  final SupabaseService _db = Get.find<SupabaseService>();

  /// `service_fee_settings()` supplies the defaults when no admin has set
  /// anything, and `app_config` itself stays admin-only.
  @override
  Future<FeeSettings> settings() async {
    final result = await _db.client.rpc('service_fee_settings');
    return FeeSettings.fromMap(
        result is Map ? Map<String, dynamic>.from(result) : null);
  }

  /// RLS lets only an admin write `app_config`; the
  /// `app_config_fees_valid` constraint refuses a rate outside 0-30%, and
  /// the change is audited.
  @override
  Future<void> update(FeeSettings settings) async {
    await _db.appConfig.upsert({
      'key': 'fees',
      'value': settings.toMap(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
