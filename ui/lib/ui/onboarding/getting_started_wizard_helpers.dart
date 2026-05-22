/// First-run setup external-link and recommendation helpers.
part of 'getting_started_wizard.dart';

Future<void> _openModelSite(
  BuildContext context,
  LocalModelDescriptor model,
) async {
  final url = Uri.parse('https://huggingface.co/${model.repository}');
  final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (opened || !context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Could not open ${url.toString()}')));
}

/// Formats byte counts for setup disclosure text.
String _formatBytes(int bytes) {
  const gib = 1024 * 1024 * 1024;
  const mib = 1024 * 1024;
  if (bytes >= gib) {
    return '${(bytes / gib).toStringAsFixed(1)} GB';
  }
  if (bytes >= mib) {
    return '${(bytes / mib).toStringAsFixed(0)} MB';
  }
  return '$bytes bytes';
}

/// Returns source metadata text for one local model setup option.
String _localModelSourceLabel(LocalModelDescriptor descriptor) {
  if (descriptor.usesManagedDownload) {
    return '${descriptor.fileName} (${_formatBytes(descriptor.expectedBytes)})';
  }
  if (descriptor.hfRepo.trim().isNotEmpty) {
    return descriptor.hfRepo;
  }
  return descriptor.repository;
}

/// Formats optional byte counts for system-check cards.
String _formatOptionalBytes(int? bytes) {
  if (bytes == null) {
    return 'Unknown';
  }
  return _formatBytes(bytes);
}

/// Formats CPU thread counts for system-check cards.
String _formatCpuThreads(int cpuThreads) {
  if (cpuThreads <= 0) {
    return 'Unknown';
  }
  return '$cpuThreads cores';
}

/// Returns a local model memory recommendation for the detected system.
String _memoryRecommendation(int? bytes) {
  if (bytes == null) {
    return 'Could not detect memory';
  }
  const eightGiB = 8 * 1024 * 1024 * 1024;
  const sixteenGiB = 16 * 1024 * 1024 * 1024;
  if (bytes < eightGiB) {
    return 'Use cloud or a smaller model';
  }
  if (bytes < sixteenGiB) {
    return 'Gemma 4 E2B should fit';
  }
  return 'Enough for local models';
}

/// Returns a model storage recommendation for the detected app data volume.
String _diskRecommendation(int? bytes) {
  if (bytes == null) {
    return 'Could not detect disk space';
  }
  final modelBytes = gemma4E2BLocalModel.expectedBytes;
  if (bytes < modelBytes * 2) {
    return 'Free space before download';
  }
  return 'Enough for Gemma 4 E2B';
}
