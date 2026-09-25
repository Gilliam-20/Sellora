import '../models/fx_rates.dart';

abstract class FxRateRepository {
  /// The most recent server-cached exchange-rate table, or null if none has
  /// ever been written (the server's daily `refreshFxRates` hasn't run yet).
  Future<FxRates?> latestRates();
}
