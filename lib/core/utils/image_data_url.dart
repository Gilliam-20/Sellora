import 'dart:convert';
import 'dart:typed_data';

/// Helpers for store branding images. A picked photo is uploaded to the
/// `store-media` Storage bucket (`StoreRepository.uploadStoreImage`) and the
/// store keeps its public URL. Stores branded before that (2026-09-20 to
/// 2026-09-27) still hold inline `data:` URIs in `logoUrl`/`bannerUrl`,
/// which [isDataUrl]/[decodeDataUrl] keep rendering until re-uploaded.

/// Matches the bucket's `file_size_limit`
/// (supabase/migrations/20260927000200_storage.sql).
const maxPickedImageBytes = 2 * 1024 * 1024;

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
