/// Command-panel shell for the file workspace.
part of 'files_section.dart';

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
          icon: Icons.folder_outlined,
          builder: (query) => _FilesLibraryContent(
            files: files,
            query: query,
            selectedFileId: selected?.id,
            kindFilter: _kindFilter,
            onSelected: _selectFile,
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
          id: _fileProvenanceModeId,
          label: 'Provenance',
          icon: Icons.fingerprint,
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
        controller: widget.controller,
        file: selected,
        modeId: modeId,
        onSendToChat: selected == null
            ? null
            : () => widget.controller.sendFileToChatFromUi(selected.record),
      ),
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: _buildAreaActions,
      areaFiltersBuilder: (_, _) => _fileFilterOptions(files),
      selectedAreaFilterIdBuilder: (_) => _kindFilter.name,
      onAreaFilterSelected: (_, filterId) => _selectKindFilterId(filterId),
      filterHint: 'Filter files...',
      emptyLabel: 'No file areas configured',
      split: const PanelSplit(left: 0.30, min: 0.18, max: 0.62),
    );
  }

  /// Builds add-file actions for the file library header.
  Widget _buildAreaActions(BuildContext context, SwitcherPanelArea area) {
    return PanelIconButton(
      icon: Icons.add,
      tooltip: 'Add file',
      onPressed: widget.controller.memoryBusy
          ? null
          : widget.controller.importFileFromUi,
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

  /// Selects the file kind filter from the shared shell option id.
  void _selectKindFilterId(String filterId) {
    for (final filter in _FileKindFilter.values) {
      if (filter.name == filterId) {
        _selectKindFilter(filter);
        return;
      }
    }
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

  /// Builds shell-owned file filter options with current counts.
  List<CommandPanelFilterOption> _fileFilterOptions(
    List<_AgentFileItem> files,
  ) {
    return <CommandPanelFilterOption>[
      for (final filter in _FileKindFilter.values)
        CommandPanelFilterOption(
          id: filter.name,
          label: filter.label,
          icon: filter.icon,
          badge: _countFilter(files, filter).toString(),
        ),
    ];
  }
}
