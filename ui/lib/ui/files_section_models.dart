/// Private file workspace view models and filter enums.
part of 'files_section.dart';

/// _AgentFileItem is the file-only UI model derived from memory records.
class _AgentFileItem {
  /// Creates a managed file item for the Files section.
  const _AgentFileItem({
    required this.id,
    required this.memoryId,
    required this.evidenceId,
    required this.title,
    required this.summary,
    required this.kind,
    required this.mediaLabel,
    required this.pathLabel,
    required this.checksumLabel,
    required this.sourceLabel,
    required this.sourceSystem,
    required this.sourceId,
    required this.firewall,
    required this.sensitivity,
    required this.trustLevel,
    required this.status,
    required this.topics,
    required this.record,
  });

  /// Stable file id.
  final String id;

  /// Backing memory id.
  final String memoryId;

  /// Raw source record id.
  final String evidenceId;

  /// Display title.
  final String title;

  /// Short summary.
  final String summary;

  /// File category.
  final _AgentFileKind kind;

  /// Media type or extension display label.
  final String mediaLabel;

  /// File path or source location label.
  final String pathLabel;

  /// Raw checksum label.
  final String checksumLabel;

  /// Source display label.
  final String sourceLabel;

  /// Source system.
  final String sourceSystem;

  /// Source id.
  final String sourceId;

  /// Memory firewall.
  final String firewall;

  /// Sensitivity label.
  final String sensitivity;

  /// Trust label.
  final String trustLevel;

  /// Lifecycle status.
  final String status;

  /// Topic labels.
  final List<String> topics;

  /// Backing memory record for controller actions.
  final MemoryRecord record;
}

/// _AgentFileKind describes the supported managed file categories.
enum _AgentFileKind {
  /// PDF and document-like source material.
  document('Document', Icons.description_outlined),

  /// Spreadsheet source material.
  spreadsheet('Spreadsheet', Icons.table_chart_outlined),

  /// Image source material.
  image('Image', Icons.image_outlined),

  /// Presentation source material.
  presentation('Presentation', Icons.slideshow_outlined),

  /// Archive or binary bundle source material.
  archive('Archive', Icons.inventory_2_outlined),

  /// Other file-like source material.
  other('File', Icons.insert_drive_file_outlined);

  /// Creates a file category.
  const _AgentFileKind(this.label, this.icon);

  /// Display label.
  final String label;

  /// Display icon.
  final IconData icon;
}

/// _FileKindFilter describes the file type filters shown in the library.
enum _FileKindFilter {
  /// All indexed files.
  all('All files', Icons.folder_open_outlined),

  /// Documents and PDFs.
  documents('Documents', Icons.description_outlined),

  /// Spreadsheets.
  spreadsheets('Sheets', Icons.table_chart_outlined),

  /// Images.
  images('Images', Icons.image_outlined),

  /// Other file types.
  other('Other', Icons.insert_drive_file_outlined);

  /// Creates a file filter.
  const _FileKindFilter(this.label, this.icon);

  /// Display label.
  final String label;

  /// Display icon.
  final IconData icon;
}
