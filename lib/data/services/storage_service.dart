import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// Thin wrapper over GetStorage for anything that should survive an
/// app restart without a network round trip: last-used role, onboarding
/// completion, cached currency preference, etc.
class StorageService extends GetxService {
  final _box = GetStorage();

  static const _kLastRole = 'last_role';
  static const _kOnboardingDone = 'onboarding_done';
  static const _kCurrency = 'currency_code';

  String? get lastRole => _box.read(_kLastRole);
  set lastRole(String? value) => _box.write(_kLastRole, value);

  bool get onboardingDone => _box.read(_kOnboardingDone) ?? false;
  set onboardingDone(bool value) => _box.write(_kOnboardingDone, value);

  String get currencyCode => _box.read(_kCurrency) ?? 'USD';
  set currencyCode(String value) => _box.write(_kCurrency, value);

  Future<void> clear() => _box.erase();
}
