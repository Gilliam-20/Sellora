import 'package:get/get.dart';
import '../models/subscription_plan_model.dart';
import '../services/firestore_service.dart';
import 'subscription_repository.dart';

class FirebaseSubscriptionRepository extends GetxService
    implements SubscriptionRepository {
  final FirestoreService _fs = Get.find<FirestoreService>();

  @override
  Future<List<SubscriptionPlanModel>> fetchPlans() async {
    final snap = await _fs.plans.get();
    return snap.docs
        .map((d) => SubscriptionPlanModel.fromMap(d.data()))
        .toList();
  }

  @override
  Future<void> subscribeSeller(
      {required String sellerId,
      required String planId,
      required String paymentReference}) async {
    final plan = (await fetchPlans()).firstWhere((p) => p.id == planId);
    final activeUntil =
        DateTime.now().add(Duration(days: plan.billingPeriodDays));
    await _fs.users.doc(sellerId).update({
      'subscriptionPlanId': planId,
      'subscriptionActiveUntil': activeUntil.toIso8601String(),
      'sellerStatus': 'active',
    });
    await _fs.billingHistory.add({
      'sellerId': sellerId,
      'planId': planId,
      'paymentReference': paymentReference,
      'paidAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> updatePlan(SubscriptionPlanModel plan) async {
    await _fs.plans.doc(plan.id).set(plan.toMap());
  }
}
