import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/billing_history_entry_model.dart';
import '../models/subscription_plan_model.dart';
import '../models/subscription_usage_model.dart';
import '../services/supabase_service.dart';
import 'product_repository.dart';
import 'subscription_repository.dart';

class SupabaseSubscriptionRepository extends GetxService
    implements SubscriptionRepository {
  final SupabaseService _db = Get.find<SupabaseService>();
  final DioClient _dio = Get.find<DioClient>();

  @override
  Future<List<SubscriptionPlanModel>> fetchPlans() async {
    final rows = await _db.plans.select();
    return rows.map((r) => SubscriptionPlanModel.fromMap(fromRow(r))).toList();
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
    await _db.plans.upsert(toRow(plan.toMap()));
  }

  @override
  Future<SubscriptionUsageModel> fetchUsage(String sellerId) async {
    final profile = await _db.profiles
        .select('subscription_plan_id')
        .eq('uid', sellerId)
        .maybeSingle();
    final planId = profile?['subscription_plan_id'] as String?;
    final plans = await fetchPlans();
    SubscriptionPlanModel? plan;
    for (final p in plans) {
      if (p.id == planId) {
        plan = p;
        break;
      }
    }
    final listings =
        await Get.find<ProductRepository>().sellerListings(sellerId);
    return SubscriptionUsageModel(
      listingCount: listings.length,
      listingLimit: plan?.listingLimit ?? -1,
    );
  }
}
