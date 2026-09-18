import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/cj_category.dart';
import '../models/freight_estimate.dart';
import '../models/product_model.dart';

/// Talks to CJ Dropshipping ONLY through Sellora's own Cloud Functions
/// (see /functions/index.js) — the CJ API key/secret never ships inside
/// the Flutter app, mobile or web.
///
/// Every response from these endpoints is wrapped `{success, data,
/// message}`; a non-2xx status (the only way `success` is ever false)
/// already surfaces as a thrown [ApiException] from [DioClient], so
/// methods here can unwrap `data` directly once the call itself succeeds.
///
/// Typical flow:
///  1. Seller browses [searchProducts] (public CJ catalog search).
///  2. Seller views [productDetail], picks a price -> ProductRepository
///     writes a `listings` doc referencing the CJ product id.
///  3. Admin periodically calls [runCatalogSync] to pull the shared
///     catalog/categories into Firestore for the backend's own use.
///
/// NOTE: fulfillment (placing the real order with CJ once a buyer pays)
/// and shipment tracking are order/checkout concerns living on the
/// backend's `createOrder`/`getOrderTracking` endpoints, not this
/// catalog-browsing service — see functions/index.js. There is no
/// standalone "create a CJ order for one product" or "track by CJ order
/// id" endpoint to call from here.
class CjDropshippingService extends GetxService {
  final DioClient _dio = Get.find<DioClient>();

  /// [categoryId] matches CJ's own category id (see [ProductModel.category]
  /// once populated by a search result). [size] is page size, 1-50.
  Future<List<ProductModel>> searchProducts({
    String? keyword,
    String? categoryId,
    int page = 1,
    int size = 20,
  }) async {
    final res = await _dio.get(ApiEndpoints.searchProducts, query: {
      if (keyword != null) 'keyword': keyword,
      if (categoryId != null) 'categoryId': categoryId,
      'page': page,
      'size': size,
    });
    final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
    final items = (data['products'] as List? ?? []);
    return items
        .map((e) => _summaryToProduct(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<ProductModel> productDetail(String cjProductId) async {
    final res = await _dio
        .get(ApiEndpoints.getProductDetail, query: {'pid': cjProductId});
    final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
    return _detailToProduct(data);
  }

  /// Top-level CJ categories, for the catalog browse screen's filter chip
  /// row. CJ's raw tree is 3 levels deep; only level 0 is parsed here (see
  /// [CjCategory]) — this is a filter, not a drill-down browser.
  Future<List<CjCategory>> getCategories() async {
    final res = await _dio.get(ApiEndpoints.getCategories);
    return CjCategory.topLevelFromRawTree(res['data'] as List? ?? []);
  }

  /// Cheapest freight option for [products] (`{vid, quantity}` each)
  /// shipping to [endCountryCode]. Mirrors the cheapest-of-`logisticPrice`
  /// selection functions/lib/orders.js already does server-side at checkout
  /// — this client-side call feeds the seller import screen's landed-cost
  /// pricing card, a separate concern from what checkout actually charges.
  Future<FreightEstimate> calculateFreight({
    required String endCountryCode,
    required List<Map<String, dynamic>> products,
  }) async {
    final res = await _dio.post(ApiEndpoints.calculateFreight, data: {
      'endCountryCode': endCountryCode,
      'products': products,
    });
    final options = (res['data'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    Map<String, dynamic>? cheapest;
    double cheapestPrice = double.infinity;
    for (final option in options) {
      final price = double.tryParse('${option['logisticPrice']}') ?? -1;
      if (price >= 0 && price < cheapestPrice) {
        cheapestPrice = price;
        cheapest = option;
      }
    }
    if (cheapest == null || !cheapestPrice.isFinite) {
      throw StateError('No shipping option is available for this destination');
    }
    return FreightEstimate(
      cost: cheapestPrice,
      logisticName: cheapest['logisticName'] as String? ?? '',
    );
  }

  /// Admin-only. Triggers the full CJ catalog/category sync pipeline
  /// server-side (functions/lib/catalogSync.js) — can take up to several
  /// minutes, hence the extended receive timeout. Returns how many
  /// products were written this run.
  Future<int> runCatalogSync() async {
    final res = await _dio.post(
      ApiEndpoints.runCatalogSync,
      receiveTimeout: const Duration(minutes: 10),
    );
    final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
    if (data['skipped'] == true) return 0;
    final products = Map<String, dynamic>.from(data['products'] as Map? ?? {});
    return (products['written'] as num?)?.toInt() ?? 0;
  }

  /// Maps `searchProducts`' summary shape (functions/lib/cjApi.js) onto
  /// [ProductModel]. The live endpoint carries no stock/rating/sold-count/
  /// discount data, so those stay at their model defaults rather than
  /// being fabricated.
  ProductModel _summaryToProduct(Map<String, dynamic> item) {
    final id = item['id'] as String? ?? '';
    return ProductModel(
      id: id,
      cjProductId: id,
      title: item['name'] as String? ?? '',
      imageUrl: item['image'] as String? ?? '',
      costPrice: (item['supplierPriceUsd'] as num?)?.toDouble() ?? 0,
      sellPrice: (item['retailPriceUsd'] as num?)?.toDouble() ?? 0,
      category: (item['categoryName'] as String?) ??
          (item['categoryId'] as String?) ??
          'General',
    );
  }

  /// Maps `getProductDetail`'s shape (functions/lib/cjApi.js) onto
  /// [ProductModel]. The detail endpoint carries no top-level price or
  /// stock at all — pricing lives per-variant, so this uses the first
  /// variant's price as the product's default (a seller still sets their
  /// own sell price when listing). [_mapVariants] carries each variant's
  /// real CJ `vid` through so it survives to checkout — see
  /// [ProductVariant].
  ProductModel _detailToProduct(Map<String, dynamic> data) {
    final id = data['id'] as String? ?? '';
    final variants = (data['variants'] as List? ?? [])
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    final firstVariant = variants.isNotEmpty ? variants.first : null;
    return ProductModel(
      id: id,
      cjProductId: id,
      title: data['name'] as String? ?? '',
      imageUrl: data['image'] as String? ?? '',
      images: List<String>.from(data['images'] as List? ?? []),
      costPrice: (firstVariant?['supplierPriceUsd'] as num?)?.toDouble() ?? 0,
      sellPrice: (firstVariant?['retailPriceUsd'] as num?)?.toDouble() ?? 0,
      category: (data['categoryName'] as String?) ??
          (data['categoryId'] as String?) ??
          'General',
      description: data['description'] as String? ?? '',
      variants: _mapVariants(variants),
    );
  }

  /// Maps CJ's real per-SKU variant list (each already carrying its own
  /// `vid`/`sku`/`attributes`/price — see functions/lib/cjApi.js's
  /// `getProductDetail`) directly onto [ProductVariant], one purchasable
  /// SKU per entry.
  List<ProductVariant> _mapVariants(List<Map<String, dynamic>> variants) {
    return variants.map((v) {
      final attrs = Map<String, dynamic>.from(v['attributes'] as Map? ?? {});
      return ProductVariant(
        vid: v['vid'] as String? ?? '',
        sku: v['sku'] as String? ?? '',
        attributes: attrs.map((key, value) => MapEntry(key, value.toString())),
        price: (v['retailPriceUsd'] as num?)?.toDouble() ?? 0,
        costPrice: (v['supplierPriceUsd'] as num?)?.toDouble() ?? 0,
        image: v['image'] as String?,
      );
    }).toList();
  }
}
