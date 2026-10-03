import '../../core/constants/app_constants.dart';

/// Sellora's service fee as an admin has set it (the `fees` row of
/// `app_config`, read through `service_fee_settings()`). Mirrors
/// `supabase/functions/_shared/fees.js`, which is what checkout actually
/// charges; this copy is for pricing previews and the admin editor.
///
/// Every order snapshots the rate and base it was charged
/// ([OrderModel.serviceFeeRate], [OrderModel.serviceFeeBase]), so a change
/// here never alters a historical order.
class FeeSettings {
  const FeeSettings({
    this.serviceFeeRate = AppConstants.platformServiceFeeRate,
    this.chargeOnShipping = false,
  });

  /// The highest rate the database accepts (`app_config_fees_valid`).
  static const maxServiceFeeRate = 0.3;

  static const defaults = FeeSettings();

  /// A fraction: 0.07 is 7%.
  final double serviceFeeRate;

  /// Whether the fee also takes the buyer's shipping charge. Off by
  /// default: the fee is on the goods only, never shipping or tax.
  final bool chargeOnShipping;

  /// The rate as a percentage for display, e.g. `7` or `6.5`.
  String get percentLabel => percentOf(serviceFeeRate);

  /// [rate] as a percentage for display. Rounded to hundredths first:
  /// `0.07 * 100` is 7.000000000000001 in floating point.
  static String percentOf(double rate) {
    final percent = (rate * 10000).round() / 100;
    if (percent == percent.roundToDouble()) return percent.toStringAsFixed(0);
    return percent.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');
  }

  /// The fee on an order with these goods and shipping charges.
  double feeOn(double goods, {double shipping = 0}) {
    final base = goods + (chargeOnShipping ? shipping : 0);
    return (base * serviceFeeRate * 100).round() / 100;
  }

  /// Falls back to [defaults] for anything missing or out of range, the
  /// same way fees.js does.
  factory FeeSettings.fromMap(Map<String, dynamic>? map) {
    final rate = (map?['serviceFeeRate'] as num?)?.toDouble();
    return FeeSettings(
      serviceFeeRate: rate != null && rate >= 0 && rate <= maxServiceFeeRate
          ? rate
          : AppConstants.platformServiceFeeRate,
      chargeOnShipping: map?['chargeOnShipping'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'serviceFeeRate': serviceFeeRate,
        'chargeOnShipping': chargeOnShipping,
      };
}
