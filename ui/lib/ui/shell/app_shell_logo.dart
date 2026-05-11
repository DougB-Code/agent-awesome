/// App shell brand logo and fallback mark widgets.
part of 'app_shell_frame.dart';

/// _AgentAwesomeLogo renders the brand mark and wordmark.
class _AgentAwesomeLogo extends StatelessWidget {
  /// Creates a compact or expanded brand treatment.
  const _AgentAwesomeLogo({required this.compact});

  final bool compact;

  /// Builds the Agent Awesome mark and wordmark.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: compact ? 'Agent Awesome Personal Agent' : '',
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: <Widget>[
          Image.asset(
            'assets/images/agent-awesome-logo.png',
            height: 44,
            width: 44,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) {
              return const _LogoFallbackMark();
            },
          ),
          if (!compact) ...<Widget>[
            const SizedBox(width: 15),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'AGENT',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: 4.96,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'AWESOME',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: 4.96,
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// _LogoFallbackMark keeps the app usable if bundled assets fail to load.
class _LogoFallbackMark extends StatelessWidget {
  /// Creates a compact fallback mark.
  const _LogoFallbackMark();

  /// Builds a simple fallback mark for tests and asset failures.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final gradient = context.agentAwesomePrimaryGradient;
    return Container(
      height: 58,
      width: 58,
      decoration: BoxDecoration(
        color: gradient == null ? colors.green : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text(
          'AA',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
