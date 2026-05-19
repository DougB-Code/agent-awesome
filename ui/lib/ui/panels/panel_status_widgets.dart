/// Shared panel labels, badges, status rows, and chat panels.
part of 'panels.dart';

/// PanelContentSectionStyle selects the shared content-section treatment.
enum PanelContentSectionStyle {
  /// Plain sections use pane spacing without a gradient card or section border.
  plain,

  /// Gradient sections use the shared card gradient and section border.
  gradient,
}

/// PanelSectionBlock renders shared plain or gradient content sections.
class PanelSectionBlock extends StatelessWidget {
  /// Creates a reusable gradient section block.
  const PanelSectionBlock({
    super.key,
    required this.child,
    this.title = '',
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    this.style = PanelContentSectionStyle.gradient,
  });

  /// Creates a pane-native section without a gradient background or border.
  const PanelSectionBlock.plain({
    super.key,
    required this.child,
    this.title = '',
    this.trailing,
    this.padding = EdgeInsets.zero,
  }) : style = PanelContentSectionStyle.plain;

  /// Creates a card-like section with the shared gradient background and border.
  const PanelSectionBlock.gradient({
    super.key,
    required this.child,
    this.title = '',
    this.trailing,
    this.padding = const EdgeInsets.all(14),
  }) : style = PanelContentSectionStyle.gradient;

  /// Content shown inside the block.
  final Widget child;

  /// Optional uppercase title shown above the section content.
  final String title;

  /// Optional action or status widget aligned with the section title.
  final Widget? trailing;

  /// Inner spacing around the block content.
  final EdgeInsetsGeometry padding;

  /// Visual treatment for the section.
  final PanelContentSectionStyle style;

  /// Builds the shared section layout.
  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    return switch (style) {
      PanelContentSectionStyle.plain => Padding(
        padding: padding,
        child: content,
      ),
      PanelContentSectionStyle.gradient => PanelSurface(
        fillWidth: true,
        padding: padding,
        style: PanelSurfaceStyle.card,
        child: content,
      ),
    };
  }

  /// Builds the title row and section child.
  Widget _buildContent() {
    final titleText = title.trim();
    if (titleText.isEmpty && trailing == null) {
      return child;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PanelSectionHeader(title: titleText, trailing: trailing),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// _PanelSectionHeader renders the optional section title and action row.
class _PanelSectionHeader extends StatelessWidget {
  /// Creates a shared content-section header.
  const _PanelSectionHeader({required this.title, required this.trailing});

  /// Uppercase section title.
  final String title;

  /// Optional widget aligned to the trailing edge.
  final Widget? trailing;

  /// Builds the shared header row.
  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;
    if (trailingWidget == null) {
      return PanelSectionLabel(title);
    }
    return Row(
      children: <Widget>[
        if (title.isEmpty)
          const Spacer()
        else
          Expanded(child: PanelSectionLabel(title)),
        trailingWidget,
      ],
    );
  }
}

/// PanelSectionLabel renders a compact uppercase section label.
class PanelSectionLabel extends StatelessWidget {
  /// Creates a reusable uppercase section label.
  const PanelSectionLabel(this.label, {super.key, this.onTap});

  final String label;

  /// Optional title activation callback.
  final VoidCallback? onTap;

  /// Builds the uppercase label shared by panel section cards.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final text = Text(
      label.toUpperCase(),
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
    if (onTap == null) {
      return text;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: text,
      ),
    );
  }
}

/// PanelBadge renders a compact metadata/status badge.
class PanelBadge extends StatelessWidget {
  /// Creates a reusable status badge.
  const PanelBadge({super.key, required this.label});

  /// Badge text.
  final String label;

  /// Builds a dense bordered badge.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// PanelFilterChip renders a shared selectable content-level filter chip.
class PanelFilterChip extends StatelessWidget {
  /// Creates one reusable panel filter chip.
  const PanelFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  /// Chip label.
  final String label;

  /// Whether this filter is currently active.
  final bool selected;

  /// Handles selection changes.
  final ValueChanged<bool> onSelected;

  /// Builds a quiet selectable chip for content-level filters.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return FilterChip(
      label: Text(label, overflow: TextOverflow.ellipsis),
      selected: selected,
      showCheckmark: true,
      backgroundColor: colors.surface,
      selectedColor: colors.panelStrong,
      checkmarkColor: colors.green,
      side: BorderSide(color: selected ? colors.borderStrong : colors.border),
      labelStyle: TextStyle(
        color: selected ? colors.ink : colors.muted,
        fontWeight: FontWeight.w700,
      ),
      onSelected: onSelected,
    );
  }
}

/// PanelRemovableChip renders a shared selected-filter chip with removal.
class PanelRemovableChip extends StatelessWidget {
  /// Creates one removable panel chip.
  const PanelRemovableChip({
    super.key,
    required this.label,
    required this.onDeleted,
  });

  /// Chip label.
  final String label;

  /// Removes this chip.
  final VoidCallback onDeleted;

  /// Builds a quiet removable chip for active filters.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return InputChip(
      label: Text(label, overflow: TextOverflow.ellipsis),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close, size: 16),
      backgroundColor: colors.panel,
      side: BorderSide(color: colors.border),
      labelStyle: TextStyle(color: colors.muted, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PanelStyleTokens.compactRadius),
      ),
    );
  }
}

/// PanelEmptyBlock renders a bordered empty state block.
class PanelEmptyBlock extends StatelessWidget {
  /// Creates a reusable empty state block.
  const PanelEmptyBlock({super.key, required this.label});

  /// Empty-state text.
  final String label;

  /// Builds a compact bordered empty block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelSurface(
      fillWidth: true,
      padding: const EdgeInsets.all(14),
      style: PanelSurfaceStyle.card,
      showBorder: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: SelectableText(label, style: TextStyle(color: colors.muted)),
        ),
      ),
    );
  }
}

/// StatusRow renders one service/process status line.
class StatusRow extends StatelessWidget {
  /// Creates a reusable status row.
  const StatusRow({
    super.key,
    required this.name,
    required this.url,
    required this.state,
    required this.message,
  });

  /// Status subject name.
  final String name;

  /// Endpoint or path detail.
  final String url;

  /// Current connection state.
  final ConnectionStateKind state;

  /// Supporting status message.
  final String message;

  /// Builds one reusable connection status row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final color = switch (state) {
      ConnectionStateKind.connected => colors.green,
      ConnectionStateKind.disconnected => colors.coral,
      ConnectionStateKind.unknown => colors.muted,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(Icons.circle, size: 12, color: color),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 160,
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(child: Text(url, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: SelectableText(
              message,
              style: TextStyle(color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// ChatPanel renders chat timeline content in a section panel.
class ChatPanel extends StatelessWidget {
  /// Creates a chat panel body.
  const ChatPanel({
    super.key,
    required this.children,
    required this.empty,
    this.controller,
    this.compact = false,
  });

  /// Timeline children.
  final List<Widget> children;

  /// Empty state widget.
  final Widget empty;

  /// Optional scroll controller for callers that manage timeline position.
  final ScrollController? controller;

  /// Whether the panel is rendering in a narrow auxiliary chat pane.
  final bool compact;

  /// Builds the chat panel.
  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return empty;
    }
    return ListView(
      controller: controller,
      padding: compact
          ? const EdgeInsets.fromLTRB(18, 16, 18, 22)
          : const EdgeInsets.fromLTRB(22, 20, 22, 28),
      children: children,
    );
  }
}
