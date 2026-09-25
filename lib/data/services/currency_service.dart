import 'package:get/get.dart';
import '../../core/i18n/currencies.dart';
import '../../core/i18n/money.dart';
import '../../core/utils/formatters.dart';
import '../models/fx_rates.dart';
import '../repositories/fx_rate_repository.dart';
import 'storage_service.dart';

/// Lets a buyer pick which currency prices are *displayed* in — any of
/// [Currencies.all]. Records still store the amount in whatever currency the
/// seller actually charges (ProductModel.currency, OrderModel.currency);
/// this only converts what's shown, using the server's cached daily rate
/// table ([FxRateRepository]) once [refreshRates] loads it, and
/// [FxRates.fallback] until then. The choice persists across restarts via
/// [StorageService.currencyCode].
class CurrencyService extends GetxService {
  CurrencyService() : _storage = Get.find<StorageService>() {
    code = Rx<String>(_normalize(_storage.currencyCode));
  }

  final StorageService _storage;

  static List<String> get supported => Currencies.codes;

  late final Rx<String> code;
  final rates = Rx<FxRates>(FxRates.fallback);

  static String _normalize(String value) =>
      Currencies.isSupported(value) ? value : 'USD';

  void setCode(String value) {
    if (!Currencies.isSupported(value) || value == code.value) return;
    code.value = value;
    _storage.currencyCode = value;
  }

  /// Loads the latest server rate table. Never throws — a failure (offline,
  /// no table written yet) just leaves the current table, fallback or not,
  /// in place, since these rates only ever drive display estimates.
  /// Resolves [FxRateRepository] lazily because this service is registered
  /// before any repository (see InitialBinding).
  Future<void> refreshRates() async {
    try {
      final latest = await Get.find<FxRateRepository>().latestRates();
      if (latest != null) rates.value = latest;
    } catch (_) {
      // Keep whatever table we already have.
    }
  }

  /// Converts [amount] from [fromCode] into [toCode], rounded to [toCode]'s
  /// minor unit. Returns the input unchanged if no rate exists for the pair
  /// — only possible for a currency outside [Currencies.all].
  Money convertMoney(Money amount, String toCode) {
    if (amount.currency == toCode) return amount;
    final rate = rates.value.rateBetween(amount.currency, toCode);
    return rate == null ? amount : amount.convertTo(toCode, rate);
  }

  /// [amount] in [fromCode], converted into the buyer's display currency.
  double convert(double amount, String fromCode) =>
      convertMoney(Money.fromMajor(amount, fromCode), code.value).toMajor();

  /// Whether amounts in [fromCode] are shown converted (and so are an
  /// estimate) rather than in the currency actually charged.
  bool isConverted(String fromCode) =>
      fromCode != code.value &&
      rates.value.rateBetween(fromCode, code.value) != null;

  String format(double amount, {String fromCode = 'USD'}) {
    final converted =
        convertMoney(Money.fromMajor(amount, fromCode), code.value);
    return Formatters.money(converted);
  }
}
