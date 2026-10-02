import '../models/store_customer_model.dart';

/// A store's registered customers. Their orders come from
/// [OrderRepository.storeOrders]; this is who they are.
abstract class CustomerRepository {
  /// Everyone registered with [storeId], newest first. RLS limits it to the
  /// store's owner and admin.
  Future<List<StoreCustomerModel>> storeCustomers(String storeId);
}
