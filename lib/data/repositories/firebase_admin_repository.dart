import 'package:get/get.dart';
import '../models/user_model.dart';
import '../services/cj_dropshipping_service.dart';
import '../services/firestore_service.dart';
import 'admin_repository.dart';

class FirebaseAdminRepository extends GetxService implements AdminRepository {
  final FirestoreService _fs = Get.find<FirestoreService>();
  final CjDropshippingService _cj = Get.find<CjDropshippingService>();

  DateTime? _lastSyncedAt;

  @override
  DateTime? get lastSyncedAt => _lastSyncedAt;

  @override
  Future<List<UserModel>> fetchSellers() async {
    final snap = await _fs.users.where('role', isEqualTo: 'seller').get();
    return snap.docs.map((d) => UserModel.fromMap(d.data())).toList();
  }

  @override
  Future<void> setSellerStatus(String sellerId, SellerStatus status) async {
    await _fs.users.doc(sellerId).update({'sellerStatus': status.name});
  }

  @override
  Future<int> syncCjCatalog() async {
    final products = await _cj.searchProducts(page: 1);
    final batch = _fs.catalog.firestore.batch();
    for (final product in products) {
      batch.set(_fs.catalog.doc(product.id), product.toMap());
    }
    await batch.commit();
    _lastSyncedAt = DateTime.now();
    return products.length;
  }
}
