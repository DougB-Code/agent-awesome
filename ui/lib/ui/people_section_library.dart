/// Contact library list, filters, cards, and summary metrics.
part of 'people_section.dart';

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
