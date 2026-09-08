import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/product_model.dart';

/// Talks to CJ Dropshipping ONLY through Sellora's own Cloud Functions
/// (see /functions/src/cj.ts) — the CJ API key/secret never ships
/// inside the Flutter app, mobile or web.
///
/// Typical flow:
///  1. Seller browses `searchProducts` (proxied CJ catalog search).
///  2. Seller lists a product -> ProductRepository writes a `listings`
///     doc referencing the CJ product id, with the seller's own price.
///  3. Buyer places an order -> OrderRepository calls `createCjOrder`
///     so Cloud Functions forwards the real fulfillment order to CJ.
class CjDropshippingService extends GetxService {
  final DioClient _dio = Get.find<DioClient>();

  Future<List<ProductModel>> searchProducts(
      {String? keyword, String? category, int page = 1}) async {
    final res = await _dio.get(ApiEndpoints.cjSearchProducts, query: {
      if (keyword != null) 'keyword': keyword,
      if (category != null) 'category': category,
      'page': page,
    });
    final items = (res['products'] as List? ?? []);
    return items
        .map((e) => ProductModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ProductModel> productDetail(String cjProductId) async {
    final res = await _dio
        .get(ApiEndpoints.cjProductDetail, query: {'id': cjProductId});
    return ProductModel.fromMap(res);
  }

  /// Places the real fulfillment order with CJ once a buyer pays.
  /// Returns CJ's own order id/tracking reference.
  Future<String> createFulfillmentOrder({
    required String cjProductId,
    required int quantity,
    required String shippingAddress,
    String? variant,
  }) async {
    final res = await _dio.post(ApiEndpoints.cjCreateOrder, data: {
      'cjProductId': cjProductId,
      'quantity': quantity,
      'shippingAddress': shippingAddress,
      'variant': variant,
    });
    return res['cjOrderId'] as String? ?? '';
  }

  Future<String> trackShipment(String cjOrderId) async {
    final res =
        await _dio.get(ApiEndpoints.cjTrackShipment, query: {'id': cjOrderId});
    return res['status'] as String? ?? 'processing';
  }
}
