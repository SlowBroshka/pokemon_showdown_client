import 'format_availability.dart';
import 'format_catalog.dart';
import 'format_catalog_kind.dart';

/// Pure allowlist policy. `experimental` does not mean fully playable or rated.
FormatAvailability formatAvailability(
  FormatCatalog? catalog, {
  required String formatId,
  required bool fresh,
  bool experimentalEnabled = false,
}) {
  if (!fresh || catalog == null) return FormatAvailability.staleCatalog;
  switch (catalog.kind) {
    case FormatCatalogKind.malformed:
      return FormatAvailability.malformedCatalog;
    case FormatCatalogKind.legacyUnsupported:
      return FormatAvailability.legacyCatalog;
    case FormatCatalogKind.valid:
      break;
  }
  final format = catalog.formats[formatId];
  if (format == null) return FormatAvailability.notAdvertised;
  if (formatId != 'gen9randombattle') {
    return FormatAvailability.unsupportedFormat;
  }
  if (format.unsupported) return FormatAvailability.unsupportedFlags;
  if (!format.searchShow) return FormatAvailability.searchDisabled;
  if (!format.preset) return FormatAvailability.teamRequired;
  if (!experimentalEnabled) return FormatAvailability.experimentalDisabled;
  return FormatAvailability.experimental;
}
