/// A buyer registered with one store (`store_customers` table). Created by
/// the sign-up trigger only; the store's owner can read their own.
class StoreCustomerModel {
  StoreCustomerModel({
    required this.storeId,
    required this.uid,
    required this.name,
    required this.email,
    this.createdAt,
  });

  final String storeId;
  final String uid;
  final String name;
  final String email;
  final DateTime? createdAt;

  factory StoreCustomerModel.fromMap(Map<String, dynamic> map) =>
      StoreCustomerModel(
        storeId: map['storeId'] as String? ?? '',
        uid: map['uid'] as String,
        name: map['name'] as String? ?? '',
        email: map['email'] as String? ?? '',
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? ''),
      );
}
