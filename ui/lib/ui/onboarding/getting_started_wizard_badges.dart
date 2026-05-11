/// First-run setup decorative badge widgets.
part of 'getting_started_wizard.dart';

class _LargeCircleIcon extends StatelessWidget {
  const _LargeCircleIcon({
    required this.icon,
    this.size = 72,
    this.warning = false,
  });

  final IconData icon;
  final double size;
  final bool warning;

  /// Builds a round icon marker.
  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: warning
            ? const Color(0xffffead6)
            : AgentAwesomeColors.greenSoft.withValues(alpha: 0.82),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: warning ? const Color(0xffb85d00) : AgentAwesomeColors.green,
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.label);

  final String label;

  /// Builds a small recommendation badge.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AgentAwesomeColors.greenSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AgentAwesomeColors.green,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SetupEyebrow extends StatelessWidget {
  const _SetupEyebrow(this.text);

  final String text;

  /// Builds the setup eyebrow label.
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AgentAwesomeColors.coral,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 6,
      ),
    );
  }
}

/// Returns the shared first-run setup input decoration.
InputDecoration _setupInputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AgentAwesomeColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AgentAwesomeColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AgentAwesomeColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AgentAwesomeColors.green),
    ),
  );
}
