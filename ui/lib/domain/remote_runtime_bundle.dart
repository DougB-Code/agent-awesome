/// Describes generated remote Docker runtime bundle artifacts.
library;

/// RemoteRuntimeDockerBundle stores paths and commands for one Docker bundle.
class RemoteRuntimeDockerBundle {
  /// Creates immutable metadata for a generated remote runtime bundle.
  const RemoteRuntimeDockerBundle({
    required this.rootPath,
    required this.dockerfilePath,
    required this.runtimeProfilePath,
    required this.buildScriptPath,
    required this.runScriptPath,
    required this.remoteDeployScriptPath,
    required this.imageTag,
    required this.buildCommand,
    required this.runCommand,
    required this.remoteDeployCommand,
    this.localModelPath = '',
    this.remoteModelPath = '',
    this.localModelServerExecutablePath = '',
    this.remoteModelServerExecutablePath = '',
  });

  /// Directory containing generated bundle artifacts.
  final String rootPath;

  /// Dockerfile path that builds the configured remote runtime image.
  final String dockerfilePath;

  /// Desktop UI runtime topology path for the generated remote gateway.
  final String runtimeProfilePath;

  /// Shell script that builds the Docker image from the workspace root.
  final String buildScriptPath;

  /// Shell script that starts the Docker image on the current host.
  final String runScriptPath;

  /// Shell script that transfers the image and starts it on a remote Docker host.
  final String remoteDeployScriptPath;

  /// Docker image tag produced by the build command.
  final String imageTag;

  /// Command line that builds the image from the workspace root.
  final List<String> buildCommand;

  /// Command line that starts the built image locally or on a server.
  final List<String> runCommand;

  /// Command line that runs the generated remote deploy script.
  final List<String> remoteDeployCommand;

  /// Optional local Gemma model path mounted or copied for Docker runtime use.
  final String localModelPath;

  /// Optional model path used inside the container.
  final String remoteModelPath;

  /// Optional local llama.cpp server executable copied into the Docker image.
  final String localModelServerExecutablePath;

  /// Optional llama.cpp server executable path used inside the container.
  final String remoteModelServerExecutablePath;
}
