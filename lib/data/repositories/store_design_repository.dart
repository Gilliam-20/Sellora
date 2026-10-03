import '../models/store_design.dart';

/// A store's design as its owner sees it in the builder.
class StoreDesignRecord {
  const StoreDesignRecord({
    required this.draft,
    this.published,
    this.publishedAt,
    this.publishedVersion = 0,
    this.draftUpdatedAt,
  });

  final StoreDesign draft;
  final StoreDesign? published;
  final DateTime? publishedAt;
  final int publishedVersion;
  final DateTime? draftUpdatedAt;
}

class NewsletterSubscriber {
  const NewsletterSubscriber(
      {required this.id, required this.email, required this.createdAt});
  final int id;
  final String email;
  final DateTime createdAt;
}

/// Store designs (TODO §18) and the newsletter list their newsletter
/// section collects.
abstract class StoreDesignRepository {
  /// What buyers see: the store's published design, or null if it never
  /// published one (the storefront then uses `StoreDesign.starter`) or the
  /// store isn't open.
  Future<StoreDesign?> publishedDesign(String storeId);

  /// The owner's draft and published copy, or null if nothing was saved.
  Future<StoreDesignRecord?> loadForOwner(String storeId);

  Future<void> saveDraft(String storeId, StoreDesign draft);

  /// Publishes the saved draft. Returns the new published version.
  Future<int> publish(String storeId);

  /// A visitor's sign-up. Signing up twice is a quiet no-op.
  Future<void> subscribeToNewsletter(String storeId, String email);

  /// Newest first.
  Future<List<NewsletterSubscriber>> subscribers(String storeId);

  Future<void> removeSubscriber(int id);
}
