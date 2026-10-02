import 'package:get/get.dart';
import '../models/store_customer_model.dart';
import '../services/supabase_service.dart';
import 'customer_repository.dart';

class SupabaseCustomerRepository extends GetxService
    implements CustomerRepository {
  final SupabaseService _db = Get.find<SupabaseService>();

  @override
  Future<List<StoreCustomerModel>> storeCustomers(String storeId) async {
    final rows = await _db.storeCustomers
        .select()
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return rows.map((r) => StoreCustomerModel.fromMap(fromRow(r))).toList();
  }
}
