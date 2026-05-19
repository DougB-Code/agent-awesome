/// Contact library list, filters, cards, and summary metrics.
part of 'people_section.dart';

class _ContactsLibraryContent extends StatelessWidget {
  /// Creates the contact library content.
  const _ContactsLibraryContent({
    required this.contacts,
    required this.query,
    required this.selectedContactId,
    required this.filter,
    required this.onSelected,
  });

  /// All contacts known to the section.
  final List<_ContactItem> contacts;

  /// Fuzzy search query from the command subshell.
  final String query;

  /// Currently selected contact id.
  final String? selectedContactId;

  /// Active contact filter.
  final _ContactFilter filter;

  /// Selects a contact card.
  final ValueChanged<String> onSelected;

  /// Builds the contact library body.
  @override
  Widget build(BuildContext context) {
    final visibleContacts = _filteredContacts(contacts, query, filter);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: visibleContacts.isEmpty
                ? _ContactsEmptyState(hasAnyContact: contacts.isNotEmpty)
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
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
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
        borderRadius: BorderRadius.circular(PanelStyleTokens.radius),
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
        borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
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
