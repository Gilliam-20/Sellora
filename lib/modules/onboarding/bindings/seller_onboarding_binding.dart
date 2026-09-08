import 'package:get/get.dart';
import '../controllers/seller_onboarding_controller.dart';

class SellerOnboardingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SellerOnboardingController>(() => SellerOnboardingController());
  }
}
