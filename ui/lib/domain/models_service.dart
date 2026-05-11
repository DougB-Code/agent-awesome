/// Service availability data models shared by app state and widgets.
part of 'models.dart';

/// ConnectionStateKind describes service availability for the shell.
enum ConnectionStateKind {
  /// The service has not been checked yet.
  unknown,

  /// The service responded successfully.
  connected,

  /// The service failed or timed out.
  disconnected,
}
