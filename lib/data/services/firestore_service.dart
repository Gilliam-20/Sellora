import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

/// Thin wrapper around Firestore collection references so repositories
/// don't sprinkle raw collection-path strings everywhere.
class FirestoreService extends GetxService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get catalog => _db.collection('catalog'); // shared CJ-sourced products
  CollectionReference<Map<String, dynamic>> get listings => _db.collection('listings'); // seller-specific listings
  CollectionReference<Map<String, dynamic>> get orders => _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get plans => _db.collection('subscription_plans');
  CollectionReference<Map<String, dynamic>> get billingHistory => _db.collection('billing_history');
}
