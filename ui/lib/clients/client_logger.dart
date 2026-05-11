/// Defines logging contracts for transport clients.
library;

/// ClientLogger records diagnostic messages without coupling clients to app UI.
abstract class ClientLogger {
  /// Writes one diagnostic message for a named client source.
  Future<void> write(String source, String message);
}
