/// Backlog task commitment creation and editing dialog.
part of 'backlog_section.dart';

/// Shows the commitment create or edit dialog.
Future<void> _showTaskCommitmentDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  WorkspaceTask task, {
  TaskCommitment? commitment,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskCommitmentDialog(
        controller: controller,
        task: task,
        commitment: commitment,
      );
    },
  );
}

class _TaskCommitmentDialog extends StatefulWidget {
  const _TaskCommitmentDialog({
    required this.controller,
    required this.task,
    this.commitment,
  });

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;
  final TaskCommitment? commitment;

  @override
  State<_TaskCommitmentDialog> createState() => _TaskCommitmentDialogState();
}

class _TaskCommitmentDialogState extends State<_TaskCommitmentDialog> {
  final TextEditingController _people = TextEditingController();
  final TextEditingController _domain = TextEditingController();
  final TextEditingController _project = TextEditingController();
  final TextEditingController _timeWindow = TextEditingController();
  final TextEditingController _responsibility = TextEditingController();
  final TextEditingController _promiseSource = TextEditingController();
  final TextEditingController _hardness = TextEditingController();
  final TextEditingController _consequence = TextEditingController();

  /// Initializes commitment fields from the existing commitment when present.
  @override
  void initState() {
    super.initState();
    final commitment = widget.commitment;
    if (commitment == null) {
      _domain.text = widget.task.domain;
      _project.text = widget.task.context;
      _people.text = widget.task.owner;
      return;
    }
    _people.text = commitment.people.join(', ');
    _domain.text = commitment.domain;
    _project.text = commitment.project;
    _timeWindow.text = commitment.timeWindow;
    _responsibility.text = commitment.responsibility;
    _promiseSource.text = commitment.promiseSource;
    _hardness.text = commitment.hardness;
    _consequence.text = commitment.consequence;
  }

  /// Cleans up commitment field controllers.
  @override
  void dispose() {
    _people.dispose();
    _domain.dispose();
    _project.dispose();
    _timeWindow.dispose();
    _responsibility.dispose();
    _promiseSource.dispose();
    _hardness.dispose();
    _consequence.dispose();
    super.dispose();
  }

  /// Builds the commitment create or edit dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.commitment == null ? 'Add Commitment' : 'Edit Commitment',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _TaskTextField(controller: _people, label: 'People'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _domain, label: 'View'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _project, label: 'Project'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _timeWindow, label: 'Time window'),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _responsibility,
                label: 'Responsibility',
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _promiseSource,
                label: 'Promise source',
              ),
              const SizedBox(height: 10),
              _TaskTextField(controller: _hardness, label: 'Hardness'),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _consequence,
                label: 'Consequence',
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  /// Saves the commitment through graph-backed task tools.
  Future<void> _save() async {
    await widget.controller.upsertTaskCommitmentFromUi(
      commitmentId: widget.commitment?.id ?? '',
      taskId: widget.task.id,
      people: splitCommaSeparatedValues(_people.text),
      domain: _domain.text.trim(),
      project: _project.text.trim(),
      timeWindow: _timeWindow.text.trim(),
      responsibility: _responsibility.text.trim(),
      promiseSource: _promiseSource.text.trim(),
      hardness: _hardness.text.trim(),
      consequence: _consequence.text.trim(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
