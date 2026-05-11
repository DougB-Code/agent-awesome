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
            onFilterChanged: _selectFilter,
            onSelected: _selectContact,
            onAddContact: () =>
                _showContactCaptureDialog(context, widget.controller),
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
                  _contactChatPrompt(selected),
                  displayText: 'Review ${selected.name}',
                ),
              ),
      ),
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: _buildAreaActions,
      filterHint: 'Filter contacts...',
      emptyLabel: 'No contact areas configured',
      split: const PanelSplit(left: 0.66, min: 0.5, max: 0.84),
    );
  }

  /// Builds refresh and add-contact actions for the contact library header.
  Widget _buildAreaActions(BuildContext context, SwitcherPanelArea area) {
    final colors = context.agentAwesomeColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Tooltip(
          message: 'Refresh contacts',
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
          message: 'Add contact',
          child: IconButton.filled(
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: colors.green,
              foregroundColor: colors.surface,
            ),
            onPressed: widget.controller.memoryBusy
                ? null
                : () => _showContactCaptureDialog(context, widget.controller),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ),
      ],
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
}
