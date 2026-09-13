import '../models/product_model.dart';
import '../models/store_model.dart';
import '../models/subscription_plan_model.dart';

/// Sample catalog + plans used when [AppConstants.useMockData] is true.
/// Swap this out for real CJ Dropshipping / Firestore data by flipping
/// that flag and wiring FirebaseProductRepository / CjDropshippingService.
class MockSeedData {
  MockSeedData._();

  static List<ProductModel> catalog() => [
        ProductModel(
          id: 'p1',
          cjProductId: 'CJ-88214',
          title: 'Wireless Earbuds — Active Noise Cancelling',
          imageUrl:
              'https://images.unsplash.com/photo-1590658268037-6bf12165a8df?w=600',
          costPrice: 14.20,
          sellPrice: 34.99,
          compareAtPrice: 49.99,
          category: 'Electronics',
          description:
              'Bluetooth 5.3 earbuds with active noise cancelling and a 28-hour charging case.',
          soldCount: 214,
          rating: 4.6,
          stock: 480,
          discountPercent: 30,
        ),
        ProductModel(
          id: 'p2',
          cjProductId: 'CJ-77031',
          title: 'Minimalist Stainless Steel Watch',
          imageUrl:
              'https://images.unsplash.com/photo-1524805444758-089113d48a6d?w=600',
          costPrice: 9.80,
          sellPrice: 27.50,
          category: 'Fashion',
          description:
              'Unisex minimalist watch, stainless mesh strap, water resistant to 30m.',
          soldCount: 96,
          rating: 4.4,
          stock: 260,
        ),
        ProductModel(
          id: 'p3',
          cjProductId: 'CJ-90256',
          title: 'LED Ring Light with Tripod Stand',
          imageUrl:
              'https://images.unsplash.com/photo-1616763355603-9755a640a287?w=600',
          costPrice: 11.00,
          sellPrice: 29.99,
          compareAtPrice: 39.99,
          category: 'Electronics',
          description:
              '10-inch ring light, 3 color modes, adjustable tripod up to 2.1m.',
          soldCount: 152,
          rating: 4.5,
          stock: 190,
          discountPercent: 25,
        ),
        ProductModel(
          id: 'p4',
          cjProductId: 'CJ-65123',
          title: 'Ceramic Pour-Over Coffee Set',
          imageUrl:
              'https://images.unsplash.com/photo-1621241441204-abb731a1f5b8?w=600',
          costPrice: 13.40,
          sellPrice: 32.00,
          category: 'Home',
          description:
              'Hand-glazed ceramic dripper, server and filter set for pour-over coffee.',
          soldCount: 41,
          rating: 4.8,
          stock: 75,
        ),
        ProductModel(
          id: 'p5',
          cjProductId: 'CJ-33890',
          title: 'Foldable Laptop Stand — Aluminum',
          imageUrl:
              'https://images.unsplash.com/photo-1611186871348-b1ce696e52c9?w=600',
          costPrice: 8.50,
          sellPrice: 22.99,
          category: 'Electronics',
          description:
              'Adjustable aluminum laptop stand, folds flat, fits 10–17 inch laptops.',
          soldCount: 303,
          rating: 4.7,
          stock: 410,
        ),
        ProductModel(
          id: 'p6',
          cjProductId: 'CJ-51442',
          title: 'Reusable Silicone Food Storage Bags (Set of 6)',
          imageUrl:
              'https://images.unsplash.com/photo-1610701596007-11502861dcfa?w=600',
          costPrice: 6.90,
          sellPrice: 18.50,
          compareAtPrice: 24.00,
          category: 'Home',
          description:
              'Leak-proof, freezer and microwave safe silicone bags in 3 sizes.',
          soldCount: 178,
          rating: 4.3,
          stock: 320,
          discountPercent: 20,
        ),
      ];

  /// Two distinct tenants so the store boundary is actually testable in
  /// demo mode: different sellers, different products (see
  /// MockProductRepository), separate buyers, carts and order history.
  /// `store-aminas`' sellerId matches the existing "sign in with an email
  /// containing 'seller'" quick-login shortcut in MockAuthRepository, so
  /// that shortcut now lands on a real store instead of a floating uid.
  static List<StoreModel> stores() => [
        StoreModel(
          id: 'store-aminas',
          slug: 'aminas-picks',
          sellerId: 'mock-seller',
          name: "Amina's Curated Picks",
          tagline: 'Curated home & tech finds, shipped fast.',
          primaryColorHex: '#16213E', // Cargo Navy
          currencyCode: 'KES',
          createdAt: DateTime.now().subtract(const Duration(days: 120)),
        ),
        StoreModel(
          id: 'store-jengo',
          slug: 'jengo-electronics',
          sellerId: 'mock-seller-2',
          name: 'Jengo Electronics',
          tagline: 'Everyday gadgets and accessories at honest prices.',
          primaryColorHex: '#2EC4B6', // Horizon Teal
          currencyCode: 'KES',
          createdAt: DateTime.now().subtract(const Duration(days: 45)),
        ),
      ];

  static List<SubscriptionPlanModel> plans() => [
        SubscriptionPlanModel(
          id: 'starter',
          name: 'Starter',
          priceUsd: 9.99,
          priceKes: 1300,
          billingPeriodDays: 30,
          listingLimit: 25,
          orderLimit: 50,
          storeLimit: 1,
          commissionPercent: 7,
          features: const {'customDomain': false, 'advancedAnalytics': false},
          perks: const [
            'List up to 25 products',
            'Standard catalog access',
            'Email support',
          ],
        ),
        SubscriptionPlanModel(
          id: 'growth',
          name: 'Growth',
          priceUsd: 29.99,
          priceKes: 3250,
          billingPeriodDays: 30,
          listingLimit: 200,
          orderLimit: 500,
          storeLimit: 1,
          commissionPercent: 5,
          isPopular: true,
          features: const {'customDomain': false, 'advancedAnalytics': true},
          perks: const [
            'List up to 200 products',
            'Full catalog access',
            'Priority order processing',
            'Priority support',
          ],
        ),
        SubscriptionPlanModel(
          id: 'scale',
          name: 'Scale',
          priceUsd: 79,
          priceKes: 10300,
          billingPeriodDays: 30,
          listingLimit: -1,
          orderLimit: -1,
          storeLimit: 1,
          commissionPercent: 3,
          features: const {'customDomain': true, 'advancedAnalytics': true},
          perks: const [
            'Unlimited listings',
            'Full catalog access',
            'Lowest commission rate',
            'Dedicated support line',
          ],
        ),
      ];
}
