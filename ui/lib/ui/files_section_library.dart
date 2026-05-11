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
    required this.onKindFilterChanged,
    required this.onSelected,
    required this.onAddFile,
  });

  /// All file records known to the section.
  final List<_AgentFileItem> files;

  /// Fuzzy search query from the command subshell.
  final String query;

  /// Currently selected file id.
  final String? selectedFileId;

  /// Active type filter.
  final _FileKindFilter kindFilter;

  /// Changes the active type filter.
  final ValueChanged<_FileKindFilter> onKindFilterChanged;

  /// Selects a file card.
  final ValueChanged<String> onSelected;

  /// Opens the add-file affordance.
  final VoidCallback onAddFile;

  /// Builds the file library body.
  @override
  Widget build(BuildContext context) {
    final visibleFiles = _filteredFiles(files, query, kindFilter);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _FilesSummaryStrip(files: files),
          const SizedBox(height: 14),
          _FileKindFilterBar(
            selected: kindFilter,
            files: files,
            onSelected: onKindFilterChanged,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: visibleFiles.isEmpty
                ? _FilesEmptyState(
                    hasAnyFile: files.isNotEmpty,
                    onAddFile: onAddFile,
                  )
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

/// _FilesSummaryStrip renders high-level file inventory counts.
class _FilesSummaryStrip extends StatelessWidget {
  /// Creates the file summary strip.
  const _FilesSummaryStrip({required this.files});

  /// File inventory to summarize.
  final List<_AgentFileItem> files;

  /// Builds responsive inventory cards.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final cards = <Widget>[
          _FileMetricCard(
            label: 'Files',
            value: files.length.toString(),
            icon: Icons.folder_open_outlined,
            accent: context.agentAwesomeColors.green,
          ),
          _FileMetricCard(
            label: 'Documents',
            value: _countKind(files, _AgentFileKind.document).toString(),
            icon: Icons.description_outlined,
            accent: context.agentAwesomeLowAccent,
          ),
          _FileMetricCard(
            label: 'Sheets',
            value: _countKind(files, _AgentFileKind.spreadsheet).toString(),
            icon: Icons.table_chart_outlined,
            accent: context.agentAwesomeWarningAccent,
          ),
          _FileMetricCard(
            label: 'Images',
            value: _countKind(files, _AgentFileKind.image).toString(),
            icon: Icons.image_outlined,
            accent: context.agentAwesomeColors.coral,
          ),
        ];
        if (compact) {
          return Column(
            children: <Widget>[
              for (final card in cards) ...<Widget>[
                card,
                if (card != cards.last) const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Row(
          children: <Widget>[
            for (final card in cards) ...<Widget>[
              Expanded(child: card),
              if (card != cards.last) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

/// _FileMetricCard renders one compact file count.
class _FileMetricCard extends StatelessWidget {
  /// Creates one summary card.
  const _FileMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  /// Metric label.
  final String label;

  /// Metric value.
  final String value;

  /// Metric icon.
  final IconData icon;

  /// Accent color for the left edge.
  final Color accent;

  /// Builds the summary card.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeCardGradient,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: <Widget>[
          Container(width: 4, color: accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: <Widget>[
                  _FileIconBox(icon: icon, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          value,
                          style: TextStyle(
                            color: colors.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// _FileKindFilterBar renders file type filter chips.
class _FileKindFilterBar extends StatelessWidget {
  /// Creates the file type filter bar.
  const _FileKindFilterBar({
    required this.selected,
    required this.files,
    required this.onSelected,
  });

  /// Active filter.
  final _FileKindFilter selected;

  /// File inventory used to show counts.
  final List<_AgentFileItem> files;

  /// Selects a filter.
  final ValueChanged<_FileKindFilter> onSelected;

  /// Builds filter controls with subtle dark styling.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final filter in _FileKindFilter.values) ...<Widget>[
            _FileFilterChip(
              filter: filter,
              selected: selected == filter,
              count: _countFilter(files, filter),
              onSelected: () => onSelected(filter),
            ),
            if (filter != _FileKindFilter.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// _FileFilterChip renders one file type filter trigger.
class _FileFilterChip extends StatelessWidget {
  /// Creates a filter chip.
  const _FileFilterChip({
    required this.filter,
    required this.selected,
    required this.count,
    required this.onSelected,
  });

  /// File type filter represented by this chip.
  final _FileKindFilter filter;

  /// Whether this chip is active.
  final bool selected;

  /// Count shown beside the filter label.
  final int count;

  /// Selects this filter.
  final VoidCallback onSelected;

  /// Builds the filter chip.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return OutlinedButton.icon(
      onPressed: onSelected,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        backgroundColor: selected ? colors.greenSoft : colors.surface,
        foregroundColor: selected ? colors.green : colors.ink,
        side: BorderSide(color: selected ? colors.borderStrong : colors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(filter.icon, size: 16),
      label: Text('${filter.label} $count'),
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
          gradient: context.agentAwesomeCardGradient,
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
              child: ColoredBox(color: accent, child: const SizedBox(width: 4)),
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
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
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
        borderRadius: BorderRadius.circular(8),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.agentAwesomeIsDark ? 0.12 : 0.1),
        border: Border.all(color: color.withValues(alpha: 0.62)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: colors.muted),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
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
  const _FilesEmptyState({required this.hasAnyFile, required this.onAddFile});

  /// Whether files exist before filtering.
  final bool hasAnyFile;

  /// Opens the add-file affordance.
  final VoidCallback onAddFile;

  /// Builds the empty state with a clear file-only message.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final title = hasAnyFile ? 'No matching files' : 'No files indexed yet';
    final message = hasAnyFile
        ? 'Try a different file type or search.'
        : 'Files for your agent. Add PDFs, spreadsheets, images, and other source documents here. Chat messages belong in Memory, not Files.';
    return PanelSectionBlock(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.folder_open_outlined, color: colors.muted, size: 38),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted, height: 1.35),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.green,
                foregroundColor: colors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
              onPressed: onAddFile,
              icon: const Icon(Icons.add),
              label: const Text('Add file'),
            ),
          ],
        ),
      ),
    );
  }
}
