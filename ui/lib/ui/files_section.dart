/// Renders file-only management surfaces for source documents.
library;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../domain/models.dart';
import 'panels/panels.dart';

const String _fileDetailsModeId = 'details';
const String _fileSourceModeId = 'source';
const String _fileAccessModeId = 'access';

/// FilesCommandSubShell renders indexed files in the command subshell.
class FilesCommandSubShell extends StatefulWidget {
  /// Creates the file management section.
  const FilesCommandSubShell({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller that owns workspace file records.
  final AgentAwesomeAppController controller;

  /// Reports the active command area to the shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<FilesCommandSubShell> createState() => _FilesCommandSubShellState();
}

class _FilesCommandSubShellState extends State<FilesCommandSubShell> {
  String _detailModeId = _fileDetailsModeId;
  String? _selectedFileId;
  _FileKindFilter _kindFilter = _FileKindFilter.all;

  /// Builds the file library and file inspector columns.
  @override
  Widget build(BuildContext context) {
    final files = _agentFilesFromWorkspace(widget.controller.workspace);
    final selected = _selectedFile(files);
    return CommandPanelSubShell(
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          title: 'Files',
          icon: Icons.folder_open_outlined,
          builder: (query) => _FilesLibraryContent(
            files: files,
            query: query,
            selectedFileId: selected?.id,
            kindFilter: _kindFilter,
            onKindFilterChanged: _selectKindFilter,
            onSelected: _selectFile,
            onAddFile: widget.controller.importFileFromUi,
          ),
        ),
      ],
      detailTitle: 'File Inspector',
      detailModes: const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _fileDetailsModeId,
          label: 'Details',
          icon: Icons.info_outline,
        ),
        CommandPanelDetailMode(
          id: _fileSourceModeId,
          label: 'Source',
          icon: Icons.link_outlined,
        ),
        CommandPanelDetailMode(
          id: _fileAccessModeId,
          label: 'Access',
          icon: Icons.lock_outline,
        ),
      ],
      selectedDetailModeId: _detailModeId,
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: (modeId) => _FileInspectorContent(
        file: selected,
        modeId: modeId,
        onSendToChat: selected == null
            ? null
            : () => widget.controller.sendFileToChatFromUi(selected.record),
      ),
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: _buildAreaActions,
      filterHint: 'Filter files...',
      emptyLabel: 'No file areas configured',
      split: const PanelSplit(left: 0.68, min: 0.5, max: 0.84),
    );
  }

  /// Builds refresh and add-file actions for the file library header.
  Widget _buildAreaActions(BuildContext context, SwitcherPanelArea area) {
    final colors = context.agentAwesomeColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Tooltip(
          message: 'Refresh files',
          child: IconButton.outlined(
            visualDensity: VisualDensity.compact,
            onPressed: widget.controller.memoryBusy
                ? null
                : widget.controller.refreshMemoryFromUi,
            icon: Icon(Icons.refresh, color: colors.muted),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Add file',
          child: IconButton.filled(
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: colors.green,
              foregroundColor: colors.surface,
            ),
            onPressed: widget.controller.memoryBusy
                ? null
                : widget.controller.importFileFromUi,
            icon: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  /// Selects the active file inspector tab.
  void _selectDetailMode(String modeId) {
    setState(() => _detailModeId = modeId);
  }

  /// Selects the file kind filter.
  void _selectKindFilter(_FileKindFilter filter) {
    setState(() => _kindFilter = filter);
  }

  /// Selects one file for the right-side inspector.
  void _selectFile(String fileId) {
    setState(() => _selectedFileId = fileId);
  }

  /// Returns the selected file or the first available file.
  _AgentFileItem? _selectedFile(List<_AgentFileItem> files) {
    if (files.isEmpty) {
      return null;
    }
    final selectedId = _selectedFileId;
    if (selectedId != null) {
      for (final file in files) {
        if (file.id == selectedId) {
          return file;
        }
      }
    }
    return files.first;
  }
}

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

/// _FileInspectorContent renders details for the selected file.
class _FileInspectorContent extends StatelessWidget {
  /// Creates selected file inspector content.
  const _FileInspectorContent({
    required this.file,
    required this.modeId,
    required this.onSendToChat,
  });

  /// Selected file.
  final _AgentFileItem? file;

  /// Active inspector mode.
  final String modeId;

  /// Sends the selected file to the current chat.
  final VoidCallback? onSendToChat;

  /// Builds the detail mode body.
  @override
  Widget build(BuildContext context) {
    final selected = file;
    if (selected == null) {
      return const PanelEmptyBlock(
        label:
            'No files indexed yet. Files are PDFs, spreadsheets, images, and source documents, not chat messages.',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: switch (modeId) {
        _fileSourceModeId => _FileSourceDetails(file: selected),
        _fileAccessModeId => _FileAccessDetails(file: selected),
        _ => _FilePrimaryDetails(file: selected, onSendToChat: onSendToChat),
      },
    );
  }
}

/// _FilePrimaryDetails renders the main selected-file summary.
class _FilePrimaryDetails extends StatelessWidget {
  /// Creates primary file details.
  const _FilePrimaryDetails({required this.file, required this.onSendToChat});

  /// Selected file.
  final _AgentFileItem file;

  /// Sends this file to chat.
  final VoidCallback? onSendToChat;

  /// Builds the selected-file overview.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accent = _fileKindAccent(context, file.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InspectorHeader(file: file),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onSendToChat,
          icon: const Icon(Icons.send_outlined, size: 16),
          label: const Text('Send to chat'),
        ),
        const SizedBox(height: 12),
        _InspectorBlock(
          label: 'Summary',
          child: SelectableText(
            file.summary,
            style: TextStyle(color: colors.muted, fontSize: 15, height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        _InspectorBlock(
          label: 'File',
          child: Column(
            children: <Widget>[
              _InspectorRow(label: 'Type', value: file.kind.label),
              _InspectorRow(label: 'Media', value: file.mediaLabel),
              _InspectorRow(label: 'Path', value: file.pathLabel),
              _InspectorRow(label: 'Checksum', value: file.checksumLabel),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InspectorBlock(
          label: 'Topics',
          child: file.topics.isEmpty
              ? Text('No topics', style: TextStyle(color: colors.muted))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final topic in file.topics)
                      _FileTypeBadge(label: topic, color: accent),
                  ],
                ),
        ),
      ],
    );
  }
}

/// _FileSourceDetails renders provenance for the selected file.
class _FileSourceDetails extends StatelessWidget {
  /// Creates source details.
  const _FileSourceDetails({required this.file});

  /// Selected file.
  final _AgentFileItem file;

  /// Builds file source metadata.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InspectorHeader(file: file),
        const SizedBox(height: 18),
        _InspectorBlock(
          label: 'Source',
          child: Column(
            children: <Widget>[
              _InspectorRow(label: 'System', value: file.sourceSystem),
              _InspectorRow(label: 'Source id', value: file.sourceId),
              _InspectorRow(label: 'File record id', value: file.evidenceId),
              _InspectorRow(label: 'Memory id', value: file.memoryId),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InspectorBlock(
          label: 'File path',
          child: SelectableText(file.pathLabel),
        ),
      ],
    );
  }
}

/// _FileAccessDetails renders access metadata for the selected file.
class _FileAccessDetails extends StatelessWidget {
  /// Creates access details.
  const _FileAccessDetails({required this.file});

  /// Selected file.
  final _AgentFileItem file;

  /// Builds scope and lifecycle metadata.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InspectorHeader(file: file),
        const SizedBox(height: 18),
        _InspectorBlock(
          label: 'Access',
          child: Column(
            children: <Widget>[
              _InspectorRow(label: 'Scope', value: file.scope),
              _InspectorRow(label: 'Sensitivity', value: file.sensitivity),
              _InspectorRow(label: 'Trust', value: file.trustLevel),
              _InspectorRow(label: 'Status', value: file.status),
            ],
          ),
        ),
      ],
    );
  }
}

