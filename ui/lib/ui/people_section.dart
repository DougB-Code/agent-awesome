/// Renders contact management surfaces for people-backed memory and work.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../domain/date_formatting.dart';
import '../domain/models.dart';
import 'panels/panels.dart';

const String _contactProfileModeId = 'profile';
const String _contactContextsModeId = 'contexts';
const String _contactActivityModeId = 'activity';
const String _contactSourcesModeId = 'sources';
const String _contactPageModeId = 'page';

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

/// _ContactsLibraryContent renders the searchable contact list.
class _ContactsLibraryContent extends StatelessWidget {
  /// Creates the contact library content.
  const _ContactsLibraryContent({
    required this.contacts,
    required this.query,
    required this.selectedContactId,
    required this.filter,
    required this.onFilterChanged,
    required this.onSelected,
    required this.onAddContact,
  });

  /// All contacts known to the section.
  final List<_ContactItem> contacts;

  /// Fuzzy search query from the command subshell.
  final String query;

  /// Currently selected contact id.
  final String? selectedContactId;

  /// Active contact filter.
  final _ContactFilter filter;

  /// Changes the active contact filter.
  final ValueChanged<_ContactFilter> onFilterChanged;

  /// Selects a contact card.
  final ValueChanged<String> onSelected;

  /// Opens the add-contact affordance.
  final VoidCallback onAddContact;

