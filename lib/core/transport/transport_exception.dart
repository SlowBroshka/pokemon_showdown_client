import 'transport_failure.dart';

/// Deliberately excludes URLs, payloads and underlying exception messages.
final class TransportException implements Exception {
  const TransportException(this.failure);

  final TransportFailure failure;

  @override
  String toString() => 'TransportException(${failure.name})';
}
