/// Backlog task work-breakdown editing dialog.
part of 'backlog_section.dart';

/// Shows the WBS editing dialog.
Future<void> _showTaskWbsDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskWbsDialog(controller: controller, task: task);
    },
  );
}

class _TaskWbsDialog extends StatefulWidget {
  const _TaskWbsDialog({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  @override
  State<_TaskWbsDialog> createState() => _TaskWbsDialogState();
}

class _TaskWbsDialogState extends State<_TaskWbsDialog> {
  static const Duration _saveDelay = Duration(milliseconds: 500);

  final TextEditingController _code = TextEditingController();
  final TextEditingController _deliverable = TextEditingController();
  final TextEditingController _startCriteria = TextEditingController();
  final TextEditingController _acceptanceCriteria = TextEditingController();
  final TextEditingController _requirementRefs = TextEditingController();
  final TextEditingController _rubricRefs = TextEditingController();
  final TextEditingController _resources = TextEditingController();
  final TextEditingController _estimatedCost = TextEditingController();
  final TextEditingController _costCurrency = TextEditingController();
  Timer? _saveTimer;
  String _message = '';
  String _lastSavedFingerprint = '';

  /// Initializes WBS fields from the selected task.
  @override
  void initState() {
    super.initState();
    _code.addListener(_scheduleSave);
    _deliverable.addListener(_scheduleSave);
    _startCriteria.addListener(_scheduleSave);
    _acceptanceCriteria.addListener(_scheduleSave);
    _requirementRefs.addListener(_scheduleSave);
    _rubricRefs.addListener(_scheduleSave);
    _resources.addListener(_scheduleSave);
    _estimatedCost.addListener(_scheduleSave);
    _costCurrency.addListener(_scheduleSave);
    final workBreakdown = widget.task.workBreakdown;
    _code.text = workBreakdown.code;
    _deliverable.text = workBreakdown.deliverable;
    _startCriteria.text = workBreakdown.startCriteria.join('\n');
    _acceptanceCriteria.text = workBreakdown.acceptanceCriteria.join('\n');
    _requirementRefs.text = workBreakdown.requirementRefs.join('\n');
    _rubricRefs.text = workBreakdown.rubricRefs.join('\n');
    _resources.text = workBreakdown.resources
        .map(taskResourceRequirementLine)
        .join('\n');
    _estimatedCost.text = workBreakdown.estimatedCostCents <= 0
        ? ''
        : workBreakdown.estimatedCostCents.toString();
    _costCurrency.text = workBreakdown.costCurrency;
    _lastSavedFingerprint = _fingerprint();
  }

  /// Cleans up WBS field controllers.
  @override
  void dispose() {
    _saveTimer?.cancel();
    _code.removeListener(_scheduleSave);
    _deliverable.removeListener(_scheduleSave);
    _startCriteria.removeListener(_scheduleSave);
    _acceptanceCriteria.removeListener(_scheduleSave);
    _requirementRefs.removeListener(_scheduleSave);
    _rubricRefs.removeListener(_scheduleSave);
    _resources.removeListener(_scheduleSave);
    _estimatedCost.removeListener(_scheduleSave);
    _costCurrency.removeListener(_scheduleSave);
    _code.dispose();
    _deliverable.dispose();
    _startCriteria.dispose();
    _acceptanceCriteria.dispose();
    _requirementRefs.dispose();
    _rubricRefs.dispose();
    _resources.dispose();
    _estimatedCost.dispose();
    _costCurrency.dispose();
    super.dispose();
  }

  /// Builds the WBS editing dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit WBS'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TaskTextField(controller: _code, label: 'Code'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TaskTextField(
                      controller: _costCurrency,
                      label: 'Currency',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _deliverable,
                label: 'Deliverable',
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _estimatedCost,
                label: 'Spend cents',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _startCriteria,
                label: 'Start criteria',
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _acceptanceCriteria,
                label: 'Done criteria',
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _requirementRefs,
                label: 'Requirement refs',
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _rubricRefs,
                label: 'Rubric refs',
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _resources,
                label: 'Resources',
                maxLines: 5,
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
          child: const Text('Close'),
        ),
      ],
    );
  }

  /// Saves the edited WBS metadata through graph-backed task tools.
  Future<void> _save() async {
    _saveTimer?.cancel();
    if (widget.controller.tasksBusy) {
      _scheduleSave();
      return;
    }
    final fingerprint = _fingerprint();
    if (fingerprint == _lastSavedFingerprint) {
      return;
    }
    final costText = _estimatedCost.text.trim();
    final cost = costText.isEmpty ? 0 : int.tryParse(costText);
    if (cost == null || cost < 0) {
      setState(() => _message = 'Spend must be zero or greater');
      return;
    }
    final resources = parseTaskResourceRequirementLines(_resources.text);
    if (resources == null) {
      setState(() => _message = 'Resource quantities and spend must be valid');
      return;
    }
    _lastSavedFingerprint = fingerprint;
    await widget.controller.updateTaskFromUi(
      taskId: widget.task.id,
      workBreakdown: TaskWorkBreakdown(
        code: _code.text.trim(),
        deliverable: _deliverable.text.trim(),
        startCriteria: splitWbsLines(_startCriteria.text),
        acceptanceCriteria: splitWbsLines(_acceptanceCriteria.text),
        requirementRefs: splitWbsLines(_requirementRefs.text),
        rubricRefs: splitWbsLines(_rubricRefs.text),
        resources: resources,
        estimatedCostCents: cost,
        costCurrency: _costCurrency.text.trim(),
      ),
    );
    if (mounted) {
      setState(() => _message = '');
    }
  }

  /// Schedules one WBS save after a short edit pause.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_save()));
  }

  /// Returns a stable comparison key for persisted WBS fields.
  String _fingerprint() {
    return jsonEncode(<String, Object?>{
      'code': _code.text.trim(),
      'deliverable': _deliverable.text.trim(),
      'startCriteria': _startCriteria.text.trim(),
      'acceptanceCriteria': _acceptanceCriteria.text.trim(),
      'requirementRefs': _requirementRefs.text.trim(),
      'rubricRefs': _rubricRefs.text.trim(),
      'resources': _resources.text.trim(),
      'estimatedCost': _estimatedCost.text.trim(),
      'costCurrency': _costCurrency.text.trim(),
    });
  }
}
