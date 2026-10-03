import '../models/fee_settings.dart';

abstract class FeeRepository {
  /// The service fee in force. Sellers and admin only.
  Future<FeeSettings> settings();

  /// Admin only. Applies to orders placed from now on; every existing order
  /// keeps the fee it was charged.
  Future<void> update(FeeSettings settings);
}
