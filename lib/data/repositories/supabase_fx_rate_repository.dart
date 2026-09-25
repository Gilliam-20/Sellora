import 'package:get/get.dart';
import '../models/fx_rates.dart';
import '../services/supabase_service.dart';
import 'fx_rate_repository.dart';

class SupabaseFxRateRepository extends GetxService implements FxRateRepository {
  final SupabaseService _db = Get.find<SupabaseService>();

  @override
  Future<FxRates?> latestRates() async {
    final row = await _db.fxRates.select().eq('id', 'current').maybeSingle();
    return row == null ? null : FxRates.fromMap(fromRow(row));
  }
}
