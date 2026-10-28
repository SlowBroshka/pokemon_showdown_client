import 'format_catalog.dart';
import 'format_catalog_kind.dart';
import 'showdown_format.dart';

final _hex = RegExp(r'^[0-9a-fA-F]+$');
final _column = RegExp(r'^,[0-9]+$');
final _controls = RegExp(r'[\x00-\x1f\x7f]');
final _nonId = RegExp(r'[^a-z0-9]');

/// Decodes only the payload after `formats|`, not a WebSocket envelope.
/// Legacy syntax is identifiable but never enables search in this version.
FormatCatalog decodeFormatCatalog(String data) {
  FormatCatalog invalid() => FormatCatalog(kind: FormatCatalogKind.malformed);
  if (_controls.hasMatch(data)) return invalid();
  final entries = data.isEmpty ? <String>[] : data.split('|');
  final formats = <String, ShowdownFormat>{};
  var section = '';
  var column = 0;
  var localLadder = false;
  var legacy = false;
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    if (entry == ',LL') {
      if (localLadder) return invalid();
      localLadder = true;
      continue;
    }
    if (entry.isEmpty || _column.hasMatch(entry)) {
      if (entry.isNotEmpty) {
        final parsed = int.tryParse(entry.substring(1));
        if (parsed == null || parsed > 0x7fffffff) return invalid();
        column = parsed;
      }
      if (++index >= entries.length) return invalid();
      section = entries[index];
      if (section.trim().isEmpty || section.startsWith(',')) return invalid();
      continue;
    }
    if (entry.startsWith(',')) return invalid();
    var name = entry;
    BigInt? flags;
    final comma = entry.lastIndexOf(',');
    if (comma >= 0 && _hex.hasMatch(entry.substring(comma + 1))) {
      name = entry.substring(0, comma);
      flags = BigInt.parse(entry.substring(comma + 1), radix: 16);
    } else {
      // Known legacy suffixes may be combined (search-only + preset).
      if (name.endsWith(',#')) name = name.substring(0, name.length - 2);
      if (name.endsWith(',,')) {
        name = name.substring(0, name.length - 2);
      } else if (name.endsWith(',')) {
        name = name.substring(0, name.length - 1);
      }
      // A remaining comma is neither a supported hex suffix nor legacy syntax.
      if (name.contains(',')) return invalid();
      legacy = true;
    }
    final id = name.toLowerCase().replaceAll(_nonId, '');
    if (id.isEmpty || formats.containsKey(id)) return invalid();
    formats[id] = ShowdownFormat(
      id: id,
      name: name,
      section: section,
      column: column,
      flags: flags,
    );
  }
  return FormatCatalog(
    kind: legacy
        ? FormatCatalogKind.legacyUnsupported
        : FormatCatalogKind.valid,
    formats: formats,
    localLadder: localLadder,
  );
}
