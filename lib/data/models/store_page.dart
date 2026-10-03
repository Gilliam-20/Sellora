/// One of a storefront's own pages (TODO §20): About, Contact and the four
/// policies, written by the seller and shown at `/s/{slug}/pages/{path}`.
/// Stored in `store_pages`; buyers read `storefront_pages`.
enum StorePageKind {
  about('about', 'about', 'About us'),
  contact('contact', 'contact', 'Contact'),
  privacy('privacy', 'privacy-policy', 'Privacy policy'),
  terms('terms', 'terms-of-service', 'Terms of service'),
  shipping('shipping', 'shipping-policy', 'Shipping policy'),
  refund('refund', 'refund-policy', 'Refund policy');

  const StorePageKind(this.id, this.path, this.defaultTitle);

  /// The `kind` column.
  final String id;

  /// The URL segment.
  final String path;
  final String defaultTitle;

  bool get isPolicy => this != about && this != contact;

  static StorePageKind? parse(Object? id) =>
      values.where((k) => k.id == id).firstOrNull;

  static StorePageKind? fromPath(String? path) =>
      values.where((k) => k.path == path).firstOrNull;
}

class StorePage {
  const StorePage({
    required this.kind,
    required this.title,
    this.body = '',
    this.email,
    this.phone,
    this.isPublished = true,
    this.updatedAt,
  });

  static const maxTitle = 80;
  static const maxBody = 20000;

  final StorePageKind kind;
  final String title;

  /// Plain text; blank lines separate paragraphs.
  final String body;

  /// Contact page only.
  final String? email;
  final String? phone;

  /// An unpublished page is kept for the seller but hidden from buyers.
  final bool isPublished;
  final DateTime? updatedAt;

  static final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final phonePattern = RegExp(r'^\+?[0-9 ()-]{6,20}$');

  StorePage copyWith({
    String? title,
    String? body,
    String? email,
    String? phone,
    bool? isPublished,
    bool clearEmail = false,
    bool clearPhone = false,
  }) =>
      StorePage(
        kind: kind,
        title: title ?? this.title,
        body: body ?? this.body,
        email: clearEmail ? null : email ?? this.email,
        phone: clearPhone ? null : phone ?? this.phone,
        isPublished: isPublished ?? this.isPublished,
        updatedAt: updatedAt,
      );

  /// Why this can't be saved, or empty. Mirrors the table's checks.
  List<String> problems() => [
        if (title.trim().isEmpty) 'Give the page a title.',
        if (title.length > maxTitle)
          'Keep the title under $maxTitle characters.',
        if (body.length > maxBody) 'Keep the page under $maxBody characters.',
        if (kind != StorePageKind.contact && body.trim().isEmpty)
          'Write something for this page.',
        if (isPublished && StorePageTemplates.hasBlanks(body))
          'Fill in or remove the [bracketed] parts, or save it unpublished.',
        if (email != null && !emailPattern.hasMatch(email!))
          'That email address doesn\'t look right.',
        if (phone != null && !phonePattern.hasMatch(phone!))
          'Use a phone number like +254 711 000000.',
        if (kind == StorePageKind.contact &&
            email == null &&
            phone == null &&
            body.trim().isEmpty)
          'Add an email, a phone number or a message.',
      ];

  /// The body split into paragraphs.
  List<String> get paragraphs => body
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  /// [phone] as a WhatsApp link, digits only.
  Uri? get whatsappUri {
    final digits = phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    return digits.length < 6 ? null : Uri.parse('https://wa.me/$digits');
  }

  /// Null for a row whose kind this app doesn't know.
  static StorePage? tryFromMap(Map<String, dynamic> map) {
    final kind = StorePageKind.parse(map['kind']);
    if (kind == null) return null;
    String? opt(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    return StorePage(
      kind: kind,
      title: map['title'] as String? ?? kind.defaultTitle,
      body: map['body'] as String? ?? '',
      email: opt(map['email']),
      phone: opt(map['phone']),
      isPublished: map['isPublished'] != false,
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? ''),
    );
  }

  /// The writable columns, camelCase (see `toRow`).
  Map<String, dynamic> toMap() => {
        'kind': kind.id,
        'title': title.trim(),
        'body': body,
        'email': kind == StorePageKind.contact ? email : null,
        'phone': kind == StorePageKind.contact ? phone : null,
        'isPublished': isPublished,
      };
}

/// Starting points for the seller's pages. They are drafts for the seller
/// to read and complete, never published on their behalf: the bracketed
/// parts are theirs to fill in, and none of it is legal advice.
class StorePageTemplates {
  StorePageTemplates._();

  static StorePage of(StorePageKind kind, String storeName) => StorePage(
        kind: kind,
        title: kind.defaultTitle,
        body: _body(kind, storeName),
      );

  static String _body(StorePageKind kind, String store) => switch (kind) {
        StorePageKind.about => '$store is [what you sell, and who for].\n\n'
            '[How you started, and what you care about when you choose '
            'products.]',
        StorePageKind.contact =>
          'Questions about an order or a product? Get in touch and we\'ll '
              'reply within [1–2 working days].',
        StorePageKind.privacy =>
          'This policy explains what $store collects when you shop with us '
              'and how it\'s used.\n\n'
              'What we collect: your name, email address, phone number and '
              'delivery address, and the details of your orders.\n\n'
              'Why: to process and deliver your orders, contact you about '
              'them, and, if you signed up, send you our newsletter.\n\n'
              'Who we share it with: our store platform (Sellora), our payment '
              'provider, and the supplier and couriers who ship your order, '
              'only as far as each needs it. We don\'t sell your information.\n\n'
              'Payments: card and mobile money payments are handled by our '
              'payment provider. We never see or store your full card number.\n\n'
              'Your choices: you can ask us for a copy of your information, '
              'ask us to correct it, or delete your account at any time from '
              'your account page.\n\n'
              'Contact: [your email address].',
        StorePageKind.terms => 'These terms apply when you buy from $store.\n\n'
            'Orders: an order is confirmed once payment is received. We may '
            'cancel an order and refund you in full if an item becomes '
            'unavailable.\n\n'
            'Prices: prices are shown in your chosen currency and charged in '
            'the store\'s currency. Shipping is shown at checkout.\n\n'
            'Delivery and returns: see our Shipping policy and Refund '
            'policy.\n\n'
            'Contact: [your email address].',
        StorePageKind.shipping =>
          'Orders are prepared within [1–3] working days of payment and '
              'shipped from our supplier\'s warehouse.\n\n'
              'Delivery usually takes [7–20] working days, depending on the '
              'shipping method you choose at checkout and your location.\n\n'
              'Shipping costs are calculated at checkout. You\'ll receive a '
              'tracking number once your order ships.\n\n'
              'We ship to: [the countries you ship to].',
        StorePageKind.refund =>
          'If an item arrives damaged, faulty or not as described, contact us '
              'within [14] days of delivery with your order number and a '
              'photo.\n\n'
              'We\'ll offer a replacement or a refund to your original payment '
              'method. Refunds are processed within [5–10] working days of '
              'approval.\n\n'
              '[Whether you accept returns for change of mind, and who pays '
              'return shipping.]',
      };

  /// Whether [body] still has a template's blanks in it.
  static bool hasBlanks(String body) => RegExp(r'\[[^\]]+\]').hasMatch(body);
}
