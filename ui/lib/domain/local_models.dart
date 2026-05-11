/// Defines local model artifact and installation data.
library;

/// LocalModelDescriptor describes one downloadable LiteRT-LM model artifact.
class LocalModelDescriptor {
  /// Creates immutable metadata for a locally managed model.
  const LocalModelDescriptor({
    required this.id,
    required this.displayName,
    required this.modelName,
    required this.repository,
    required this.revision,
    required this.fileName,
    required this.downloadUrl,
    required this.expectedBytes,
    required this.expectedSha256,
    required this.license,
  });

  /// Stable Agent Awesome model id.
  final String id;

  /// User-facing model name.
  final String displayName;

  /// Model name sent through the OpenAI-compatible runtime API.
  final String modelName;

  /// Source Hugging Face repository.
  final String repository;

  /// Pinned source repository revision.
  final String revision;

  /// Artifact filename inside the repository.
  final String fileName;

  /// Pinned artifact download URL.
  final String downloadUrl;

  /// Expected artifact size in bytes.
  final int expectedBytes;

  /// Expected SHA-256 digest for the artifact.
  final String expectedSha256;

  /// Source model license label.
  final String license;
}

/// LocalModelInstall stores the installed file paths for a model.
class LocalModelInstall {
  /// Creates an immutable installed model record.
  const LocalModelInstall({
    required this.model,
    required this.directory,
    required this.modelPath,
    required this.manifestPath,
  });

  /// Model metadata.
  final LocalModelDescriptor model;

  /// Directory that owns the model artifact and manifest.
  final String directory;

  /// Installed LiteRT-LM artifact path.
  final String modelPath;

  /// Installation manifest path.
  final String manifestPath;
}

/// LocalModelInstallProgress reports model download and verification progress.
class LocalModelInstallProgress {
  /// Creates a progress update for the local model setup UI.
  const LocalModelInstallProgress({
    required this.phase,
    required this.message,
    this.receivedBytes = 0,
    this.totalBytes = 0,
  });

  /// Machine-friendly phase name.
  final String phase;

  /// User-facing progress message.
  final String message;

  /// Bytes received so far.
  final int receivedBytes;

  /// Expected total bytes, when known.
  final int totalBytes;

  /// Fractional progress when the total byte count is available.
  double? get fraction {
    if (totalBytes <= 0) {
      return null;
    }
    return receivedBytes.clamp(0, totalBytes) / totalBytes;
  }
}