/// _InspectorHeader renders the selected-file heading.
class _InspectorHeader extends StatelessWidget {
  /// Creates the inspector header.
  const _InspectorHeader({required this.file});

  /// Selected file.
  final _AgentFileItem file;

  /// Builds the selected-file heading row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accent = _fileKindAccent(context, file.kind);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FileIconBox(icon: file.kind.icon, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectableText(
                file.title,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                file.kind.label,
                style: TextStyle(color: colors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// _InspectorBlock renders a titled detail group.
class _InspectorBlock extends StatelessWidget {
  /// Creates an inspector block.
  const _InspectorBlock({required this.label, required this.child});

  /// Group label.
  final String label;

  /// Group content.
  final Widget child;

  /// Builds one bordered inspector group.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        gradient: context.agentAwesomeCardGradient,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PanelSectionLabel(label),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// _InspectorRow renders one selected-file metadata row.
class _InspectorRow extends StatelessWidget {
  /// Creates an inspector metadata row.
  const _InspectorRow({required this.label, required this.value});

  /// Row label.
  final String label;

  /// Row value.
  final String value;

  /// Builds a label/value row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final display = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: colors.subtle,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              display,
              style: TextStyle(
                color: colors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// _FilesEmptyState renders empty and no-match states for the file library.
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
    required this.scope,
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

  /// Access scope.
  final String scope;

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

/// Builds file-only records from workspace memory records.
List<_AgentFileItem> _agentFilesFromWorkspace(ProjectWorkspace workspace) {
  final files = <_AgentFileItem>[];
  for (final record in workspace.memoryRecords) {
    if (!_isFileMemoryRecord(record)) {
      continue;
    }
    files.add(_fileItemFromRecord(record));
  }
  files.sort((left, right) => left.title.compareTo(right.title));
  return files;
}

/// Converts one file-like memory record into a display item.
_AgentFileItem _fileItemFromRecord(MemoryRecord record) {
  final path = record.rawPath.trim();
  final sourceId = record.sourceId.trim();
  final mediaType = record.rawMediaType.trim();
  final kind = _fileKindFor(record);
  return _AgentFileItem(
    id: record.evidenceId.isEmpty ? record.id : record.evidenceId,
    memoryId: record.id,
    evidenceId: record.evidenceId,
    title: _fileTitle(record),
    summary: _fileSummary(record),
    kind: kind,
    mediaLabel: mediaType.isEmpty ? _extensionLabel(path, sourceId) : mediaType,
    pathLabel: _filePathLabel(path: path, sourceId: sourceId),
    checksumLabel: record.rawChecksum,
    sourceLabel: record.sourceLabel,
    sourceSystem: record.sourceSystem,
    sourceId: sourceId,
    scope: record.scope,
    sensitivity: record.sensitivity,
    trustLevel: record.trustLevel,
    status: record.status,
    topics: record.topics,
    record: record,
  );
}

/// Returns a file-oriented title from record metadata.
String _fileTitle(MemoryRecord record) {
  final path = record.rawPath.trim();
  final sourceId = record.sourceId.trim();
  final candidates = <String>[
    if (_looksLikeFilePath(sourceId)) sourceId,
    record.title.trim(),
    if (!_isStoredSourcePath(path)) path,
    sourceId,
    path,
  ];
  for (final candidate in candidates) {
    final label = _fileNameFromPath(candidate);
    if (label.isNotEmpty) {
      return label;
    }
  }
  return 'Untitled file';
}

/// Returns a concise file summary without leaking storage terminology.
String _fileSummary(MemoryRecord record) {
  final summary = record.summary.trim();
  if (summary.isEmpty) {
    return 'Indexed file';
  }
  return _fileLanguage(summary);
}

/// Returns the user-facing path, preferring the original file location.
String _filePathLabel({required String path, required String sourceId}) {
  if (sourceId.trim().isNotEmpty &&
      (path.trim().isEmpty ||
          _isStoredSourcePath(path) ||
          _looksLikeFilePath(sourceId))) {
    return sourceId.trim();
  }
  if (_isStoredSourcePath(path)) {
    return _fileNameFromPath(path);
  }
  return path.trim().isEmpty ? sourceId.trim() : path.trim();
}

/// Removes old "evidence" wording from file-only display strings.
String _fileLanguage(String value) {
  return value
      .replaceAll(
        RegExp(r'\bAgent Awesome file evidence\b', caseSensitive: false),
        'Agent Awesome file',
      )
      .replaceAll(RegExp(r'\bfile evidence\b', caseSensitive: false), 'file')
      .replaceAll(
        RegExp(r'\bsource evidence\b', caseSensitive: false),
        'source content',
      )
      .replaceAll(
        RegExp(r'\braw evidence\b', caseSensitive: false),
        'source content',
      )
      .replaceAll(
        RegExp(r'\bevidence\b', caseSensitive: false),
        'source material',
      );
}

/// Returns whether a path points at Agent Awesome's backing source store.
bool _isStoredSourcePath(String path) {
  final normalized = path.trim().replaceAll('\\', '/').toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return normalized == 'evidence' ||
      normalized == 'sources' ||
      normalized.startsWith('evidence/') ||
      normalized.startsWith('sources/') ||
      normalized.contains('/evidence/') ||
      normalized.contains('/sources/');
}

/// Returns whether a value looks like a local file path.
bool _looksLikeFilePath(String value) {
  final trimmed = value.trim();
  return trimmed.contains('/') || trimmed.contains('\\');
}

/// Returns the last path segment from a path-like string.
String _fileNameFromPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final parts = trimmed
      .split(RegExp(r'[/\\]'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  return parts.isEmpty ? trimmed : parts.last.trim();
}

/// Returns whether a memory record represents a file rather than chat.
bool _isFileMemoryRecord(MemoryRecord record) {
  if (_isChatLikeMemory(record)) {
    return false;
  }
  final mediaType = record.rawMediaType.toLowerCase();
  final path = record.rawPath.toLowerCase();
  final title = record.title.toLowerCase();
  final source = '${record.sourceSystem} ${record.sourceId}'.toLowerCase();
  final kind = record.kind.toLowerCase();
  return _isFileMediaType(mediaType) ||
      _hasKnownFileExtension(path) ||
      _hasKnownFileExtension(title) ||
      _hasKnownFileExtension(source) ||
      _isFileKind(kind) ||
      source.contains('filesystem') ||
      source.contains('file_upload') ||
      source.contains('google_drive');
}

/// Returns whether a record is conversational memory, not a file.
bool _isChatLikeMemory(MemoryRecord record) {
  final kind = record.kind.toLowerCase();
  final title = record.title.toLowerCase();
  final source = '${record.sourceSystem} ${record.sourceId}'.toLowerCase();
  return kind == 'conversation' ||
      kind == 'chat' ||
      kind == 'chat_message' ||
      title.startsWith('chat message from ') ||
      source.contains('google_adk_session') ||
      source.contains('chat:');
}

/// Returns whether a media type is file-like for the Files screen.
bool _isFileMediaType(String mediaType) {
  if (mediaType.isEmpty) {
    return false;
  }
  if (mediaType.startsWith('image/')) {
    return true;
  }
  return mediaType.contains('pdf') ||
      mediaType.contains('spreadsheet') ||
      mediaType.contains('excel') ||
      mediaType.contains('word') ||
      mediaType.contains('presentation') ||
      mediaType.contains('powerpoint') ||
      mediaType.contains('csv') ||
      mediaType.contains('zip');
}

/// Returns whether a kind string names a file-like memory category.
bool _isFileKind(String kind) {
  return kind == 'file' ||
      kind == 'document' ||
      kind == 'source_file' ||
      kind == 'pdf' ||
      kind == 'spreadsheet' ||
      kind == 'image' ||
      kind == 'photo' ||
      kind == 'presentation';
}

/// Returns whether text contains a known file extension.
bool _hasKnownFileExtension(String value) {
  return RegExp(
    r'\.(pdf|doc|docx|xls|xlsx|csv|ods|png|jpe?g|gif|webp|heic|ppt|pptx|zip|txt|md)\b',
  ).hasMatch(value);
}

/// Returns a category for a file-like memory record.
_AgentFileKind _fileKindFor(MemoryRecord record) {
  final combined =
      '${record.rawMediaType} ${record.rawPath} ${record.title} ${record.kind}'
          .toLowerCase();
  if (combined.contains('xls') ||
      combined.contains('spreadsheet') ||
      combined.contains('excel') ||
      combined.contains('.csv') ||
      combined.contains('.ods')) {
    return _AgentFileKind.spreadsheet;
  }
  if (combined.contains('image/') ||
      combined.contains('.png') ||
      combined.contains('.jpg') ||
      combined.contains('.jpeg') ||
      combined.contains('.gif') ||
      combined.contains('.webp') ||
      combined.contains('.heic') ||
      combined.contains('photo')) {
    return _AgentFileKind.image;
  }
  if (combined.contains('presentation') ||
      combined.contains('powerpoint') ||
      combined.contains('.ppt')) {
    return _AgentFileKind.presentation;
  }
  if (combined.contains('zip') || combined.contains('.zip')) {
    return _AgentFileKind.archive;
  }
  if (combined.contains('pdf') ||
      combined.contains('.doc') ||
      combined.contains('.txt') ||
      combined.contains('.md') ||
      combined.contains('document')) {
    return _AgentFileKind.document;
  }
  return _AgentFileKind.other;
}

/// Returns a readable extension label when no media type exists.
String _extensionLabel(String path, String sourceId) {
  final value = path.isEmpty ? sourceId : path;
  final match = RegExp(
    r'\.([a-z0-9]+)\b',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) {
    return 'File';
  }
  return '.${match.group(1)!.toLowerCase()}';
}

/// Applies text and type filters to files.
List<_AgentFileItem> _filteredFiles(
  List<_AgentFileItem> files,
  String query,
  _FileKindFilter kindFilter,
) {
  return files.where((file) {
    if (!_matchesFileKindFilter(file, kindFilter)) {
      return false;
    }
    return _matchesFileQuery(file, query);
  }).toList();
}

/// Returns whether a file belongs to a selected type filter.
bool _matchesFileKindFilter(_AgentFileItem file, _FileKindFilter filter) {
  return switch (filter) {
    _FileKindFilter.all => true,
    _FileKindFilter.documents => file.kind == _AgentFileKind.document,
    _FileKindFilter.spreadsheets => file.kind == _AgentFileKind.spreadsheet,
    _FileKindFilter.images => file.kind == _AgentFileKind.image,
    _FileKindFilter.other =>
      file.kind == _AgentFileKind.other ||
          file.kind == _AgentFileKind.presentation ||
          file.kind == _AgentFileKind.archive,
  };
}

/// Returns whether a file matches the fuzzy search query.
bool _matchesFileQuery(_AgentFileItem file, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }
  final haystack =
      '${file.title} ${file.summary} ${file.mediaLabel} ${file.pathLabel} '
              '${file.sourceLabel} ${file.topics.join(' ')}'
          .toLowerCase();
  var cursor = 0;
  for (final codeUnit in normalizedQuery.codeUnits) {
    cursor = haystack.indexOf(String.fromCharCode(codeUnit), cursor);
    if (cursor == -1) {
      return false;
    }
    cursor++;
  }
  return true;
}

/// Counts files matching one concrete file kind.
int _countKind(List<_AgentFileItem> files, _AgentFileKind kind) {
  return files.where((file) => file.kind == kind).length;
}

/// Counts files matching a library filter.
int _countFilter(List<_AgentFileItem> files, _FileKindFilter filter) {
  return files.where((file) => _matchesFileKindFilter(file, filter)).length;
}

/// Returns the accent color for a file category.
Color _fileKindAccent(BuildContext context, _AgentFileKind kind) {
  final colors = context.agentAwesomeColors;
  return switch (kind) {
    _AgentFileKind.document => colors.green,
    _AgentFileKind.spreadsheet => context.agentAwesomeWarningAccent,
    _AgentFileKind.image => colors.coral,
    _AgentFileKind.presentation => colors.coral,
    _AgentFileKind.archive => colors.warningText,
    _AgentFileKind.other => colors.muted,
  };
}
