import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/billing_history_entry_model.dart';
import '../models/subscription_plan_model.dart';
import '../models/subscription_usage_model.dart';
import '../services/supabase_service.dart';
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

  /// Always the signed-in seller's own: `my_plan_usage()` reads `auth.uid()`.
  @override
  Future<SubscriptionUsageModel> fetchUsage(String sellerId) async {
    final res = await _db.client.rpc('my_plan_usage');
    return SubscriptionUsageModel.fromMap(
        Map<String, dynamic>.from(res as Map));
  }

  @override
  Future<List<BillingHistoryEntryModel>> billingHistory(String sellerId,
      {int limit = 24}) async {
    final rows = await _db.billingHistory
        .select()
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map((r) => BillingHistoryEntryModel.fromMap(fromRow(r)))
        .toList();
  }
}
