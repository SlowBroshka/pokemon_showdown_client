import '../../matchmaking/formats/format_catalog.dart';
import '../server_event.dart';

/// Also emitted for malformed global catalogs, so consumers revoke old data.
final class FormatsEvent extends ServerEvent {
  const FormatsEvent(super.record, {required this.catalog});
  final FormatCatalog catalog;
}
