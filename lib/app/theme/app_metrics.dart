/// Spacing and radius tokens.
///
/// Radii are deliberately NOT uniform across the app — a generic "one
/// border-radius for every card" is one of the clearest templated-AI
/// tells. Sellora uses three distinct treatments:
///   - `card`      : soft, rounded — product & content cards buyers browse.
///   - `stub`      : barely-rounded with a flat left edge — manifest/order
///                   stub cards, evoking a cargo tag rather than a SaaS card.
///   - `control`   : pill-shaped — buttons, chips, inputs.
library;

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppRadii {
  AppRadii._();

  static const double card = 18;
  static const double stub = 6;
  static const double control = 100; // pill
  static const double sheet = 28;
}
