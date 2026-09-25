import 'dart:convert';
import 'dart:typed_data';

/// Encodes picked image bytes as a `data:` URI so a locally-picked photo can
/// be stored in the same `String` fields (`StoreModel.logoUrl`/`bannerUrl`)
/// that already hold hosted URLs — no Supabase Storage upload step exists
/// yet (see pubspec.yaml's "common next additions"), so this is what makes
/// picking an on-device photo actually work today, against both the mock and
/// Supabase-backed `StoreRepository`.
///
/// Kept small because `updateStore` writes the whole `StoreModel` in one
/// `.update()` call, and every storefront read ships these inline images.
const maxPickedImageBytes = 350 * 1024;

const _extensionMimeTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
};

String mimeTypeForPath(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
  return _extensionMimeTypes[ext] ?? 'image/jpeg';
}

String bytesToDataUrl(Uint8List bytes, String mimeType) {
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

bool isDataUrl(String value) => value.startsWith('data:');

/// Decodes a `data:<mime>;base64,<payload>` URI back to raw bytes. Returns
/// `null` for anything malformed rather than throwing, matching
/// `hexToColor`'s "bad input is just unset" convention.
Uint8List? decodeDataUrl(String value) {
  final commaIndex = value.indexOf(',');
  if (commaIndex == -1) return null;
  try {
    return base64Decode(value.substring(commaIndex + 1));
  } on FormatException {
    return null;
  }
}
