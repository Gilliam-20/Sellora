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
    // The real sync pipeline (categories + products + detail/variant
    // enrichment + stale-deactivation) runs entirely server-side, admin-
    // claim-gated — see functions/index.js's runCatalogSync and
    // functions/lib/catalogSync.js. It writes Firestore's top-level
    // `products`/`categories` collections directly via the Admin SDK, so
    // there is nothing left for the client to batch-write itself.
    final count = await _cj.runCatalogSync();
    _lastSyncedAt = DateTime.now();
    return count;
  }
}
