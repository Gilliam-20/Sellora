import 'package:get/get.dart';
import '../../models/fx_rates.dart';
import '../fx_rate_repository.dart';

class MockFxRateRepository extends GetxService implements FxRateRepository {
  @override
  Future<FxRates?> latestRates() async {
    await Future.delayed(const Duration(milliseconds: 150));
    // The fallback table, stamped as freshly fetched so demo mode behaves
    // like a healthy server cache rather than the no-rates-yet path.
    return FxRates(rates: FxRates.fallback.rates, fetchedAt: DateTime.now());
  }
}
