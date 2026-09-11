/// THE MERIDIAN PALETTE
/// ---------------------------------------------------------------------
/// Sellora sits between two worlds: a global shipping network (CJ
/// Dropshipping's supply lines) and a local marketplace hustle (sellers
/// in Nairobi, Lagos, London or Austin building a storefront). The
/// palette is named after lines of longitude — the "meridians" that
/// tie a global supply chain together.
///
/// Cargo Navy anchors trust and logistics. Manifest Gold is the
/// entrepreneurial spark — every seller CTA, every "list this product"
/// moment. Horizon Teal belongs to the buyer side: confirmations,
/// shipped orders, the feeling of a purchase in motion. The neutrals
/// (Ink / Mist / Slate) are deliberately cool, not the warm cream that
/// generic AI-generated products default to.
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ---- Brand ----------------------------------------------------------
  static const Color cargoNavy = Color(0xFF303F9F);
  static const Color cargoNavyDeep = Color(0xFF1A237E);
  static const Color manifestGold = Color(0xFFFFC107);
  static const Color manifestGoldDeep = Color(0xFFFFA000);
  static const Color horizonTeal = Color(0xFF2EC4B6);
  static const Color horizonTealDeep = Color(0xFF1F9E92);

  // ---- Neutrals ---------------------------------------------------------
  static const Color ink = Color(0xFF14161F);
  static const Color slate = Color(0xFF7A8194);
  static const Color slateLight = Color(0xFFB7BCC8);
  static const Color mist = Color(0xFFF1F3F2);
  static const Color cloud = Color(0xFFFCFCFB);
  static const Color hairline = Color(0xFFE2E5E4);

  // ---- Semantic ---------------------------------------------------------
  static const Color success = horizonTeal;
  static const Color warning = manifestGold;
  static const Color danger = Color(0xFFE0553F);
  static const Color info = Color(0xFF4E7FCC);

  // ---- Role accents (used to color-code the three portals) --------------
  static const Color buyerAccent = horizonTeal;
  static const Color sellerAccent = manifestGold;
  static const Color adminAccent = Color(0xFF8C6FE0);

  /// Order/shipment status colors — used on manifest-stub cards.
  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return manifestGold;
      case 'processing':
        return info;
      case 'shipped':
        return horizonTeal;
      case 'delivered':
        return const Color(0xFF3FAE5C);
      case 'cancelled':
      case 'canceled':
      case 'failed':
        return danger;
      default:
        return slate;
    }
  }
}
