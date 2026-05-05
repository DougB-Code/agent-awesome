/// Stores screen-scoped command metadata for the global command bar.
library;

/// CommandContext describes where a top-bar command should act.
class CommandContext {
  /// Creates immutable screen command context.
  const CommandContext({
    required this.section,
    required this.area,
    required this.text,
    this.selectedTaskId = '',
    this.selectedMemoryId = '',
    this.profilePath = '',
  });

  /// Top-level workspace section.
  final String section;

  /// Active panel or subview inside the section.
  final String area;

  /// Raw command text entered by the user.
  final String text;

  /// Selected graph backlog id, when the command is backlog-scoped.
  final String selectedTaskId;

  /// Selected memory id, when the command is memory-scoped.
  final String selectedMemoryId;

  /// Runtime profile selected for a potential new chat.
  final String profilePath;

  /// Human-readable scope label for prompts and status text.
  String get scopeLabel {
    final trimmedArea = area.trim();
    if (trimmedArea.isEmpty) {
      return section;
    }
    return '$section / $trimmedArea';
  }
}
