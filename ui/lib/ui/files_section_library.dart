/// File library list, filters, cards, badges, and empty state.
part of 'files_section.dart';

/// _FilesLibraryContent renders the searchable file list.
class _FilesLibraryContent extends StatelessWidget {
  /// Creates the library content for indexed files.
  const _FilesLibraryContent({
    required this.files,
    required this.query,
    required this.selectedFileId,
    required this.kindFilter,
    required this.onSelected,
  });

  /// All file records known to the section.
  final List<_AgentFileItem> files;

  /// Fuzzy search query from the command subshell.
  final String query;

  /// Currently selected file id.
  final String? selectedFileId;

  /// Active type filter.
  final _FileKindFilter kindFilter;

  /// Selects a file card.
  final ValueChanged<String> onSelected;

  /// Builds the file library body.
  @override
  Widget build(BuildContext context) {
    final visibleFiles = _filteredFiles(files, query, kindFilter);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: visibleFiles.isEmpty
                ? _FilesEmptyState(hasAnyFile: files.isNotEmpty)
                : ListView.separated(
                    itemCount: visibleFiles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final file = visibleFiles[index];
                      return _AgentFileCard(
                        file: file,
                        selected: file.id == selectedFileId,
                        onTap: () => onSelected(file.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// _AgentFileCard renders one selectable file record.
class _AgentFileCard extends StatelessWidget {
  /// Creates one file card.
  const _AgentFileCard({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  /// File item to render.
  final _AgentFileItem file;

  /// Whether this card is selected.
  final bool selected;

  /// Selects this file.
  final VoidCallback onTap;

  /// Builds the file record with file-specific metadata only.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accent = _fileKindAccent(context, file.kind);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? colors.panelStrong : colors.surface,
          border: Border.all(
            color: selected ? colors.borderStrong : colors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: ColoredBox(color: accent, child: const SizedBox(width: 3)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _FileIconBox(icon: file.kind.icon, color: accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              file.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              file.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _FileTypeBadge(label: file.kind.label, color: accent),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _FileMetadataBadge(
                        icon: Icons.insert_drive_file_outlined,
                        label: file.mediaLabel,
                      ),
                      if (file.pathLabel.isNotEmpty)
                        _FileMetadataBadge(
                          icon: Icons.folder_outlined,
                          label: file.pathLabel,
                        ),
                      if (file.sourceLabel.isNotEmpty)
                        _FileMetadataBadge(
                          icon: Icons.link_outlined,
                          label: file.sourceLabel,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// _FileIconBox renders a compact icon tile.
class _FileIconBox extends StatelessWidget {
  /// Creates an icon box.
  const _FileIconBox({required this.icon, required this.color});

  /// Icon shown in the tile.
  final IconData icon;

  /// Accent color for the icon.
  final Color color;

  /// Builds a small themed icon tile.
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      width: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.agentAwesomeIsDark ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(PanelStyleTokens.radius),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// _FileTypeBadge renders a file category badge.
class _FileTypeBadge extends StatelessWidget {
  /// Creates a type badge.
  const _FileTypeBadge({required this.label, required this.color});

  /// Badge label.
  final String label;

  /// Badge accent color.
  final Color color;

  /// Builds the category badge.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: context.agentAwesomeColors.panel,
        border: Border.all(color: context.agentAwesomeColors.border),
        borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.agentAwesomeColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// _FileMetadataBadge renders compact supporting file metadata.
class _FileMetadataBadge extends StatelessWidget {
  /// Creates a metadata badge.
  const _FileMetadataBadge({required this.icon, required this.label});

  /// Metadata icon.
  final IconData icon;

  /// Metadata label.
  final String label;

  /// Builds one metadata badge.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: colors.muted),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesEmptyState extends StatelessWidget {
  /// Creates the file empty state.
  const _FilesEmptyState({required this.hasAnyFile});

  /// Whether files exist before filtering.
  final bool hasAnyFile;

  /// Builds the empty state with a clear file-only message.
  @override
  Widget build(BuildContext context) {
    final title = hasAnyFile ? 'No matching files' : 'No files indexed yet';
    final message = hasAnyFile
        ? 'Try a different file type or search.'
        : 'Files for your agent. Add PDFs, spreadsheets, images, and other files here. Chat messages belong in Memory, not Files.';
    return PanelGuidedEmptyBlock(
      icon: Icons.folder_outlined,
      title: title,
      message: message,
    );
  }
}
