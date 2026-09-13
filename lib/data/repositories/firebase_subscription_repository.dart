import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/billing_history_entry_model.dart';
import '../models/subscription_plan_model.dart';
import '../models/subscription_usage_model.dart';
import '../services/firestore_service.dart';
import 'product_repository.dart';
import 'subscription_repository.dart';

class FirebaseSubscriptionRepository extends GetxService
    implements SubscriptionRepository {
  final FirestoreService _fs = Get.find<FirestoreService>();
  final DioClient _dio = Get.find<DioClient>();

  @override
  Future<List<SubscriptionPlanModel>> fetchPlans() async {
    final snap = await _fs.plans.get();
    return snap.docs
        .map((d) => SubscriptionPlanModel.fromMap(d.data()))
        .toList();
  }

  @override
  Future<BillingHistoryEntryModel> subscribeSeller({
    required String sellerId,
    required String planId,
  }) async {
    final res = await _dio.post(ApiEndpoints.subscribeSeller, data: {
      'planId': planId,
    });
    return BillingHistoryEntryModel.fromMap(
        Map<String, dynamic>.from(res['data'] as Map));
  }

  @override
  Future<void> updatePlan(SubscriptionPlanModel plan) async {
    await _fs.plans.doc(plan.id).set(plan.toMap());
  }

  @override
  Future<SubscriptionUsageModel> fetchUsage(String sellerId) async {
    final userDoc = await _fs.users.doc(sellerId).get();
    final planId = userDoc.data()?['subscriptionPlanId'] as String?;
    final plans = await fetchPlans();
    SubscriptionPlanModel? plan;
    for (final p in plans) {
      if (p.id == planId) {
        plan = p;
        break;
      }
    }
    final listings = await Get.find<ProductRepository>().sellerListings(sellerId);
    return SubscriptionUsageModel(
      listingCount: listings.length,
      listingLimit: plan?.listingLimit ?? -1,
    );
  }
}
