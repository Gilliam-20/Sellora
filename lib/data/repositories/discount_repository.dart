import '../models/discount_model.dart';

/// A store's discount codes. RLS lets only the store's owner (and admin)
/// read or write them; buyers can only look one up by its code.
abstract class DiscountRepository {
  /// Every code of [storeId], newest first.
  Future<List<DiscountModel>> storeDiscounts(String storeId);

  /// How many live (not cancelled) orders used each of [storeId]'s codes,
  /// by discount id.
  Future<Map<String, int>> usage(String storeId);

  Future<DiscountModel> createDiscount(DiscountModel discount);

  Future<void> updateDiscount(DiscountModel discount);

  /// Throws [DiscountInUseException] when an order already used the code;
  /// the seller deactivates it instead.
  Future<void> deleteDiscount(String discountId);

  /// Checkout's preview of a code: its terms if it's usable in [storeId]
  /// right now, else null. `createOrder` re-checks everything.
  Future<DiscountModel?> lookup(String storeId, String code);
}

class DiscountInUseException implements Exception {
  const DiscountInUseException();

  @override
  String toString() =>
      'This code has already been used, so it can\'t be deleted. '
      'Turn it off instead.';
}

/// Another of the seller's codes already has this name.
class DuplicateDiscountCodeException implements Exception {
  const DuplicateDiscountCodeException(this.code);

  final String code;

  @override
  String toString() => 'You already have a code called $code.';
}
