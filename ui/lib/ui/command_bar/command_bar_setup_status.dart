/// Global command bar setup status action widget.
part of 'command_bar.dart';

class _SetupStatusButton extends StatelessWidget {
  /// Creates the setup status action.
  const _SetupStatusButton({required this.onTap});

  /// Opens the setup wizard.
  final VoidCallback onTap;

  /// Builds a prominent setup status action for incomplete model setup.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Tooltip(
      message: 'Finish setup',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 42,
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: colors.warningSoft,
            border: Border.all(color: colors.warningBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, color: colors.warningText, size: 18),
              const SizedBox(width: 7),
              Text(
                'Setup incomplete',
                style: TextStyle(
                  color: colors.warningText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
