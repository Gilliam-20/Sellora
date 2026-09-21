import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import 'storage_service.dart';

/// Lets a buyer pick which currency prices are *displayed* in — USD or
/// KES. Records still store the amount in whatever currency the seller
/// actually charges (ProductModel.currency, OrderModel.currency); this
/// only converts what's shown, using [AppConstants.usdToKesRate] as a
/// fixed approximation, since there's no live FX-rate source yet. The
/// choice persists across restarts via [StorageService.currencyCode].
class CurrencyService extends GetxService {
  CurrencyService() : _storage = Get.find<StorageService>() {
    code = Rx<String>(_normalize(_storage.currencyCode));
  }

  final StorageService _storage;

  static const supported = ['USD', 'KES'];

  late final Rx<String> code;

  static String _normalize(String value) =>
      supported.contains(value) ? value : 'USD';

  void setCode(String value) {
    if (!supported.contains(value) || value == code.value) return;
    code.value = value;
    _storage.currencyCode = value;
  }

  double convert(double amount, String fromCode) {
    if (fromCode == code.value) return amount;
    final amountUsd =
        fromCode == 'KES' ? amount / AppConstants.usdToKesRate : amount;
    return code.value == 'KES'
        ? amountUsd * AppConstants.usdToKesRate
        : amountUsd;
  }

  String format(double amount, {String fromCode = 'USD'}) =>
      Formatters.currency(convert(amount, fromCode), code: code.value);
}
