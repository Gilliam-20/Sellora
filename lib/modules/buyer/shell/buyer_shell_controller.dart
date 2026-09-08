import 'package:get/get.dart';

class BuyerShellController extends GetxController {
  final tabIndex = 0.obs;

  @override
  void onInit() {
    super.onInit();
    // Consumed once here rather than in the view's build() — reading
    // Get.arguments from build() would re-apply the initial tab (and
    // stomp on wherever the user has since navigated to) on every
    // rebuild, including the MediaQuery-driven rebuilds a responsive
    // layout triggers on resize.
    final args = Get.arguments as Map?;
    final initialTab = args?['tab'];
    if (initialTab is int) tabIndex.value = initialTab;
  }

  void changeTab(int index) => tabIndex.value = index;
}
