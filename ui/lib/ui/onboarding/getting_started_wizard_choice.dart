/// First-run setup method choice widgets.
part of 'getting_started_wizard.dart';

class _ChooseSetupMethod extends StatelessWidget {
  const _ChooseSetupMethod({
    required this.onApiKey,
    required this.onLocalModel,
  });

  final VoidCallback onApiKey;
  final VoidCallback onLocalModel;

  /// Builds the first setup method choice screen.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 36,
          runSpacing: 20,
          children: <Widget>[
            _SetupChoiceCard(
              icon: Icons.cloud_outlined,
              title: 'Use API key',
              detail:
                  'Connect OpenAI, Anthropic, Google, or another supported provider.',
              buttonLabel: 'Connect provider',
              filled: true,
              onPressed: onApiKey,
            ),
            _SetupChoiceCard(
              icon: Icons.desktop_windows_outlined,
              title: 'Run local model',
              detail:
                  "Use a local model endpoint if you don't have an API key.",
              buttonLabel: 'Use local model',
              filled: false,
              onPressed: onLocalModel,
            ),
          ],
        ),
      ],
    );
  }
}

class _SetupChoiceCard extends StatelessWidget {
  const _SetupChoiceCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.buttonLabel,
    required this.filled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String buttonLabel;
  final bool filled;
  final VoidCallback onPressed;

  /// Builds one setup method card.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 430,
      height: 300,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AgentAwesomeColors.surface,
        border: Border.all(color: AgentAwesomeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _LargeCircleIcon(icon: icon),
          const SizedBox(width: 26),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AgentAwesomeColors.muted,
                    fontSize: 16,
                    height: 1.35,
                  ),
                ),
                const Spacer(),
                _SetupButton(
                  label: buttonLabel,
                  icon: Icons.arrow_forward,
                  filled: filled,
                  onPressed: onPressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
