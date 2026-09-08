import 'package:get/get.dart';

class SellerShellController extends GetxController {
  final tabIndex = 0.obs;
  void changeTab(int index) => tabIndex.value = index;
}
