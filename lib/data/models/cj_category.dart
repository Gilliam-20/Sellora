/// A CJ Dropshipping category, used to filter the catalog browse screen.
///
/// CJ's raw category tree names its id/name keys differently at each depth
/// (`categoryFirstId`/`categoryFirstName`, `categorySecondId`/..., down to a
/// leaf `categoryId`/`categoryName`) — see supabase/functions/_shared/catalogSync.js's
/// `normalizeCategoryNode`, which this mirrors. Only the top level is parsed
/// here: the catalog screen shows a single filter chip row, not a 3-level
/// drill-down browser.
class CjCategory {
  CjCategory({required this.id, required this.name});

  final String id;
  final String name;

  static List<CjCategory> topLevelFromRawTree(List<dynamic> raw) {
    final out = <CjCategory>[];
    for (final node in raw) {
      final parsed = _normalize(node);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  static CjCategory? _normalize(dynamic node) {
    if (node is! Map) return null;
    String? id;
    String? name;
    for (final entry in node.entries) {
      final key = entry.key.toString().toLowerCase();
      final value = entry.value;
      if (value is List) continue; // children — unused at level 0
      if (id == null && key.endsWith('id') && value != null) {
        id = value.toString();
      }
      if (name == null && key.endsWith('name') && value != null) {
        name = value.toString();
      }
    }
    if (id == null || name == null) return null;
    return CjCategory(id: id, name: name);
  }
}
