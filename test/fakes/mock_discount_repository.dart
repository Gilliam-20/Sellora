import 'package:get/get.dart';
import 'package:sellora/data/models/discount_model.dart';
import 'package:sellora/data/repositories/discount_repository.dart';

/// In-memory [DiscountRepository]: unique codes per store, and a code with
/// recorded uses can't be deleted — the two refusals the real table makes.
class MockDiscountRepository extends GetxService implements DiscountRepository {
  final List<DiscountModel> _discounts = [];

  /// Live orders per discount id; tests set this directly.
  final Map<String, int> uses = {};
  var _nextId = 1;

  @override
  Future<List<DiscountModel>> storeDiscounts(String storeId) async =>
      _discounts.where((d) => d.storeId == storeId).toList().reversed.toList();

  @override
  Future<Map<String, int>> usage(String storeId) async => {
        for (final d in _discounts.where((d) => d.storeId == storeId))
          d.id: uses[d.id] ?? 0,
      };

  @override
  Future<DiscountModel> createDiscount(DiscountModel discount) async {
    _refuseDuplicate(discount);
    final created =
        DiscountModel.fromMap({...discount.toMap(), 'id': 'd${_nextId++}'});
    _discounts.add(created);
    return created;
  }

  @override
  Future<void> updateDiscount(DiscountModel discount) async {
    _refuseDuplicate(discount);
    final index = _discounts.indexWhere((d) => d.id == discount.id);
    if (index >= 0) _discounts[index] = discount;
  }

  @override
  Future<void> deleteDiscount(String discountId) async {
    if ((uses[discountId] ?? 0) > 0) throw const DiscountInUseException();
    _discounts.removeWhere((d) => d.id == discountId);
  }

  @override
  Future<DiscountModel?> lookup(String storeId, String code) async {
    final now = DateTime.now();
    for (final d in _discounts) {
      if (d.storeId == storeId &&
          d.code == DiscountModel.normalizeCode(code) &&
          d.isLiveAt(now) &&
          (d.usageLimit == null || (uses[d.id] ?? 0) < d.usageLimit!)) {
        return d;
      }
    }
    return null;
  }

  void _refuseDuplicate(DiscountModel discount) {
    if (_discounts.any((d) =>
        d.storeId == discount.storeId &&
        d.code == discount.code &&
        d.id != discount.id)) {
      throw DuplicateDiscountCodeException(discount.code);
    }
  }
}
