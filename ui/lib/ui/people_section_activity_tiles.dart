/// Contact activity tiles for tasks, memories, and pages.
part of 'people_section.dart';

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
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    PanelBadge(label: _contactLabel(task.status)),
                    PanelBadge(
                      label: _contactLabel(_taskContextFirewall(task)),
                    ),
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

/// _ContactMemoryTile renders one memory source linked to a contact.
class _ContactMemoryTile extends StatelessWidget {
  /// Creates a contact memory tile.
  const _ContactMemoryTile({
    required this.controller,
    required this.record,
    required this.selected,
    required this.onTap,
  });

  /// Shared app controller for configured firewall labels.
  final AgentAwesomeAppController controller;

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
    final firewallAudience = controller.memoryFirewallAudienceLabel(
      record.firewall,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? colors.panelStrong : colors.surface,
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
              style: TextStyle(color: colors.ink, fontWeight: FontWeight.w800),
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
                  label: controller.memoryFirewallLabel(record.firewall),
                ),
                if (firewallAudience.isNotEmpty)
                  PanelBadge(label: 'Shared with $firewallAudience'),
                PanelBadge(label: _memoryContextLabel(record)),
                PanelBadge(label: record.sensitivity),
                if (record.sourceLabel.isNotEmpty)
                  PanelBadge(label: _contactSourceLabel(record.sourceLabel)),
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
  const _ContactCompiledPagePreview({
    required this.controller,
    required this.page,
  });

  /// Shared app controller for configured firewall labels.
  final AgentAwesomeAppController controller;

  /// Compiled memory page to preview.
  final CompiledMemoryPage page;

  /// Builds a source-backed compiled page preview.
  @override
  Widget build(BuildContext context) {
    final firewallAudience = controller.memoryFirewallAudienceLabel(
      page.firewall,
    );
    return PanelSectionBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            page.title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              PanelBadge(label: _contactLabel(page.kind)),
              PanelBadge(label: controller.memoryFirewallLabel(page.firewall)),
              if (firewallAudience.isNotEmpty)
                PanelBadge(label: 'Shared with $firewallAudience'),
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
