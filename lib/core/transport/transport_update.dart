import 'transport_status.dart';

/// One ordered notification: either a complete message or a lifecycle change.
final class TransportUpdate {
  const TransportUpdate.message(String value, {this.sequence = 0})
    : message = value,
      status = null;
  const TransportUpdate.status(TransportStatus value, {this.sequence = 0})
    : status = value,
      message = null;

  final String? message;
  final TransportStatus? status;
  final int sequence;
}
