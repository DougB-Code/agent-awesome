/// Home workspace hero copy and action widgets.
part of 'workspace_widgets.dart';

/// _HeroPanel renders the screenshot-inspired welcome surface.
class _HeroPanel extends StatelessWidget {
  /// Creates the home hero panel.
  const _HeroPanel({required this.onOpenSection});

  /// Opens app sections from hero calls to action.
  final ValueChanged<String>? onOpenSection;

  /// Builds the bordered hero with copy and system diagram.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 430),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.shadow,
            blurRadius: 38,
            offset: Offset(0, 20),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[colors.surface, colors.heroEnd],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final copy = _HeroCopy(compact: !wide, onOpenSection: onOpenSection);
          final diagram = _AgentSystemDiagram(compact: !wide);
          if (!wide) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  copy,
                  const SizedBox(height: 28),
                  SizedBox(height: 320, child: diagram),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(74, 58, 52, 48),
            child: Row(
              children: <Widget>[
                Expanded(flex: 7, child: copy),
                const SizedBox(width: 36),
                Expanded(flex: 6, child: diagram),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// _HeroCopy renders the primary welcome headline and actions.
class _HeroCopy extends StatelessWidget {
  /// Creates the hero copy block.
  const _HeroCopy({required this.compact, required this.onOpenSection});

  /// Whether to use a smaller type scale.
  final bool compact;

  /// Opens app sections from hero actions.
  final ValueChanged<String>? onOpenSection;

  /// Builds the hero text and buttons.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _WorkspaceEyebrow('AGENT AWESOME AI', color: colors.coral),
        const SizedBox(height: 22),
        Text(
          'Design and\nrun your AI\nagent system',
          style: Theme.of(
            context,
          ).textTheme.displayLarge?.copyWith(fontSize: compact ? 48 : 72),
        ),
        const SizedBox(height: 26),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 610),
          child: Text(
            'Agent Awesome gives you everything you need to build, run, and ship reliable AI agents with the models, tools, memory, workflows, and deployment paths you control.',
            style: TextStyle(
              color: colors.muted,
              fontSize: 24,
              height: 1.5,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(height: 34),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: <Widget>[
            _HeroActionButton(
              label: 'Start Building',
              primary: true,
              compact: compact,
              onPressed: onOpenSection == null
                  ? null
                  : () => onOpenSection!(AppSections.chat),
            ),
            _HeroActionButton(
              label: 'Open Backlog',
              primary: false,
              compact: compact,
              onPressed: onOpenSection == null
                  ? null
                  : () => onOpenSection!(AppSections.backlog),
            ),
          ],
        ),
      ],
    );
  }
}

/// _HeroActionButton renders one hero call to action.
class _HeroActionButton extends StatelessWidget {
  /// Creates a hero action button.
  const _HeroActionButton({
    required this.label,
    required this.primary,
    required this.compact,
    required this.onPressed,
  });

  /// Visible button label.
  final String label;

  /// Whether the button uses the coral treatment.
  final bool primary;

  /// Whether the button needs compact padding and text treatment.
  final bool compact;

  /// Action callback.
  final VoidCallback? onPressed;

  /// Builds the hero action.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final style = primary
        ? FilledButton.styleFrom(
            backgroundColor: colors.coral,
            foregroundColor: Colors.white,
            disabledBackgroundColor: colors.coral,
            disabledForegroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 24,
              vertical: compact ? 14 : 18,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: colors.ink,
            disabledForegroundColor: colors.ink,
            side: BorderSide(color: colors.border),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 24,
              vertical: compact ? 14 : 18,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          );
    final child = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 230 : 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          if (!compact) ...const <Widget>[
            SizedBox(width: 14),
            Icon(Icons.arrow_forward, size: 18),
          ],
        ],
      ),
    );
    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}
