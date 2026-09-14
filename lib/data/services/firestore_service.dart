import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

/// Thin wrapper around Firestore collection references so repositories
/// don't sprinkle raw collection-path strings everywhere.
class FirestoreService extends GetxService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get listings =>
      _db.collection('listings'); // seller-specific listings
  CollectionReference<Map<String, dynamic>> get orders =>
      _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get plans =>
      _db.collection('subscription_plans');
  CollectionReference<Map<String, dynamic>> get billingHistory =>
      _db.collection('billing_history');
  CollectionReference<Map<String, dynamic>> get subscriptions =>
      _db.collection('subscriptions');
  CollectionReference<Map<String, dynamic>> get stores =>
      _db.collection('stores');

  /// A store's buyers, as `stores/{storeId}/customers/{uid}` — kept as
  /// its own subcollection (not a field on `users`) so a store's seller
  /// can be granted read access to their own customers without touching
  /// the platform-wide `users` collection. See WORKLOG.md.
  CollectionReference<Map<String, dynamic>> storeCustomers(String storeId) =>
      stores.doc(storeId).collection('customers');

  /// Tenant-owned resources. These paths are introduced additively; the
  /// legacy flat listing/order collections remain readable during migration.
  CollectionReference<Map<String, dynamic>> storeProducts(String storeId) =>
      stores.doc(storeId).collection('products');

  CollectionReference<Map<String, dynamic>> storeOrders(String storeId) =>
      stores.doc(storeId).collection('orders');
}
