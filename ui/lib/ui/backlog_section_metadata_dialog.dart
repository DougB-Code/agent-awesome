/// Backlog task metadata editing dialog.
part of 'backlog_section.dart';

Future<void> _showTaskMetadataDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskMetadataDialog(controller: controller, task: task);
    },
  );
}

class _TaskMetadataDialog extends StatefulWidget {
  const _TaskMetadataDialog({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  @override
  State<_TaskMetadataDialog> createState() => _TaskMetadataDialogState();
}

class _TaskMetadataDialogState extends State<_TaskMetadataDialog> {
  final TextEditingController _estimate = TextEditingController();
  final TextEditingController _energy = TextEditingController();
  final TextEditingController _context = TextEditingController();
  final TextEditingController _domain = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _owner = TextEditingController();
  final TextEditingController _source = TextEditingController();
  final TextEditingController _effort = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _urgency = TextEditingController();
  final TextEditingController _risk = TextEditingController();
  final TextEditingController _confidence = TextEditingController();
  String _message = '';

  /// Initializes metadata fields from the selected backlog item.
  @override
  void initState() {
    super.initState();
    _estimate.text = widget.task.estimateMinutes <= 0
        ? ''
        : widget.task.estimateMinutes.toString();
    _energy.text = widget.task.energyRequired;
    _context.text = widget.task.context;
    _domain.text = widget.task.domain;
    _location.text = widget.task.location;
    _owner.text = widget.task.owner;
    _source.text = widget.task.source;
    _effort.text = _scoreInputText(widget.task.effort);
    _value.text = _scoreInputText(widget.task.value);
    _urgency.text = _scoreInputText(widget.task.urgency);
    _risk.text = _scoreInputText(widget.task.risk);
    _confidence.text = _scoreInputText(widget.task.confidence);
  }

  /// Cleans up metadata field controllers.
  @override
  void dispose() {
    _estimate.dispose();
    _energy.dispose();
    _context.dispose();
    _domain.dispose();
    _location.dispose();
    _owner.dispose();
    _source.dispose();
    _effort.dispose();
    _value.dispose();
    _urgency.dispose();
    _risk.dispose();
    _confidence.dispose();
    super.dispose();
  }

  /// Builds the metadata editing dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Graph Metadata'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _TaskTextField(
                controller: _estimate,
                label: 'Estimate minutes',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _TaskTextField(controller: _energy, label: 'Energy'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _context, label: 'Context'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _domain, label: 'View'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _location, label: 'Location'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _owner, label: 'Person'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _source, label: 'Source'),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TaskTextField(
                      controller: _effort,
                      label: 'Effort 0-1',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TaskTextField(
                      controller: _value,
                      label: 'Value 0-1',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TaskTextField(
                      controller: _urgency,
                      label: 'Urgency 0-1',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TaskTextField(
                      controller: _risk,
                      label: 'Risk 0-1',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _confidence,
                label: 'Confidence 0-1',
                keyboardType: TextInputType.number,
              ),
              if (_message.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _message,
                  style: const TextStyle(color: AgentAwesomeColors.coral),
                ),
              ],
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

  /// Saves the edited metadata through graph-backed task tools.
  Future<void> _save() async {
    final estimateText = _estimate.text.trim();
    final estimate = estimateText.isEmpty ? 0 : int.tryParse(estimateText);
    if (estimate == null || estimate < 0) {
      setState(() => _message = 'Estimate must be zero or greater');
      return;
    }
    final effort = _parseDialogScore(_effort.text);
    final value = _parseDialogScore(_value.text);
    final urgency = _parseDialogScore(_urgency.text);
    final risk = _parseDialogScore(_risk.text);
    final confidence = _parseDialogScore(_confidence.text);
    if (<double?>[effort, value, urgency, risk, confidence].contains(null)) {
      setState(() => _message = 'Scores must be between 0 and 1');
      return;
    }
    await widget.controller.updateTaskFromUi(
      taskId: widget.task.id,
      estimateMinutes: estimate,
      energyRequired: _energy.text.trim(),
      effort: effort,
      value: value,
      urgency: urgency,
      risk: risk,
      context: _context.text.trim(),
      domain: _domain.text.trim(),
      location: _location.text.trim(),
      owner: _owner.text.trim(),
      source: _source.text.trim(),
      confidence: confidence,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
