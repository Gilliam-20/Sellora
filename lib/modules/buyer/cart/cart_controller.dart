import 'package:get/get.dart';
import '../../../data/repositories/cart_repository.dart';

class CartController extends GetxController {
  final CartRepository cartRepo = Get.find<CartRepository>();
}
