import 'transport_status.dart';

/// One ordered notification: either a complete message or a lifecycle change.
final class TransportUpdate {
  const TransportUpdate.message(String value) : message = value, status = null;
  const TransportUpdate.status(TransportStatus value)
    : status = value,
      message = null;

  final String? message;
  final TransportStatus? status;
}
