enum UserRole { buyer, seller, admin }

UserRole userRoleFromString(String value) {
  return UserRole.values.firstWhere(
    (r) => r.name == value,
    orElse: () => UserRole.buyer,
  );
}

enum SellerStatus { pendingApproval, active, suspended }

/// The version a seller agrees to when opening a Sellora store. Keeping this
/// alongside the acceptance record lets us ask for a new agreement when the
/// terms materially change.
const sellerTermsVersion = '2026-09-17';

class UserModel {
  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.photoUrl,
    this.sellerStatus,
    this.storeName,
    this.subscriptionPlanId,
    this.subscriptionActiveUntil,
    this.sellerTermsAcceptedAt,
    this.sellerTermsVersion,
    this.currencyCode = 'USD',
    this.storeId,
    this.createdAt,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final String? phone;
  final String? photoUrl;

  // Seller-only fields
  final SellerStatus? sellerStatus;
  final String? storeName;
  final String? subscriptionPlanId;
  final DateTime? subscriptionActiveUntil;
  final DateTime? sellerTermsAcceptedAt;
  final String? sellerTermsVersion;
  final String currencyCode;

  // Buyer-only: the store (see StoreModel) they registered as a customer
  // of. A buyer shops exactly one store — this is what scopes their cart
  // and order history.
  final String? storeId;

  final DateTime? createdAt;

  bool get hasActiveSubscription =>
      subscriptionActiveUntil != null &&
      subscriptionActiveUntil!.isAfter(DateTime.now());

  UserModel copyWith({
    String? name,
    String? phone,
    String? photoUrl,
    SellerStatus? sellerStatus,
    String? storeName,
    String? subscriptionPlanId,
    DateTime? subscriptionActiveUntil,
    DateTime? sellerTermsAcceptedAt,
    String? sellerTermsVersion,
    String? currencyCode,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email,
      role: role,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      sellerStatus: sellerStatus ?? this.sellerStatus,
      storeName: storeName ?? this.storeName,
      subscriptionPlanId: subscriptionPlanId ?? this.subscriptionPlanId,
      subscriptionActiveUntil:
          subscriptionActiveUntil ?? this.subscriptionActiveUntil,
      sellerTermsAcceptedAt:
          sellerTermsAcceptedAt ?? this.sellerTermsAcceptedAt,
      sellerTermsVersion: sellerTermsVersion ?? this.sellerTermsVersion,
      currencyCode: currencyCode ?? this.currencyCode,
      createdAt: createdAt,
    );
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: userRoleFromString(map['role'] as String? ?? 'buyer'),
      phone: map['phone'] as String?,
      photoUrl: map['photoUrl'] as String?,
      sellerStatus: map['sellerStatus'] != null
          ? SellerStatus.values.firstWhere((s) => s.name == map['sellerStatus'],
              orElse: () => SellerStatus.pendingApproval)
          : null,
      storeName: map['storeName'] as String?,
      subscriptionPlanId: map['subscriptionPlanId'] as String?,
      subscriptionActiveUntil: map['subscriptionActiveUntil'] != null
          ? DateTime.tryParse(map['subscriptionActiveUntil'] as String)
          : null,
      sellerTermsAcceptedAt: map['sellerTermsAcceptedAt'] != null
          ? DateTime.tryParse(map['sellerTermsAcceptedAt'] as String)
          : null,
      sellerTermsVersion: map['sellerTermsVersion'] as String?,
      currencyCode: map['currencyCode'] as String? ?? 'USD',
      storeId: map['storeId'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role.name,
      'phone': phone,
      'photoUrl': photoUrl,
      'sellerStatus': sellerStatus?.name,
      'storeName': storeName,
      'subscriptionPlanId': subscriptionPlanId,
      'subscriptionActiveUntil': subscriptionActiveUntil?.toIso8601String(),
      'sellerTermsAcceptedAt': sellerTermsAcceptedAt?.toIso8601String(),
      'sellerTermsVersion': sellerTermsVersion,
      'currencyCode': currencyCode,
      'storeId': storeId,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}
