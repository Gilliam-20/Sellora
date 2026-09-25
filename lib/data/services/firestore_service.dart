import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

/// Thin wrapper around Firestore collection references so repositories
/// don't sprinkle raw collection-path strings everywhere.
class FirestoreService extends GetxService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get users =>
      _db.collection('users');
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

  /// One doc per claimed slug (id == slug, `{storeId}`), written in the same
  /// batch as its store. Firestore rules refuse a store whose slug isn't
  /// reserved here, which is what makes slugs actually unique.
  CollectionReference<Map<String, dynamic>> get storeSlugs =>
      _db.collection('store_slugs');

  WriteBatch batch() => _db.batch();

  /// The USD-base rate table `functions/lib/fx.js` refreshes daily —
  /// server-written, publicly readable (see firestore.rules).
  DocumentReference<Map<String, dynamic>> get fxRates =>
      _db.collection('config').doc('fx');

  /// A store's buyers, as `stores/{storeId}/customers/{uid}` — kept as
  /// its own subcollection (not a field on `users`) so a store's seller
  /// can be granted read access to their own customers without touching
  /// the platform-wide `users` collection. See WORKLOG.md.
  CollectionReference<Map<String, dynamic>> storeCustomers(String storeId) =>
      stores.doc(storeId).collection('customers');

  /// Tenant-owned resources. The legacy flat `orders` collection remains
  /// readable during that migration; `listings` doesn't need the same
  /// treatment — nothing reads or writes it any more (see WORKLOG.md,
  /// PHASE 5 write-path migration).
  CollectionReference<Map<String, dynamic>> storeProducts(String storeId) =>
      stores.doc(storeId).collection('products');

  CollectionReference<Map<String, dynamic>> storeOrders(String storeId) =>
      stores.doc(storeId).collection('orders');

  /// Every store's products in one query, for reads that used to span the
  /// flat `listings` collection (a seller's own listings by id, or the
  /// active-listings feed) and now have to span `stores/*/products`
  /// instead. Requires the matching collection-group field overrides in
  /// `firestore.indexes.json`.
  Query<Map<String, dynamic>> get productsGroup => _db.collectionGroup('products');

  /// A private inbox below each user's document.
  CollectionReference<Map<String, dynamic>> userNotifications(String userId) =>
      users.doc(userId).collection('notifications');
}
