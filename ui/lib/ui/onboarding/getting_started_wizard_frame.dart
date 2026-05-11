/// First-run setup frame and stepper widgets.
part of 'getting_started_wizard.dart';

class _SetupFrame extends StatelessWidget {
  const _SetupFrame({required this.child});

  final Widget child;

  /// Builds the bordered setup frame.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(36, 36, 36, 24),
      decoration: BoxDecoration(
        color: AgentAwesomeColors.surface,
        border: Border.all(color: AgentAwesomeColors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0a453421),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SetupStepper extends StatelessWidget {
  const _SetupStepper({required this.step});

  final _SetupStep step;

  /// Builds the four-step setup progress indicator.
  @override
  Widget build(BuildContext context) {
    final current = step.number;
    const labels = <String>[
      'Choose setup method',
      'Connect model',
      'Verify',
      'Start chat',
    ];
    return Row(
      children: <Widget>[
        for (var index = 0; index < labels.length; index++) ...<Widget>[
          Expanded(
            child: _StepperItem(
              number: index + 1,
              label: labels[index],
              active: current == index + 1,
              complete: current > index + 1,
            ),
          ),
          if (index < labels.length - 1)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.only(bottom: 28),
                color: current > index + 1
                    ? AgentAwesomeColors.green
                    : AgentAwesomeColors.border,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepperItem extends StatelessWidget {
  const _StepperItem({
    required this.number,
    required this.label,
    required this.active,
    required this.complete,
  });

  final int number;
  final String label;
  final bool active;
  final bool complete;

  /// Builds one step marker.
  @override
  Widget build(BuildContext context) {
    final color = active || complete
        ? AgentAwesomeColors.green
        : AgentAwesomeColors.muted;
    return Column(
      children: <Widget>[
        Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active || complete
                ? AgentAwesomeColors.green
                : Colors.transparent,
            border: Border.all(
              color: active || complete
                  ? AgentAwesomeColors.green
                  : AgentAwesomeColors.border,
            ),
          ),
          child: Center(
            child: complete
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    number.toString(),
                    style: TextStyle(
                      color: active ? Colors.white : AgentAwesomeColors.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
