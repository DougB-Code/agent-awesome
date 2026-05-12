/// Contact inspector panels and detail blocks.
part of 'people_section.dart';

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
        _contactContextsModeId => _ContactContextsDetails(
          controller: controller,
          contact: selected,
        ),
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
                label: 'Firewalls',
                value: _contactFirewallLabels(controller, contact).join(', '),
              ),
              _ContactInspectorRow(
                label: 'Primary',
                value: contact.primaryContext == null
                    ? ''
                    : _contactContextDisplayLabel(
                        controller,
                        contact.primaryContext!,
                      ),
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
                      _ContactContextSummaryRow(
                        controller: controller,
                        context: context,
                      ),
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

/// _ContactContextsDetails renders firewall context slices for a contact.
class _ContactContextsDetails extends StatelessWidget {
  /// Creates contact context details.
  const _ContactContextsDetails({
    required this.controller,
    required this.contact,
  });

  /// Shared app controller for configured firewall labels.
  final AgentAwesomeAppController controller;

  /// Selected contact.
  final _ContactItem contact;

  /// Builds the contact's firewall/context groups.
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
              child: _ContactContextCard(
                controller: controller,
                context: context,
              ),
            ),
      ],
    );
  }
}

/// _ContactContextSummaryRow renders a compact context line in Profile.
class _ContactContextSummaryRow extends StatelessWidget {
  /// Creates a context summary row.
  const _ContactContextSummaryRow({
    required this.controller,
    required this.context,
  });

  /// Shared app controller for configured firewall labels.
  final AgentAwesomeAppController controller;

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
                  _contactContextDisplayLabel(controller, this.context),
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

/// _ContactContextCard renders one firewall context slice.
class _ContactContextCard extends StatelessWidget {
  /// Creates a context card.
  const _ContactContextCard({required this.controller, required this.context});

  /// Shared app controller for configured firewall labels.
  final AgentAwesomeAppController controller;

  /// Context slice to render.
  final _ContactContext context;

  /// Builds one contact context with its own activity counts.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final firewallAudience = controller.memoryFirewallAudienceLabel(
      this.context.firewall,
    );
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
                      controller.memoryFirewallLabel(this.context.firewall),
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
              PanelBadge(
                label: controller.memoryFirewallLabel(this.context.firewall),
              ),
              if (firewallAudience.isNotEmpty)
                PanelBadge(label: 'Shared with $firewallAudience'),
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
                controller: controller,
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
          _ContactCompiledPagePreview(controller: controller, page: page)
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
