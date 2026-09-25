import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/fx_rates.dart';
import '../services/firestore_service.dart';
import 'fx_rate_repository.dart';

class FirebaseFxRateRepository extends GetxService implements FxRateRepository {
  final FirestoreService _fs = Get.find<FirestoreService>();

  @override
  Future<FxRates?> latestRates() async {
    final doc = await _fs.fxRates.get();
    if (!doc.exists) return null;
    final data = Map<String, dynamic>.from(doc.data()!);
    final fetchedAt = data['fetchedAt'];
    if (fetchedAt is Timestamp) data['fetchedAt'] = fetchedAt.toDate();
    return FxRates.fromMap(data);
  }
}
