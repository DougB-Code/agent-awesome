/// Workspace shared label widgets.
part of 'workspace_widgets.dart';

class _WorkspaceEyebrow extends StatelessWidget {
  const _WorkspaceEyebrow(this.text, {this.color});

  final String text;
  final Color? color;

  /// Builds a small uppercase label.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Text(
      text,
      style: TextStyle(
        color: color ?? colors.green,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 4,
      ),
    );
  }
}
