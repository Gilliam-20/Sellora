/// How a seller pays for their plan, plus what their invoices are made out
/// to. Mirrors `seller_billing_profiles` (one row per seller, the seller's
/// own to write).
///
/// There's no stored card: a card payment always goes through IntaSend's
/// hosted page, so [BillingPaymentMethod.card] only means "take me there".
class BillingProfileModel {
  const BillingProfileModel({
    required this.sellerId,
    this.paymentMethod = BillingPaymentMethod.mpesa,
    this.mpesaPhone,
    this.billingName,
    this.taxId,
    this.updatedAt,
  });

  final String sellerId;
  final BillingPaymentMethod paymentMethod;

  /// 2547XXXXXXXX / 2541XXXXXXXX, the format the payment route sends.
  /// Required when [paymentMethod] is M-Pesa.
  final String? mpesaPhone;

  /// Printed on invoices instead of the seller's name when set.
  final String? billingName;

  /// e.g. a KRA PIN, printed on invoices when set.
  final String? taxId;
  final DateTime? updatedAt;

  /// The number as a Kenyan would write it: 0712 345 678.
  String? get mpesaPhoneDisplay {
    final phone = mpesaPhone;
    if (phone == null || phone.length != 12) return phone;
    final local = '0${phone.substring(3)}';
    return '${local.substring(0, 4)} ${local.substring(4, 7)} ${local.substring(7)}';
  }

  factory BillingProfileModel.fromMap(Map<String, dynamic> map) {
    return BillingProfileModel(
      sellerId: map['sellerId'] as String,
      paymentMethod:
          BillingPaymentMethod.fromId(map['paymentMethod'] as String?),
      mpesaPhone: map['mpesaPhone'] as String?,
      billingName: map['billingName'] as String?,
      taxId: map['taxId'] as String?,
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? ''),
    );
  }

  /// `updatedAt` is left out: the database stamps it.
  Map<String, dynamic> toMap() => {
        'sellerId': sellerId,
        'paymentMethod': paymentMethod.id,
        'mpesaPhone': mpesaPhone,
        'billingName': billingName,
        'taxId': taxId,
      };
}

enum BillingPaymentMethod {
  mpesa('mpesa', 'M-Pesa'),
  card('card', 'Card');

  const BillingPaymentMethod(this.id, this.label);
  final String id;
  final String label;

  static BillingPaymentMethod fromId(String? id) =>
      id == card.id ? card : mpesa;
}
