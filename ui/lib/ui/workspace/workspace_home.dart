/// Home workspace shell widget.
part of 'workspace_widgets.dart';

/// HomeWorkspace renders the default Today workspace surface.
class HomeWorkspace extends StatelessWidget {
  /// Creates the Today workspace bound to app state.
  const HomeWorkspace({
    super.key,
    required this.controller,
    this.onOpenSection,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Opens a top-level workspace from hero and path actions.
  final ValueChanged<String>? onOpenSection;

  /// Builds the Today assistant workspace.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _HeroPanel(onOpenSection: onOpenSection),
          const SizedBox(height: 28),
          Text(
            'Choose your path',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          _PathGrid(onOpenSection: onOpenSection),
          const SizedBox(height: 34),
          Text(
            'Live Workspace',
            style: TextStyle(
              color: colors.ink,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            controller.statusMessage,
            style: TextStyle(color: colors.muted, fontSize: 17),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final hasTasks = controller.executionSteps.isNotEmpty;
              final chatColumn = controller.messages.isEmpty
                  ? const PanelEmptyBlock(label: 'No live chat messages')
                  : Column(
                      children: <Widget>[
                        for (final message in controller.messages)
                          ChatRow(message: message),
                      ],
                    );
              if (!hasTasks) {
                return chatColumn;
              }
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ExecutionPlan(tasks: controller.executionSteps),
                    const SizedBox(height: 32),
                    chatColumn,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 300,
                    child: ExecutionPlan(tasks: controller.executionSteps),
                  ),
                  const SizedBox(width: 36),
                  Expanded(child: chatColumn),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
