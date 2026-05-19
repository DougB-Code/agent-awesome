/// Command-panel shell for the people workspace.
part of 'people_section.dart';

/// PeopleCommandSubShell renders contacts in the command-panel subshell.
class PeopleCommandSubShell extends StatefulWidget {
  /// Creates a contact management section.
  const PeopleCommandSubShell({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  /// Shared app controller that owns memory and task state.
  final AgentAwesomeAppController controller;

  /// Reports the active command area to the shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<PeopleCommandSubShell> createState() => _PeopleCommandSubShellState();
}

class _PeopleCommandSubShellState extends State<PeopleCommandSubShell> {
  String _detailModeId = _contactProfileModeId;
  String? _selectedContactId;
  _ContactFilter _filter = _ContactFilter.all;

  /// Builds the contact library and inspector columns.
  @override
  Widget build(BuildContext context) {
    final contacts = _contactItemsFromController(widget.controller);
    final selected = _selectedContact(contacts);
    return CommandPanelSubShell(
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          title: 'Contacts',
          icon: Icons.people_alt_outlined,
          builder: (query) => _ContactsLibraryContent(
            contacts: contacts,
            query: query,
            selectedContactId: selected?.id,
            filter: _filter,
            onSelected: _selectContact,
          ),
        ),
      ],
      detailTitle: 'Contact Inspector',
      detailModes: const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: _contactProfileModeId,
          label: 'Profile',
          icon: Icons.person_outline,
        ),
        CommandPanelDetailMode(
          id: _contactContextsModeId,
          label: 'Contexts',
          icon: Icons.account_tree_outlined,
        ),
        CommandPanelDetailMode(
          id: _contactActivityModeId,
          label: 'Activity',
          icon: Icons.checklist_rtl_outlined,
        ),
        CommandPanelDetailMode(
          id: _contactSourcesModeId,
          label: 'Sources',
          icon: Icons.source_outlined,
        ),
        CommandPanelDetailMode(
          id: _contactPageModeId,
          label: 'Page',
          icon: Icons.article_outlined,
        ),
      ],
      selectedDetailModeId: _detailModeId,
      onDetailModeSelected: _selectDetailMode,
      detailBuilder: (modeId) => _ContactInspectorContent(
        controller: widget.controller,
        contact: selected,
        modeId: modeId,
        onAddNote: selected == null
            ? null
            : () => _showContactCaptureDialog(
                context,
                widget.controller,
                contact: selected,
              ),
        onSendToChat: selected == null
            ? null
            : () => unawaited(
                widget.controller.sendUserMessage(
                  _contactChatPrompt(selected, widget.controller),
                  displayText: 'Review ${selected.name}',
                ),
              ),
      ),
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: _buildAreaActions,
      areaFiltersBuilder: (_, _) => _contactFilterOptions(contacts),
      selectedAreaFilterIdBuilder: (_) => _filter.name,
      onAreaFilterSelected: (_, filterId) => _selectFilterId(filterId),
      filterHint: 'Filter contacts...',
      emptyLabel: 'No contact areas configured',
      split: const PanelSplit(left: 0.66, min: 0.5, max: 0.84),
    );
  }

  /// Builds add-contact actions for the contact library header.
  Widget _buildAreaActions(BuildContext context, SwitcherPanelArea area) {
    return PanelIconButton(
      icon: Icons.person_add_alt_1_outlined,
      tooltip: 'Add contact',
      onPressed: widget.controller.memoryBusy
          ? null
          : () => _showContactCaptureDialog(context, widget.controller),
    );
  }

  /// Selects the active contact inspector tab.
  void _selectDetailMode(String modeId) {
    setState(() => _detailModeId = modeId);
  }

  /// Selects the active contact library filter.
  void _selectFilter(_ContactFilter filter) {
    setState(() => _filter = filter);
  }

  /// Selects the active contact library filter from a shell option id.
  void _selectFilterId(String filterId) {
    for (final filter in _ContactFilter.values) {
      if (filter.name == filterId) {
        _selectFilter(filter);
        return;
      }
    }
  }

  /// Selects one contact for the right-side inspector.
  void _selectContact(String contactId) {
    setState(() => _selectedContactId = contactId);
  }

  /// Returns the selected contact or the first available contact.
  _ContactItem? _selectedContact(List<_ContactItem> contacts) {
    if (contacts.isEmpty) {
      return null;
    }
    final selectedId = _selectedContactId;
    if (selectedId != null) {
      for (final contact in contacts) {
        if (contact.id == selectedId) {
          return contact;
        }
      }
    }
    return contacts.first;
  }

  /// Builds shell-owned contact filter options with current counts.
  List<CommandPanelFilterOption> _contactFilterOptions(
    List<_ContactItem> contacts,
  ) {
    return <CommandPanelFilterOption>[
      for (final filter in _ContactFilter.values)
        CommandPanelFilterOption(
          id: filter.name,
          label: filter.label,
          icon: filter.icon,
          badge: _countContactFilter(contacts, filter).toString(),
        ),
    ];
  }
}
