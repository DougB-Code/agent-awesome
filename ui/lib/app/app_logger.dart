/// Writes timestamped Agent Awesome UI diagnostics to the local UI log file.
library;

import 'dart:io';

import '../clients/client_logger.dart';

/// AppLogger appends UI and client diagnostics to ui.log.
class AppLogger implements ClientLogger {
  /// Creates a file-backed app logger.
  const AppLogger({required this.directory});

  /// Directory where log files are written.
  final String directory;

  /// Writes a timestamped log line to the UI log.
  @override
  Future<void> write(String source, String message) async {
    await Directory(directory).create(recursive: true);
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] [$source] $message\n';
    await File(
      '$directory/ui.log',
    ).writeAsString(line, mode: FileMode.append, flush: true);
  }
}
