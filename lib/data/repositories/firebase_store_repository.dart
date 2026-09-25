import 'package:get/get.dart';
import '../models/store_model.dart';
import '../services/firestore_service.dart';
import 'store_repository.dart';

class FirebaseStoreRepository extends GetxService implements StoreRepository {
  final FirestoreService _fs = Get.find<FirestoreService>();

  @override
  Future<List<StoreModel>> allStores() async {
    final snap = await _fs.stores.get();
    return snap.docs.map((d) => StoreModel.fromMap(d.data())).toList();
  }

  @override
  Future<StoreModel?> storeById(String storeId) async {
    final doc = await _fs.stores.doc(storeId).get();
    return doc.exists ? StoreModel.fromMap(doc.data()!) : null;
  }

  @override
  Future<StoreModel?> storeBySlug(String slug) async {
    final snap = await _fs.stores.where('slug', isEqualTo: slug).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return StoreModel.fromMap(snap.docs.first.data());
  }

  @override
  Future<List<StoreModel>> storesForSeller(String sellerId) async {
    final snap = await _fs.stores.where('sellerId', isEqualTo: sellerId).get();
    return snap.docs.map((d) => StoreModel.fromMap(d.data())).toList();
  }

  @override
  Future<StoreModel> createStore(StoreModel store) async {
    // Store and slug reservation land together or not at all. If the slug
    // was taken since the caller's storeBySlug() check, the reservation
    // create is refused by firestore.rules and the whole batch fails —
    // no half-created store.
    final batch = _fs.batch()
      ..set(_fs.stores.doc(store.id), store.toMap())
      ..set(_fs.storeSlugs.doc(store.slug), {'storeId': store.id});
    await batch.commit();
    return store;
  }

  @override
  Future<void> updateStore(StoreModel store) async {
    await _fs.stores.doc(store.id).update(store.toMap());
  }
}
