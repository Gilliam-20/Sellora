import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/discount_model.dart';
import '../services/supabase_service.dart';
import 'discount_repository.dart';

class SupabaseDiscountRepository extends GetxService
    implements DiscountRepository {
  final SupabaseService _db = Get.find<SupabaseService>();

  /// Set once at creation; discounts_guard_update refuses changes to these.
  static const _immutable = {'id', 'storeId', 'createdAt'};

  @override
  Future<List<DiscountModel>> storeDiscounts(String storeId) async {
    final rows = await _db.discounts
        .select()
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return rows.map((r) => DiscountModel.fromMap(fromRow(r))).toList();
  }

  @override
  Future<Map<String, int>> usage(String storeId) async {
    final rows = await _db.client
        .rpc('store_discount_usage', params: {'p_store_id': storeId});
    return {
      for (final row in rows as List)
        row['discount_id'] as String: (row['uses'] as num).toInt(),
    };
  }

  @override
  Future<DiscountModel> createDiscount(DiscountModel discount) async {
    try {
      final row = await _db.discounts
          .insert(toRow(discount.toMap(), omit: const {'id', 'createdAt'}))
          .select()
          .single();
      return DiscountModel.fromMap(fromRow(row));
    } on PostgrestException catch (e) {
      throw _translate(e, discount.code);
    }
  }

  @override
  Future<void> updateDiscount(DiscountModel discount) async {
    try {
      await _db.discounts
          .update(toRow(discount.toMap(), omit: _immutable))
          .eq('id', discount.id);
    } on PostgrestException catch (e) {
      throw _translate(e, discount.code);
    }
  }

  @override
  Future<void> deleteDiscount(String discountId) async {
    try {
      await _db.discounts.delete().eq('id', discountId);
    } on PostgrestException catch (e) {
      // 23503: the orders.discount_id foreign key — an order used it.
      if (e.code == '23503') throw const DiscountInUseException();
      rethrow;
    }
  }

  @override
  Future<DiscountModel?> lookup(String storeId, String code) async {
    final result = await _db.client.rpc('storefront_discount',
        params: {'p_store_id': storeId, 'p_code': code});
    return result is Map
        ? DiscountModel.fromMap(Map<String, dynamic>.from(result))
        : null;
  }

  Object _translate(PostgrestException e, String code) =>
      // 23505: unique (store_id, code).
      e.code == '23505' ? DuplicateDiscountCodeException(code) : e;
}
