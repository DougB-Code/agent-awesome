/// Empty state and contact capture dialog widgets.
part of 'people_section.dart';

/// _ContactsEmptyState renders empty and no-match states for contacts.
class _ContactsEmptyState extends StatelessWidget {
  /// Creates the contact empty state.
  const _ContactsEmptyState({
    required this.hasAnyContact,
    required this.onAddContact,
  });

  /// Whether contacts exist before filtering.
  final bool hasAnyContact;

  /// Opens the add-contact affordance.
  final VoidCallback onAddContact;

  /// Builds the empty state.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final title = hasAnyContact ? 'No matching contacts' : 'No contacts yet';
    return PanelSectionBlock(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.people_alt_outlined, color: colors.muted, size: 38),
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
                onPressed: onAddContact,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// _ContactCaptureDialog captures a source-backed contact note.
class _ContactCaptureDialog extends StatefulWidget {
  /// Creates a contact capture dialog.
  const _ContactCaptureDialog({
    required this.controller,
    required this.initialName,
    required this.initialContext,
    required this.initialTopics,
  });

  /// Shared app controller used to save the note.
  final AgentAwesomeAppController controller;

  /// Initial contact name, if a contact is selected.
  final String initialName;

  /// Initial context label, if a contact context is selected.
  final String initialContext;

  /// Initial topic labels for the selected contact.
  final List<String> initialTopics;

  @override
  State<_ContactCaptureDialog> createState() => _ContactCaptureDialogState();
}

class _ContactCaptureDialogState extends State<_ContactCaptureDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _context = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  String _firewall = 'user';
  String _sensitivity = 'private';

  /// Initializes dialog fields from the selected contact.
  @override
  void initState() {
    super.initState();
    _firewall = widget.controller.defaultMemoryFirewallId;
    _name.text = widget.initialName;
    _context.text = widget.initialContext;
    _topics.text = widget.initialTopics.join(', ');
  }

  /// Cleans up dialog text controllers.
  @override
  void dispose() {
    _name.dispose();
    _context.dispose();
    _note.dispose();
    _topics.dispose();
    super.dispose();
  }

  /// Builds the contact note dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialName.isEmpty ? 'Add Contact' : 'Add Note'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PanelTextFormField(controller: _name, label: 'Name'),
              const SizedBox(height: 10),
              PanelTextFormField(controller: _context, label: 'Context'),
              const SizedBox(height: 10),
              PanelTextFormField(controller: _note, label: 'Note', maxLines: 5),
              const SizedBox(height: 10),
              PanelTextFormField(controller: _topics, label: 'Topics'),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: PanelDropdownFormField<String>(
                      label: 'Firewall',
                      value: _firewall,
                      values: widget.controller.memoryFirewallIds,
                      tooltip: 'Firewall',
                      labelFor: widget.controller.memoryFirewallPickerLabel,
                      onChanged: (value) => setState(() => _firewall = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PanelDropdownFormField<String>(
                      label: 'Sensitivity',
                      value: _sensitivity,
                      values: const <String>[
                        'public',
                        'internal',
                        'private',
                        'restricted',
                      ],
                      tooltip: 'Sensitivity',
                      labelFor: _contactLabel,
                      onChanged: (value) =>
                          setState(() => _sensitivity = value),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  /// Saves the contact note as source-backed memory.
  Future<void> _save() async {
    final name = _name.text.trim();
    final contextLabel = _context.text.trim();
    final note = _note.text.trim();
    if (name.isEmpty) {
      return;
    }
    final content = _contactNoteContent(
      name: name,
      contextLabel: contextLabel,
      note: note,
    );
    final slug = _contactSlug(name);
    final contextSlug = _contactSlug(contextLabel);
    final now = DateTime.now().microsecondsSinceEpoch;
    final draft = MemoryCaptureDraft(
      content: content,
      title: _contactNoteTitle(
        name: name,
        contextLabel: contextLabel,
        note: note,
      ),
      kind: 'profile_fact',
      firewall: _coerceContactDropdownValue(
        widget.controller.memoryFirewallIds,
        _firewall,
        widget.controller.defaultMemoryFirewallId,
      ),
      trustLevel: 'user_asserted',
      sensitivity: _sensitivity,
      sourceSystem: 'agent_awesome_people',
      sourceId: 'contact:$slug:$contextSlug:$now',
      subjects: <String>['people', if (contextLabel.isNotEmpty) contextLabel],
      topics: _mergedContactTopics(
        _splitContactList(_topics.text),
        contextLabel,
      ),
      entityNames: <String>[name],
    );
    await widget.controller.saveMemoryCandidateFromUi(
      draft,
      idempotencyKey: 'agent_awesome_people:$slug:$now',
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Coerces a contact dropdown selection to an allowed value.
String _coerceContactDropdownValue(
  List<String> values,
  String value,
  String fallback,
) {
  return values.contains(value) ? value : fallback;
}
