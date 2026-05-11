/// Defines local system capability data used by first-run setup.
library;

/// SystemCapabilitySnapshot stores hardware and storage facts for setup.
class SystemCapabilitySnapshot {
  /// Creates an immutable system capability snapshot.
  const SystemCapabilitySnapshot({
    required this.cpuThreads,
    required this.memoryBytes,
    required this.diskBytes,
  });

  /// Creates a placeholder snapshot before app probes complete.
  const SystemCapabilitySnapshot.unknown()
    : cpuThreads = 0,
      memoryBytes = null,
      diskBytes = null;

  /// Detected logical CPU thread count.
  final int cpuThreads;

  /// Total physical memory in bytes, when detectable.
  final int? memoryBytes;

  /// Available model-data disk space in bytes, when detectable.
  final int? diskBytes;
}
