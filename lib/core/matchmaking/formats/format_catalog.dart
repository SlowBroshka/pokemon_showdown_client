import 'format_catalog_kind.dart';
import 'showdown_format.dart';

/// A complete replacement snapshot, including rejected updates.
final class FormatCatalog {
  FormatCatalog({
    required this.kind,
    Map<String, ShowdownFormat> formats = const {},
    this.localLadder = false,
  }) : formats = Map.unmodifiable(formats);

  final FormatCatalogKind kind;
  final Map<String, ShowdownFormat> formats;
  final bool localLadder;
}
