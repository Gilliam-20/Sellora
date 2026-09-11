import 'package:get/get.dart';

import 'storefront_controller.dart';

class StorefrontBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(StorefrontController.new);
  }
}