  /// Builds the contact library body.
  @override
  Widget build(BuildContext context) {
    final visibleContacts = _filteredContacts(contacts, query, filter);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ContactSummaryStrip(contacts: contacts),
          const SizedBox(height: 14),
          _ContactFilterBar(
            selected: filter,
            contacts: contacts,
            onSelected: onFilterChanged,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: visibleContacts.isEmpty
                ? _ContactsEmptyState(
                    hasAnyContact: contacts.isNotEmpty,
                    onAddContact: onAddContact,
                  )
                : ListView.separated(
                    itemCount: visibleContacts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final contact = visibleContacts[index];
                      return _ContactCard(
                        contact: contact,
                        selected: contact.id == selectedContactId,
                        onTap: () => onSelected(contact.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// _ContactSummaryStrip renders high-level contact inventory counts.
class _ContactSummaryStrip extends StatelessWidget {
  /// Creates the contact summary strip.
  const _ContactSummaryStrip({required this.contacts});

  /// Contact inventory to summarize.
  final List<_ContactItem> contacts;

  /// Builds responsive contact metric cards.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final cards = <Widget>[
          _ContactMetricCard(
            label: 'Contacts',
            value: contacts.length.toString(),
            icon: Icons.people_alt_outlined,
            accent: context.agentAwesomeColors.green,
          ),
          _ContactMetricCard(
            label: 'Active',
            value: _activeContactCount(contacts).toString(),
            icon: Icons.task_alt_outlined,
            accent: context.agentAwesomeLowAccent,
          ),
          _ContactMetricCard(
            label: 'Contexts',
            value: _contactContextCount(contacts).toString(),
            icon: Icons.account_tree_outlined,
            accent: context.agentAwesomeColors.green,
          ),
          _ContactMetricCard(
            label: 'Commitments',
            value: _contactCommitmentCount(contacts).toString(),
            icon: Icons.handshake_outlined,
            accent: context.agentAwesomeWarningAccent,
          ),
          _ContactMetricCard(
            label: 'Sources',
            value: _contactSourceCount(contacts).toString(),
            icon: Icons.source_outlined,
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

/// _ContactMetricCard renders one compact contact count.
class _ContactMetricCard extends StatelessWidget {
  /// Creates one contact summary card.
  const _ContactMetricCard({
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

  /// Builds the contact summary card.
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
                  _ContactIconBox(icon: icon, color: accent),
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

/// _ContactFilterBar renders contact filter chips.
class _ContactFilterBar extends StatelessWidget {
  /// Creates the contact filter bar.
  const _ContactFilterBar({
    required this.selected,
    required this.contacts,
    required this.onSelected,
  });

  /// Active filter.
  final _ContactFilter selected;

  /// Contact inventory used to show counts.
  final List<_ContactItem> contacts;

  /// Selects a filter.
  final ValueChanged<_ContactFilter> onSelected;

  /// Builds filter controls with compact styling.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final filter in _ContactFilter.values) ...<Widget>[
            _ContactFilterChip(
              filter: filter,
              selected: selected == filter,
              count: _countContactFilter(contacts, filter),
              onSelected: () => onSelected(filter),
            ),
            if (filter != _ContactFilter.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// _ContactFilterChip renders one contact filter trigger.
class _ContactFilterChip extends StatelessWidget {
  /// Creates a contact filter chip.
  const _ContactFilterChip({
    required this.filter,
    required this.selected,
    required this.count,
    required this.onSelected,
  });

  /// Contact filter represented by this chip.
  final _ContactFilter filter;

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

/// _ContactCard renders one selectable contact record.
class _ContactCard extends StatelessWidget {
  /// Creates one contact card.
  const _ContactCard({
    required this.contact,
    required this.selected,
    required this.onTap,
  });

  /// Contact item to render.
  final _ContactItem contact;

  /// Whether this card is selected.
  final bool selected;

  /// Selects this contact.
  final VoidCallback onTap;

  /// Builds the contact row with memory and work metadata.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accent = _contactAccent(context, contact);
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
                      _ContactIconBox(
                        icon: Icons.person_outline,
                        color: accent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              contact.name,
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
                              contact.summary,
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
                      _ContactStatusBadge(
                        label: contact.statusLabel,
                        color: accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _ContactMetadataBadge(
                        icon: Icons.account_tree_outlined,
                        label: '${contact.contexts.length} contexts',
                      ),
                      _ContactMetadataBadge(
                        icon: Icons.source_outlined,
                        label: '${contact.memoryRecords.length} sources',
                      ),
                      if (contact.openTaskCount > 0)
                        _ContactMetadataBadge(
                          icon: Icons.task_alt_outlined,
                          label: '${contact.openTaskCount} active tasks',
                        ),
                      if (contact.commitments.isNotEmpty)
                        _ContactMetadataBadge(
                          icon: Icons.handshake_outlined,
                          label: '${contact.commitments.length} commitments',
                        ),
                      for (final topic in contact.topics.take(2))
                        _ContactMetadataBadge(
                          icon: Icons.sell_outlined,
                          label: topic,
                        ),
                      for (final context in contact.contexts.take(2))
                        _ContactMetadataBadge(
                          icon: Icons.label_outline,
                          label: context.displayLabel,
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

/// _ContactIconBox renders a compact contact icon tile.
class _ContactIconBox extends StatelessWidget {
  /// Creates a contact icon box.
  const _ContactIconBox({required this.icon, required this.color});

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

/// _ContactStatusBadge renders a contact status badge.
class _ContactStatusBadge extends StatelessWidget {
  /// Creates a status badge.
  const _ContactStatusBadge({required this.label, required this.color});

  /// Badge label.
  final String label;

  /// Badge accent color.
  final Color color;

  /// Builds the status badge.
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

/// _ContactMetadataBadge renders compact supporting contact metadata.
class _ContactMetadataBadge extends StatelessWidget {
  /// Creates a contact metadata badge.
  const _ContactMetadataBadge({required this.icon, required this.label});

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
            constraints: const BoxConstraints(maxWidth: 220),
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

/// _ContactInspectorContent renders details for the selected contact.
class _ContactInspectorContent extends StatelessWidget {
  /// Creates selected contact inspector content.
  const _ContactInspectorContent({
    required this.controller,
    required this.contact,
    required this.modeId,
    required this.onAddNote,
    required this.onSendToChat,
  });

  /// Shared app controller for contact actions.
  final AgentAwesomeAppController controller;

  /// Selected contact.
  final _ContactItem? contact;

  /// Active inspector mode.
  final String modeId;

  /// Opens the note capture dialog for this contact.
  final VoidCallback? onAddNote;

  /// Sends contact context to the active chat.
  final VoidCallback? onSendToChat;

  /// Builds the detail mode body.
  @override
  Widget build(BuildContext context) {
    final selected = contact;
    if (selected == null) {
      return const PanelEmptyBlock(label: 'No contacts indexed yet');
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: switch (modeId) {
        _contactContextsModeId => _ContactContextsDetails(contact: selected),
        _contactActivityModeId => _ContactActivityDetails(contact: selected),
        _contactSourcesModeId => _ContactSourcesDetails(
          controller: controller,
          contact: selected,
        ),
        _contactPageModeId => _ContactPageDetails(
          controller: controller,
          contact: selected,
        ),
        _ => _ContactProfileDetails(
          controller: controller,
          contact: selected,
          onAddNote: onAddNote,
          onSendToChat: onSendToChat,
        ),
      },
    );
  }
}

/// _ContactProfileDetails renders the main selected-contact summary.
class _ContactProfileDetails extends StatelessWidget {
  /// Creates primary contact details.
  const _ContactProfileDetails({
    required this.controller,
    required this.contact,
    required this.onAddNote,
    required this.onSendToChat,
  });

  /// Shared app controller for page loading.
  final AgentAwesomeAppController controller;

  /// Selected contact.
  final _ContactItem contact;

  /// Opens a contact note dialog.
  final VoidCallback? onAddNote;

  /// Sends contact context to chat.
  final VoidCallback? onSendToChat;

  /// Builds the selected-contact overview.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accent = _contactAccent(context, contact);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ContactInspectorHeader(contact: contact),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onAddNote,
              icon: const Icon(Icons.note_add_outlined, size: 16),
              label: const Text('Add note'),
            ),
            OutlinedButton.icon(
              onPressed: contact.primaryMemory == null
                  ? null
                  : () => unawaited(
                      controller.loadEntityPageFromUi(contact.primaryMemory!),
                    ),
              icon: const Icon(Icons.article_outlined, size: 16),
              label: const Text('Load page'),
            ),
            OutlinedButton.icon(
              onPressed: onSendToChat,
              icon: const Icon(Icons.send_outlined, size: 16),
              label: const Text('Send to chat'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ContactInspectorBlock(
          label: 'Summary',
          child: SelectableText(
            contact.summary,
            style: TextStyle(color: colors.muted, fontSize: 15, height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        _ContactInspectorBlock(
          label: 'Profile',
          child: Column(
            children: <Widget>[
              _ContactInspectorRow(label: 'Status', value: contact.statusLabel),
              _ContactInspectorRow(label: 'Entity id', value: contact.entityId),
              _ContactInspectorRow(
                label: 'Last update',
                value: formatOptionalLocalDateTime(contact.lastUpdatedAt),
              ),
              _ContactInspectorRow(
                label: 'Contexts',
                value: contact.contexts.length.toString(),
              ),
              _ContactInspectorRow(
                label: 'Scopes',
                value: contact.scopeLabels.join(', '),
              ),
              _ContactInspectorRow(
                label: 'Primary',
                value: contact.primaryContext?.displayLabel ?? '',
              ),
              _ContactInspectorRow(
                label: 'Sensitivity',
                value: contact.primaryContext?.sensitivityLabel ?? '',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ContactInspectorBlock(
          label: 'Contexts',
          child: contact.contexts.isEmpty
              ? Text('No contexts', style: TextStyle(color: colors.muted))
              : Column(
                  children: <Widget>[
                    for (final context in contact.contexts.take(4))
                      _ContactContextSummaryRow(context: context),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _ContactInspectorBlock(
          label: 'Topics',
          child: contact.topics.isEmpty
              ? Text('No topics', style: TextStyle(color: colors.muted))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final topic in contact.topics)
                      _ContactStatusBadge(
                        label: _contactLabel(topic),
                        color: accent,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// _ContactContextsDetails renders scoped context slices for a contact.
class _ContactContextsDetails extends StatelessWidget {
  /// Creates contact context details.
  const _ContactContextsDetails({required this.contact});

  /// Selected contact.
  final _ContactItem contact;

  /// Builds the contact's scope/context groups.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ContactInspectorHeader(contact: contact),
        const SizedBox(height: 18),
        if (contact.contexts.isEmpty)
          const PanelEmptyBlock(label: 'No contexts')
        else
          for (final context in contact.contexts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ContactContextCard(context: context),
            ),
      ],
    );
  }
}

/// _ContactContextSummaryRow renders a compact context line in Profile.
class _ContactContextSummaryRow extends StatelessWidget {
  /// Creates a context summary row.
  const _ContactContextSummaryRow({required this.context});

  /// Context slice to summarize.
  final _ContactContext context;

  /// Builds a compact row for one context slice.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.account_tree_outlined, size: 18, color: colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  this.context.displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  this.context.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _ContactContextCard renders one scoped context slice.
class _ContactContextCard extends StatelessWidget {
  /// Creates a context card.
  const _ContactContextCard({required this.context});

  /// Context slice to render.
  final _ContactContext context;

  /// Builds one contact context with its own activity counts.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.account_tree_outlined, size: 20, color: colors.green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      this.context.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _contactLabel(this.context.scope),
                      style: TextStyle(color: colors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            this.context.summary,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              PanelBadge(label: _contactLabel(this.context.scope)),
              PanelBadge(label: this.context.sensitivityLabel),
              PanelBadge(label: '${this.context.sourceCount} sources'),
              if (this.context.openTaskCount > 0)
                PanelBadge(label: '${this.context.openTaskCount} active tasks'),
              if (this.context.commitmentCount > 0)
                PanelBadge(
                  label: '${this.context.commitmentCount} commitments',
                ),
              for (final topic in this.context.topics.take(3))
                PanelBadge(label: topic),
            ],
          ),
        ],
      ),
    );
  }
}

/// _ContactActivityDetails renders tasks and commitments for a contact.
class _ContactActivityDetails extends StatelessWidget {
  /// Creates contact activity details.
  const _ContactActivityDetails({required this.contact});

  /// Selected contact.
  final _ContactItem contact;

  /// Builds work and commitment activity.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ContactInspectorHeader(contact: contact),
        const SizedBox(height: 18),
        _ContactInspectorBlock(
          label: 'Tasks',
          child: contact.tasks.isEmpty
              ? const _ContactMutedText('No tasks')
              : Column(
                  children: <Widget>[
                    for (final task in contact.tasks)
                      _ContactTaskTile(task: task),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _ContactInspectorBlock(
          label: 'Commitments',
          child: contact.commitments.isEmpty
              ? const _ContactMutedText('No commitments')
              : Column(
                  children: <Widget>[
                    for (final commitment in contact.commitments)
                      _ContactCommitmentTile(commitment: commitment),
                  ],
                ),
        ),
      ],
    );
  }
}

/// _ContactSourcesDetails renders memory records linked to a contact.
class _ContactSourcesDetails extends StatelessWidget {
  /// Creates source details.
  const _ContactSourcesDetails({
    required this.controller,
    required this.contact,
  });

  /// Shared app controller for source selection.
  final AgentAwesomeAppController controller;

  /// Selected contact.
  final _ContactItem contact;

  /// Builds source-backed contact records.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ContactInspectorHeader(contact: contact),
        const SizedBox(height: 18),
        if (contact.memoryRecords.isEmpty)
          const PanelEmptyBlock(label: 'No source records')
        else
          for (final record in contact.memoryRecords)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ContactMemoryTile(
                record: record,
                selected: controller.selectedMemory?.id == record.id,
                onTap: () => unawaited(controller.selectMemory(record.id)),
              ),
            ),
      ],
    );
  }
}

/// _ContactPageDetails renders a compiled page preview for a contact.
class _ContactPageDetails extends StatelessWidget {
  /// Creates compiled page details.
  const _ContactPageDetails({required this.controller, required this.contact});

  /// Shared app controller for page loading.
  final AgentAwesomeAppController controller;

  /// Selected contact.
  final _ContactItem contact;

  /// Builds compiled page preview and loading controls.
  @override
  Widget build(BuildContext context) {
    final page = controller.selectedMemoryPage;
    final belongs = page != null && _pageBelongsToContact(page, contact);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ContactInspectorHeader(contact: contact),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: contact.primaryMemory == null
              ? null
              : () => unawaited(
                  controller.loadEntityPageFromUi(contact.primaryMemory!),
                ),
          icon: const Icon(Icons.article_outlined, size: 16),
          label: const Text('Load page'),
        ),
        const SizedBox(height: 12),
        if (belongs)
          _ContactCompiledPagePreview(page: page)
        else
          const PanelEmptyBlock(label: 'No compiled contact page loaded'),
      ],
    );
  }
}

/// _ContactInspectorHeader renders the selected-contact heading.
class _ContactInspectorHeader extends StatelessWidget {
  /// Creates the inspector header.
  const _ContactInspectorHeader({required this.contact});

  /// Selected contact.
  final _ContactItem contact;

  /// Builds the selected-contact heading row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final accent = _contactAccent(context, contact);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ContactIconBox(icon: Icons.person_outline, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectableText(
                contact.name,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                contact.statusLabel,
                style: TextStyle(color: colors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// _ContactInspectorBlock renders a titled contact detail group.
class _ContactInspectorBlock extends StatelessWidget {
  /// Creates a contact inspector block.
  const _ContactInspectorBlock({required this.label, required this.child});

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

/// _ContactInspectorRow renders one selected-contact metadata row.
class _ContactInspectorRow extends StatelessWidget {
  /// Creates an inspector metadata row.
  const _ContactInspectorRow({required this.label, required this.value});

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

/// _ContactMutedText renders muted placeholder text inside detail blocks.
class _ContactMutedText extends StatelessWidget {
  /// Creates muted contact text.
  const _ContactMutedText(this.label);

  /// Text to render.
  final String label;

  /// Builds muted placeholder text.
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(color: context.agentAwesomeColors.muted),
    );
  }
}

/// _ContactTaskTile renders one contact-owned task.
class _ContactTaskTile extends StatelessWidget {
  /// Creates a task tile.
  const _ContactTaskTile({required this.task});

  /// Task linked to the contact.
  final WorkspaceTask task;

  /// Builds one compact task row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.task_alt_outlined, size: 18, color: colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    PanelBadge(label: _contactLabel(task.status)),
                    PanelBadge(label: _contactLabel(_taskContextScope(task))),
                    PanelBadge(label: _taskContextLabel(task)),
                    if (task.priority.isNotEmpty)
                      PanelBadge(label: _contactLabel(task.priority)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _ContactCommitmentTile renders one commitment that names a contact.
class _ContactCommitmentTile extends StatelessWidget {
  /// Creates a commitment tile.
  const _ContactCommitmentTile({required this.commitment});

  /// Commitment linked to the contact.
  final TaskCommitment commitment;

  /// Builds one compact commitment row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final title = _firstNonEmpty(<String>[
      commitment.project,
      commitment.domain,
      commitment.responsibility,
      commitment.timeWindow,
      'Commitment',
    ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.handshake_outlined, size: 18, color: colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _joinNonEmpty(<String>[
                    commitment.timeWindow,
                    commitment.responsibility,
                    commitment.consequence,
                  ]),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final person in commitment.people.take(3))
                      PanelBadge(label: person),
                    PanelBadge(
                      label: _contactLabel(_commitmentContextScope(commitment)),
                    ),
                    PanelBadge(label: _commitmentContextLabel(commitment)),
                    if (commitment.hardness.isNotEmpty)
                      PanelBadge(label: _contactLabel(commitment.hardness)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// _ContactMemoryTile renders one memory source linked to a contact.
class _ContactMemoryTile extends StatelessWidget {
  /// Creates a contact memory tile.
  const _ContactMemoryTile({
    required this.record,
    required this.selected,
    required this.onTap,
  });

  /// Memory record linked to the contact.
  final MemoryRecord record;

  /// Whether this source is selected in the global memory inspector.
  final bool selected;

  /// Selects this source.
  final VoidCallback onTap;

  /// Builds one source-backed record row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? colors.panelStrong : colors.surface,
          gradient: context.agentAwesomeCardGradient,
          border: Border.all(
            color: selected ? colors.borderStrong : colors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              record.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.ink, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              record.summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted, height: 1.3),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                PanelBadge(label: _contactLabel(record.kind)),
                PanelBadge(
                  label: _contactLabel(_normalizedScope(record.scope)),
                ),
                PanelBadge(label: _memoryContextLabel(record)),
                PanelBadge(label: record.sensitivity),
                if (record.sourceLabel.isNotEmpty)
                  PanelBadge(label: record.sourceLabel),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// _ContactCompiledPagePreview renders a compiled contact page.
class _ContactCompiledPagePreview extends StatelessWidget {
  /// Creates a compiled page preview.
  const _ContactCompiledPagePreview({required this.page});

  /// Compiled memory page to preview.
  final CompiledMemoryPage page;

  /// Builds a source-backed compiled page preview.
  @override
  Widget build(BuildContext context) {
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            page.title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              PanelBadge(label: _contactLabel(page.kind)),
              PanelBadge(label: page.scope),
              PanelBadge(label: '${page.sourceIds.length} sources'),
            ],
          ),
          const SizedBox(height: 16),
          SelectableText(page.content),
        ],
      ),
    );
  }
}

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
  String _scope = 'user';
  String _sensitivity = 'private';

  /// Initializes dialog fields from the selected contact.
  @override
  void initState() {
    super.initState();
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
              _ContactTextField(controller: _name, label: 'Name'),
              const SizedBox(height: 10),
              _ContactTextField(controller: _context, label: 'Context'),
              const SizedBox(height: 10),
              _ContactTextField(controller: _note, label: 'Note', maxLines: 5),
              const SizedBox(height: 10),
              _ContactTextField(controller: _topics, label: 'Topics'),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _ContactDropdown(
                      value: _scope,
                      values: const <String>[
                        'user',
                        'household',
                        'tenant',
                        'project',
                      ],
                      tooltip: 'Scope',
                      onChanged: (value) => setState(() => _scope = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ContactDropdown(
                      value: _sensitivity,
                      values: const <String>[
                        'public',
                        'internal',
                        'private',
                        'restricted',
                      ],
                      tooltip: 'Sensitivity',
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
      scope: _scope,
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

/// _ContactTextField renders one dialog text input.
class _ContactTextField extends StatelessWidget {
  /// Creates a dialog text field.
  const _ContactTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });

  /// Text controller for the field.
  final TextEditingController controller;

  /// Field label.
  final String label;

  /// Maximum visible lines.
  final int maxLines;

  /// Builds a compact dialog text field.
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// _ContactDropdown renders one controlled vocabulary dropdown.
class _ContactDropdown extends StatelessWidget {
  /// Creates a dropdown field.
  const _ContactDropdown({
    required this.value,
    required this.values,
    required this.tooltip,
    required this.onChanged,
  });

  /// Selected value.
  final String value;

  /// Allowed values.
  final List<String> values;

  /// Tooltip text for the control.
  final String tooltip;

  /// Selection callback.
  final ValueChanged<String> onChanged;

  /// Builds a compact dropdown control.
  @override
  Widget build(BuildContext context) {
    final dropdownValue = values.contains(value) ? value : values.first;
    return Tooltip(
      message: tooltip,
      child: DropdownButtonFormField<String>(
        initialValue: dropdownValue,
        decoration: InputDecoration(
          labelText: tooltip,
          border: const OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<String>>[
          for (final item in values)
            DropdownMenuItem<String>(
              value: item,
              child: Text(_contactLabel(item)),
            ),
        ],
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
      ),
    );
  }
}

/// _ContactItem is the contact UI model derived from memory and tasks.
class _ContactItem {
  /// Creates a contact display item.
  const _ContactItem({
    required this.id,
    required this.name,
    required this.entityId,
    required this.summary,
    required this.statusLabel,
    required this.openTaskCount,
    required this.memoryRecords,
    required this.tasks,
    required this.commitments,
    required this.contexts,
    required this.scopeLabels,
    required this.topics,
    required this.primaryMemory,
    required this.primaryContext,
    required this.lastUpdatedAt,
  });

  /// Stable contact id.
  final String id;

  /// Display name.
  final String name;

  /// Best known canonical entity id.
  final String entityId;

  /// Short profile summary.
  final String summary;

  /// Current contact status label.
  final String statusLabel;

  /// Count of open tasks assigned to this contact.
  final int openTaskCount;

  /// Memory records mentioning this contact.
  final List<MemoryRecord> memoryRecords;

  /// Tasks owned by this contact.
  final List<WorkspaceTask> tasks;

  /// Commitments involving this contact.
  final List<TaskCommitment> commitments;

  /// Scoped context slices for this contact.
  final List<_ContactContext> contexts;

  /// Scope labels represented by this contact.
  final List<String> scopeLabels;

  /// Topic labels associated with this contact.
  final List<String> topics;

  /// Primary memory record used for entity-page actions.
  final MemoryRecord? primaryMemory;

  /// Primary context used for default note routing.
  final _ContactContext? primaryContext;

  /// Most recent timestamp across linked records.
  final DateTime? lastUpdatedAt;
}

/// _ContactContext stores one scoped contact slice.
class _ContactContext {
  /// Creates an immutable contact context slice.
  const _ContactContext({
    required this.id,
    required this.scope,
    required this.label,
    required this.summary,
    required this.sensitivityLabel,
    required this.sourceCount,
    required this.openTaskCount,
    required this.commitmentCount,
    required this.memoryRecords,
    required this.tasks,
    required this.commitments,
    required this.topics,
    required this.lastUpdatedAt,
  });

  /// Stable context id.
  final String id;

  /// Memory or inferred activity scope.
  final String scope;

  /// User-facing project, trip, domain, or topic label.
  final String label;

  /// Concise summary for this context.
  final String summary;

  /// Sensitivity summary for memory records in this context.
  final String sensitivityLabel;

  /// Source-backed memory count.
  final int sourceCount;

  /// Open task count.
  final int openTaskCount;

  /// Commitment count.
  final int commitmentCount;

  /// Memory records in this context.
  final List<MemoryRecord> memoryRecords;

  /// Tasks in this context.
  final List<WorkspaceTask> tasks;

  /// Commitments in this context.
  final List<TaskCommitment> commitments;

  /// Topic labels in this context.
  final List<String> topics;

  /// Most recent timestamp across context data.
  final DateTime? lastUpdatedAt;

  /// Combined display label used in compact badges.
  String get displayLabel {
    return '${_contactLabel(scope)} / $label';
  }
}

/// _ContactAggregate collects contact state before final sorting.
class _ContactAggregate {
  /// Creates a mutable contact aggregate.
  _ContactAggregate({required this.id, required this.name});

  /// Stable contact id.
  final String id;

  /// Display name.
  final String name;

  /// Entity ids linked by memory records.
  final Set<String> entityIds = <String>{};

  /// Memory records mentioning this contact.
  final List<MemoryRecord> memoryRecords = <MemoryRecord>[];

  /// Tasks owned by this contact.
  final List<WorkspaceTask> tasks = <WorkspaceTask>[];

  /// Commitments involving this contact.
  final List<TaskCommitment> commitments = <TaskCommitment>[];

  /// Topic labels gathered from records and work.
  final Set<String> topics = <String>{};
}

/// _ContactContextAggregate collects context state before sorting.
class _ContactContextAggregate {
  /// Creates a mutable contact context aggregate.
  _ContactContextAggregate({
    required this.id,
    required this.scope,
    required this.label,
  });

  /// Stable context id.
  final String id;

  /// Scope represented by this context.
  final String scope;

  /// Context display label.
  final String label;

  /// Memory records in this context.
  final List<MemoryRecord> memoryRecords = <MemoryRecord>[];

  /// Tasks in this context.
  final List<WorkspaceTask> tasks = <WorkspaceTask>[];

  /// Commitments in this context.
  final List<TaskCommitment> commitments = <TaskCommitment>[];

  /// Topics gathered for this context.
  final Set<String> topics = <String>{};

  /// Sensitivity values from source-backed records.
  final Set<String> sensitivities = <String>{};
}

/// _ContactFilter describes the filters shown in the contact library.
enum _ContactFilter {
  /// All contacts.
  all('All contacts', Icons.people_alt_outlined),

  /// Contacts with active tasks.
  active('Active', Icons.task_alt_outlined),

  /// Contacts with source-backed memory.
  sources('Sources', Icons.source_outlined),

  /// Contacts with first-class commitments.
  commitments('Commitments', Icons.handshake_outlined),

  /// Contacts with more than one scope/context slice.
  multiContext('Multi-context', Icons.account_tree_outlined),

  /// Contacts currently known only from work ownership.
  taskOwners('Task owners', Icons.assignment_ind_outlined);

  /// Creates a contact filter.
  const _ContactFilter(this.label, this.icon);

  /// Display label.
  final String label;

  /// Display icon.
  final IconData icon;
}

/// Shows the contact capture dialog.
Future<void> _showContactCaptureDialog(
  BuildContext context,
  AgentAwesomeAppController controller, {
  _ContactItem? contact,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _ContactCaptureDialog(
        controller: controller,
        initialName: contact?.name ?? '',
        initialContext: contact?.primaryContext?.label ?? '',
        initialTopics: contact?.topics ?? const <String>[],
      );
    },
  );
}

/// Builds contact records from memory, task owners, and commitments.
List<_ContactItem> _contactItemsFromController(
  AgentAwesomeAppController controller,
) {
  final aggregates = <String, _ContactAggregate>{};
  for (final record in controller.workspace.memoryRecords) {
    for (var index = 0; index < record.entityNames.length; index++) {
      final name = record.entityNames[index].trim();
      if (!_isUsableContactName(name)) {
        continue;
      }
      final aggregate = _contactAggregateFor(aggregates, name);
      aggregate.memoryRecords.add(record);
      aggregate.topics.addAll(record.topics.where(_isUsableTopic));
      if (index < record.entityIds.length &&
          record.entityIds[index].isNotEmpty) {
        aggregate.entityIds.add(record.entityIds[index]);
      } else {
        aggregate.entityIds.addAll(record.entityIds.where(_isUsableTopic));
      }
    }
  }
  for (final task in controller.workspace.tasks) {
    final owner = task.owner.trim();
    if (!_isUsableContactName(owner)) {
      continue;
    }
    final aggregate = _contactAggregateFor(aggregates, owner);
    aggregate.tasks.add(task);
    aggregate.topics.addAll(task.topics.where(_isUsableTopic));
    for (final label in <String>[task.domain, task.project, task.context]) {
      if (_isUsableTopic(label)) {
        aggregate.topics.add(label.trim());
      }
    }
  }
  for (final commitment in controller.taskCommitments) {
    for (final person in commitment.people) {
      if (!_isUsableContactName(person)) {
        continue;
      }
      final aggregate = _contactAggregateFor(aggregates, person);
      aggregate.commitments.add(commitment);
      for (final label in <String>[
        commitment.domain,
        commitment.project,
        commitment.responsibility,
        commitment.hardness,
      ]) {
        if (_isUsableTopic(label)) {
          aggregate.topics.add(label.trim());
        }
      }
    }
  }
  final contacts = aggregates.values.map(_contactItemFromAggregate).toList()
    ..sort(_compareContacts);
  return contacts;
}

/// Returns the aggregate for a contact name, creating it when needed.
_ContactAggregate _contactAggregateFor(
  Map<String, _ContactAggregate> aggregates,
  String name,
) {
  final displayName = name.trim();
  final id = _normalizedContactId(displayName);
  return aggregates.putIfAbsent(
    id,
    () => _ContactAggregate(id: id, name: displayName),
  );
}

/// Converts one aggregate into a display contact.
_ContactItem _contactItemFromAggregate(_ContactAggregate aggregate) {
  final records = _sortedContactRecords(aggregate.memoryRecords);
  final tasks = _sortedContactTasks(aggregate.tasks);
  final commitments = _sortedContactCommitments(aggregate.commitments);
  final primary = _primaryContactMemory(records);
  final contexts = _contactContextsFromAggregate(
    records: records,
    tasks: tasks,
    commitments: commitments,
  );
  final scopeLabels = _scopeLabelsForContexts(contexts);
  final openTaskCount = tasks.where(_contactTaskIsOpen).length;
  return _ContactItem(
    id: aggregate.id,
    name: aggregate.name,
    entityId: aggregate.entityIds.isEmpty ? '' : aggregate.entityIds.first,
    summary: _contactSummary(
      name: aggregate.name,
      primary: primary,
      openTaskCount: openTaskCount,
      sourceCount: records.length,
      commitmentCount: commitments.length,
    ),
    statusLabel: _contactStatusLabel(
      openTaskCount: openTaskCount,
      commitmentCount: commitments.length,
      sourceCount: records.length,
    ),
    openTaskCount: openTaskCount,
    memoryRecords: records,
    tasks: tasks,
    commitments: commitments,
    contexts: contexts,
    scopeLabels: scopeLabels,
    topics: aggregate.topics.toList()..sort(),
    primaryMemory: primary,
    primaryContext: contexts.isEmpty ? null : contexts.first,
    lastUpdatedAt: _latestContactTimestamp(records, tasks, commitments),
  );
}

/// Builds scoped context slices from a contact aggregate.
List<_ContactContext> _contactContextsFromAggregate({
  required List<MemoryRecord> records,
  required List<WorkspaceTask> tasks,
  required List<TaskCommitment> commitments,
}) {
  final aggregates = <String, _ContactContextAggregate>{};
  for (final record in records) {
    final label = _memoryContextLabel(record);
    final aggregate = _contextAggregateFor(
      aggregates,
      scope: _normalizedScope(record.scope),
      label: label,
    );
    aggregate.memoryRecords.add(record);
    aggregate.topics.addAll(record.topics.where(_isUsableTopic));
    if (record.sensitivity.isNotEmpty) {
      aggregate.sensitivities.add(record.sensitivity);
    }
  }
  for (final task in tasks) {
    final aggregate = _contextAggregateFor(
      aggregates,
      scope: _taskContextScope(task),
      label: _taskContextLabel(task),
    );
    aggregate.tasks.add(task);
    aggregate.topics.addAll(task.topics.where(_isUsableTopic));
    for (final label in <String>[task.domain, task.project, task.context]) {
      if (_isUsableTopic(label)) {
        aggregate.topics.add(label.trim());
      }
    }
  }
  for (final commitment in commitments) {
    final aggregate = _contextAggregateFor(
      aggregates,
      scope: _commitmentContextScope(commitment),
      label: _commitmentContextLabel(commitment),
    );
    aggregate.commitments.add(commitment);
    for (final label in <String>[
      commitment.domain,
      commitment.project,
      commitment.responsibility,
      commitment.hardness,
    ]) {
      if (_isUsableTopic(label)) {
        aggregate.topics.add(label.trim());
      }
    }
  }
  final contexts = aggregates.values.map(_contactContextFromAggregate).toList()
    ..sort(_compareContactContexts);
  return contexts;
}

/// Returns the aggregate for a scope/context pair.
_ContactContextAggregate _contextAggregateFor(
  Map<String, _ContactContextAggregate> aggregates, {
  required String scope,
  required String label,
}) {
  final normalizedScope = _normalizedScope(scope);
  final displayLabel = label.trim().isEmpty ? 'General' : label.trim();
  final id = '$normalizedScope:${_normalizedContactId(displayLabel)}';
  return aggregates.putIfAbsent(
    id,
    () => _ContactContextAggregate(
      id: id,
      scope: normalizedScope,
      label: displayLabel,
    ),
  );
}

/// Converts one context aggregate into a display item.
_ContactContext _contactContextFromAggregate(
  _ContactContextAggregate aggregate,
) {
  final records = _sortedContactRecords(aggregate.memoryRecords);
  final tasks = _sortedContactTasks(aggregate.tasks);
  final commitments = _sortedContactCommitments(aggregate.commitments);
  final openTaskCount = tasks.where(_contactTaskIsOpen).length;
  return _ContactContext(
    id: aggregate.id,
    scope: aggregate.scope,
    label: aggregate.label,
    summary: _contactContextSummary(
      label: aggregate.label,
      records: records,
      tasks: tasks,
      commitments: commitments,
    ),
    sensitivityLabel: _contextSensitivityLabel(aggregate.sensitivities),
    sourceCount: records.length,
    openTaskCount: openTaskCount,
    commitmentCount: commitments.length,
    memoryRecords: records,
    tasks: tasks,
    commitments: commitments,
    topics: aggregate.topics.toList()..sort(),
    lastUpdatedAt: _latestContactTimestamp(records, tasks, commitments),
  );
}

/// Summarizes one scoped context slice.
String _contactContextSummary({
  required String label,
  required List<MemoryRecord> records,
  required List<WorkspaceTask> tasks,
  required List<TaskCommitment> commitments,
}) {
  final primary = _primaryContactMemory(records);
  if (primary != null && primary.summary.trim().isNotEmpty) {
    return primary.summary.trim();
  }
  final openTaskCount = tasks.where(_contactTaskIsOpen).length;
  final parts = <String>[
    if (openTaskCount > 0) '$openTaskCount active tasks',
    if (commitments.isNotEmpty) '${commitments.length} commitments',
    if (records.isNotEmpty) '${records.length} source records',
  ];
  if (parts.isEmpty) {
    return label;
  }
  return parts.join(' | ');
}

/// Returns a sensitivity label for one context.
String _contextSensitivityLabel(Set<String> sensitivities) {
  final values = sensitivities.where((value) => value.trim().isNotEmpty);
  if (values.isEmpty) {
    return '-';
  }
  if (values.length == 1) {
    return values.first;
  }
  return 'mixed';
}

/// Returns distinct readable scope labels for a contact.
List<String> _scopeLabelsForContexts(List<_ContactContext> contexts) {
  final labels = <String>{};
  for (final context in contexts) {
    labels.add(_contactLabel(context.scope));
  }
  return labels.toList()..sort();
}

/// Compares context slices for contact display.
int _compareContactContexts(_ContactContext left, _ContactContext right) {
  final activeCompare = right.openTaskCount.compareTo(left.openTaskCount);
  if (activeCompare != 0) {
    return activeCompare;
  }
  final commitmentCompare = right.commitmentCount.compareTo(
    left.commitmentCount,
  );
  if (commitmentCompare != 0) {
    return commitmentCompare;
  }
  final sourceCompare = right.sourceCount.compareTo(left.sourceCount);
  if (sourceCompare != 0) {
    return sourceCompare;
  }
  final scopeCompare = left.scope.compareTo(right.scope);
  if (scopeCompare != 0) {
    return scopeCompare;
  }
  return left.label.compareTo(right.label);
}

/// Returns a concise summary for one contact.
String _contactSummary({
  required String name,
  required MemoryRecord? primary,
  required int openTaskCount,
  required int sourceCount,
  required int commitmentCount,
}) {
  final summary = primary?.summary.trim() ?? '';
  if (summary.isNotEmpty) {
    return summary;
  }
  final parts = <String>[
    if (openTaskCount > 0) '$openTaskCount active tasks',
    if (commitmentCount > 0) '$commitmentCount commitments',
    if (sourceCount > 0) '$sourceCount source records',
  ];
  if (parts.isEmpty) {
    return '$name is referenced by workspace work.';
  }
  return parts.join(' | ');
}

/// Returns the status label for one contact.
String _contactStatusLabel({
  required int openTaskCount,
  required int commitmentCount,
  required int sourceCount,
}) {
  if (openTaskCount > 0) {
    return 'Active';
  }
  if (commitmentCount > 0) {
    return 'Committed';
  }
  if (sourceCount > 0) {
    return 'Known';
  }
  return 'Referenced';
}

/// Returns the preferred memory record for contact actions.
MemoryRecord? _primaryContactMemory(List<MemoryRecord> records) {
  if (records.isEmpty) {
    return null;
  }
  for (final record in records) {
    if (record.kind == 'profile_fact' && record.status == 'active') {
      return record;
    }
  }
  for (final record in records) {
    if (record.status == 'active') {
      return record;
    }
  }
  return records.first;
}

/// Sorts contact memory records by usefulness and recency.
List<MemoryRecord> _sortedContactRecords(List<MemoryRecord> records) {
  final sorted = List<MemoryRecord>.from(records);
  sorted.sort((left, right) {
    final leftProfile = left.kind == 'profile_fact' ? 0 : 1;
    final rightProfile = right.kind == 'profile_fact' ? 0 : 1;
    final profileCompare = leftProfile.compareTo(rightProfile);
    if (profileCompare != 0) {
      return profileCompare;
    }
    final timeCompare = _compareDateDesc(left.updatedAt, right.updatedAt);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return left.title.compareTo(right.title);
  });
  return sorted;
}

/// Sorts contact tasks by open state and title.
List<WorkspaceTask> _sortedContactTasks(List<WorkspaceTask> tasks) {
  final sorted = List<WorkspaceTask>.from(tasks);
  sorted.sort((left, right) {
    final leftOpen = _contactTaskIsOpen(left) ? 0 : 1;
    final rightOpen = _contactTaskIsOpen(right) ? 0 : 1;
    final openCompare = leftOpen.compareTo(rightOpen);
    if (openCompare != 0) {
      return openCompare;
    }
    final timeCompare = _compareDateDesc(left.updatedAt, right.updatedAt);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return left.title.compareTo(right.title);
  });
  return sorted;
}

/// Sorts commitments by recency and project label.
List<TaskCommitment> _sortedContactCommitments(
  List<TaskCommitment> commitments,
) {
  final sorted = List<TaskCommitment>.from(commitments);
  sorted.sort((left, right) {
    final timeCompare = _compareDateDesc(left.updatedAt, right.updatedAt);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return _firstNonEmpty(<String>[
      left.project,
      left.domain,
    ]).compareTo(_firstNonEmpty(<String>[right.project, right.domain]));
  });
  return sorted;
}

/// Compares contacts for library display.
int _compareContacts(_ContactItem left, _ContactItem right) {
  final activeCompare = right.openTaskCount.compareTo(left.openTaskCount);
  if (activeCompare != 0) {
    return activeCompare;
  }
  final commitmentCompare = right.commitments.length.compareTo(
    left.commitments.length,
  );
  if (commitmentCompare != 0) {
    return commitmentCompare;
  }
  final sourceCompare = right.memoryRecords.length.compareTo(
    left.memoryRecords.length,
  );
  if (sourceCompare != 0) {
    return sourceCompare;
  }
  return left.name.compareTo(right.name);
}

/// Applies text and type filters to contacts.
List<_ContactItem> _filteredContacts(
  List<_ContactItem> contacts,
  String query,
  _ContactFilter filter,
) {
  return contacts.where((contact) {
    if (!_matchesContactFilter(contact, filter)) {
      return false;
    }
    return _matchesContactQuery(contact, query);
  }).toList();
}

/// Returns whether a contact belongs to a selected filter.
bool _matchesContactFilter(_ContactItem contact, _ContactFilter filter) {
  return switch (filter) {
    _ContactFilter.all => true,
    _ContactFilter.active => contact.openTaskCount > 0,
    _ContactFilter.sources => contact.memoryRecords.isNotEmpty,
    _ContactFilter.commitments => contact.commitments.isNotEmpty,
    _ContactFilter.multiContext => contact.contexts.length > 1,
    _ContactFilter.taskOwners =>
      contact.tasks.isNotEmpty && contact.memoryRecords.isEmpty,
  };
}

/// Returns whether a contact matches the fuzzy search query.
bool _matchesContactQuery(_ContactItem contact, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }
  final haystack =
      '${contact.name} ${contact.summary} ${contact.statusLabel} '
              '${contact.topics.join(' ')} '
              '${contact.contexts.map((item) => item.displayLabel).join(' ')} '
              '${contact.tasks.map((task) => task.title).join(' ')} '
              '${contact.commitments.map((item) => item.project).join(' ')}'
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

/// Counts contacts matching a library filter.
int _countContactFilter(List<_ContactItem> contacts, _ContactFilter filter) {
  return contacts
      .where((contact) => _matchesContactFilter(contact, filter))
      .length;
}

/// Counts contacts with active task ownership.
int _activeContactCount(List<_ContactItem> contacts) {
  return contacts.where((contact) => contact.openTaskCount > 0).length;
}

/// Counts context slices across all contacts.
int _contactContextCount(List<_ContactItem> contacts) {
  return contacts.fold<int>(
    0,
    (count, contact) => count + contact.contexts.length,
  );
}

/// Counts commitments across all contacts.
int _contactCommitmentCount(List<_ContactItem> contacts) {
  return contacts.fold<int>(
    0,
    (count, contact) => count + contact.commitments.length,
  );
}

/// Counts source records across all contacts.
int _contactSourceCount(List<_ContactItem> contacts) {
  return contacts.fold<int>(
    0,
    (count, contact) => count + contact.memoryRecords.length,
  );
}

/// Returns whether a task is currently open for contact activity.
bool _contactTaskIsOpen(WorkspaceTask task) {
  final status = task.status.toLowerCase();
  return !task.done &&
      status != 'done' &&
      status != 'completed' &&
      status != 'canceled' &&
      status != 'cancelled' &&
      status != 'archived';
}

/// Returns the contact context label for a memory record.
String _memoryContextLabel(MemoryRecord record) {
  for (final value in <String>[
    ...record.subjects,
    ...record.topics,
    record.kind == 'profile_fact' ? 'Profile' : '',
  ]) {
    if (_isContactContextLabel(value)) {
      return value.trim();
    }
  }
  return 'General';
}

/// Returns the inferred contact context scope for a task.
String _taskContextScope(WorkspaceTask task) {
  if (task.project.trim().isNotEmpty) {
    return 'project';
  }
  if (task.domain.trim().isNotEmpty) {
    return 'user';
  }
  return 'user';
}

/// Returns the contact context label for a task.
String _taskContextLabel(WorkspaceTask task) {
  return _firstNonEmpty(<String>[
    task.project,
    task.context,
    task.domain,
    'Task ownership',
  ]);
}

/// Returns the inferred contact context scope for a commitment.
String _commitmentContextScope(TaskCommitment commitment) {
  if (commitment.project.trim().isNotEmpty) {
    return 'project';
  }
  return 'user';
}

/// Returns the contact context label for a commitment.
String _commitmentContextLabel(TaskCommitment commitment) {
  return _firstNonEmpty(<String>[
    commitment.project,
    commitment.domain,
    commitment.responsibility,
    'Commitment',
  ]);
}

/// Reports whether a label can identify a contact context.
bool _isContactContextLabel(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return normalized != 'people' &&
      normalized != 'person' &&
      normalized != 'contacts' &&
      normalized != 'contact';
}

/// Normalizes an empty scope into the default contact memory scope.
String _normalizedScope(String scope) {
  final trimmed = scope.trim();
  return trimmed.isEmpty ? 'user' : trimmed;
}

/// Returns the newest timestamp across contact data.
DateTime? _latestContactTimestamp(
  List<MemoryRecord> records,
  List<WorkspaceTask> tasks,
  List<TaskCommitment> commitments,
) {
  DateTime? latest;
  for (final value in <DateTime?>[
    for (final record in records) record.updatedAt ?? record.createdAt,
    for (final task in tasks) task.updatedAt ?? task.createdAt,
    for (final commitment in commitments)
      commitment.updatedAt ?? commitment.createdAt,
  ]) {
    if (value == null) {
      continue;
    }
    if (latest == null || value.isAfter(latest)) {
      latest = value;
    }
  }
  return latest;
}

/// Compares nullable dates in descending order.
int _compareDateDesc(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return right.compareTo(left);
}

/// Returns whether a compiled page belongs to a contact.
bool _pageBelongsToContact(CompiledMemoryPage page, _ContactItem contact) {
  if (page.title.trim().toLowerCase() == contact.name.trim().toLowerCase()) {
    return true;
  }
  final sourceIds = page.sourceIds.toSet();
  return contact.memoryRecords.any((record) {
    return sourceIds.contains(record.id) ||
        sourceIds.contains(record.evidenceId);
  });
}

/// Builds the chat prompt for reviewing one contact.
String _contactChatPrompt(_ContactItem contact) {
  return '''
Please review this contact context and use it as source material for the conversation.

Contact: ${contact.name}
Status: ${contact.statusLabel}
Summary: ${contact.summary}
Topics: ${contact.topics.join(', ')}
Contexts: ${contact.contexts.map((item) => item.displayLabel).join(', ')}
Open tasks: ${contact.openTaskCount}
Commitments: ${contact.commitments.length}
Sources: ${contact.memoryRecords.length}
'''
      .trim();
}

/// Returns the accent color for a contact.
Color _contactAccent(BuildContext context, _ContactItem contact) {
  final colors = context.agentAwesomeColors;
  if (contact.openTaskCount > 0) {
    return colors.green;
  }
  if (contact.commitments.isNotEmpty) {
    return context.agentAwesomeWarningAccent;
  }
  if (contact.memoryRecords.isNotEmpty) {
    return context.agentAwesomeLowAccent;
  }
  return colors.muted;
}

/// Returns whether a value is a usable contact name.
bool _isUsableContactName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (trimmed.length < 2) {
    return false;
  }
  if (trimmed.contains('/') || trimmed.contains('\\')) {
    return false;
  }
  return true;
}

/// Returns whether a topic-like value can be shown.
bool _isUsableTopic(String value) {
  return value.trim().isNotEmpty;
}

/// Normalizes a contact id from a display name.
String _normalizedContactId(String name) {
  return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Returns a filesystem-safe contact slug for source ids.
String _contactSlug(String name) {
  final slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'contact' : slug;
}

/// Splits comma-delimited contact labels.
List<String> _splitContactList(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// Merges typed topics with the selected context label.
List<String> _mergedContactTopics(List<String> topics, String contextLabel) {
  final merged = <String>{...topics};
  if (contextLabel.trim().isNotEmpty) {
    merged.add(contextLabel.trim());
  }
  return merged.toList();
}

/// Builds the stored content for a contact note.
String _contactNoteContent({
  required String name,
  required String contextLabel,
  required String note,
}) {
  if (note.trim().isNotEmpty) {
    return note.trim();
  }
  if (contextLabel.trim().isNotEmpty) {
    return 'Contact: $name\nContext: ${contextLabel.trim()}';
  }
  return 'Contact: $name';
}

/// Builds the title for a contact note.
String _contactNoteTitle({
  required String name,
  required String contextLabel,
  required String note,
}) {
  final contextSuffix = contextLabel.trim().isEmpty
      ? ''
      : ' (${contextLabel.trim()})';
  return note.trim().isEmpty
      ? '$name profile$contextSuffix'
      : 'Contact note: $name$contextSuffix';
}

/// Joins non-empty values into one readable string.
String _joinNonEmpty(List<String> values) {
  return values
      .map((value) => value.trim())
      .where((value) {
        return value.isNotEmpty;
      })
      .join(' | ');
}

/// Returns the first non-empty value from a list.
String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    if (value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}

/// Converts controlled vocabulary to readable labels.
String _contactLabel(String value) {
  if (value.isEmpty) {
    return '';
  }
  return value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
