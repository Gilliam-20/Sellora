import 'package:get/get.dart';

import '../../../core/i18n/money.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/store_customer_model.dart';
import '../../../data/repositories/customer_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/services/currency_service.dart';
import '../../storefront/store_scope.dart';
import 'customer_analytics.dart';

/// The seller's Customers screen: who buys from the store, how often and
/// how much (TODO.md §24/§25).
class SellerCustomersController extends GetxController {
  SellerCustomersController({
    CustomerRepository? customerRepository,
    OrderRepository? orderRepository,
    StoreScope? scope,
    ToStoreCurrency? toStoreCurrency,
  })  : _customers = customerRepository ?? Get.find<CustomerRepository>(),
        _orders = orderRepository ?? Get.find<OrderRepository>(),
        scope = scope ?? Get.find<StoreScope>(),
        _toStoreCurrency = toStoreCurrency;

  final CustomerRepository _customers;
  final OrderRepository _orders;
  final StoreScope scope;
  final ToStoreCurrency? _toStoreCurrency;

  final isLoading = true.obs;
  final errorMessage = RxnString();
  final summary = Rxn<CustomerSummary>();
  final query = ''.obs;
  final sortBy = CustomerSort.totalSpent.obs;

  final _all = <CustomerStat>[].obs;

  /// The list as searched and sorted.
  List<CustomerStat> get visible =>
      CustomerAnalytics.filter(_all, query.value, sortBy.value);

  bool get hasCustomers => _all.isNotEmpty;

  /// Every amount on the screen is in this.
  String get currencyCode => scope.current.value?.currencyCode ?? 'KES';

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final storeId = scope.current.value?.id;
    if (storeId == null) {
      errorMessage.value = 'Your store isn\'t loaded yet.';
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final results = await Future.wait([
        _customers.storeCustomers(storeId),
        _orders.storeOrders(storeId),
      ]);
      final analytics = CustomerAnalytics.build(
        members: results[0] as List<StoreCustomerModel>,
        orders: results[1] as List<OrderModel>,
        toStoreCurrency: _toStoreCurrency ?? _convert,
      );
      _all.assignAll(analytics.customers);
      summary.value = analytics.summary;
    } catch (_) {
      errorMessage.value = 'Couldn\'t load your customers.';
    } finally {
      isLoading.value = false;
    }
  }

  // Orders are priced in the shopper's currency; totals are only
  // comparable once they're all in the store's.
  double _convert(double amount, String currency) => Get.find<CurrencyService>()
      .convertMoney(Money.fromMajor(amount, currency), currencyCode)
      .toMajor();

  void search(String value) => query.value = value;

  void sort(CustomerSort order) => sortBy.value = order;
}
