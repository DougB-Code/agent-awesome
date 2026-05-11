/// Backlog task metadata, relation, commitment, and creation dialogs.
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
  final TextEditingController _code = TextEditingController();
  final TextEditingController _deliverable = TextEditingController();
  final TextEditingController _startCriteria = TextEditingController();
  final TextEditingController _acceptanceCriteria = TextEditingController();
  final TextEditingController _requirementRefs = TextEditingController();
  final TextEditingController _rubricRefs = TextEditingController();
  final TextEditingController _resources = TextEditingController();
  final TextEditingController _estimatedCost = TextEditingController();
  final TextEditingController _costCurrency = TextEditingController();
  String _message = '';

  /// Initializes WBS fields from the selected task.
  @override
  void initState() {
    super.initState();
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
  }

  /// Cleans up WBS field controllers.
  @override
  void dispose() {
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
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  /// Saves the edited WBS metadata through graph-backed task tools.
  Future<void> _save() async {
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
      Navigator.of(context).pop();
    }
  }
}

/// Shows the backlog relation creation dialog.
Future<void> _showTaskRelationDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskRelationDialog(controller: controller, task: task);
    },
  );
}

class _TaskRelationDialog extends StatefulWidget {
  const _TaskRelationDialog({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  @override
  State<_TaskRelationDialog> createState() => _TaskRelationDialogState();
}

class _TaskRelationDialogState extends State<_TaskRelationDialog> {
  final TextEditingController _explanation = TextEditingController();
  String _targetTaskId = '';
  String _relationType = 'related_to';

  /// Initializes the first available target backlog item.
  @override
  void initState() {
    super.initState();
    final targets = _relationTargets;
    if (targets.isNotEmpty) {
      _targetTaskId = targets.first.id;
    }
  }

  /// Cleans up dialog controllers.
  @override
  void dispose() {
    _explanation.dispose();
    super.dispose();
  }

  List<WorkspaceTask> get _relationTargets {
    return widget.controller.workspace.tasks.where((task) {
      return task.id != widget.task.id;
    }).toList();
  }

  /// Builds the backlog relation creation dialog.
  @override
  Widget build(BuildContext context) {
    final targets = _relationTargets;
    return AlertDialog(
      title: const Text('Add Relation'),
      content: SizedBox(
        width: 460,
        child: targets.isEmpty
            ? const Text(
                'Create another backlog item before adding a relation.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _targetTaskId.isEmpty ? null : _targetTaskId,
                    decoration: _taskDialogDecoration(
                      context,
                      'Related backlog item',
                    ),
                    isExpanded: true,
                    items: <DropdownMenuItem<String>>[
                      for (final target in targets)
                        DropdownMenuItem<String>(
                          value: target.id,
                          child: Text(
                            target.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _targetTaskId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _TaskDropdown(
                    value: _relationType,
                    values: _taskRelationTypes,
                    tooltip: 'Relation type',
                    onChanged: (value) => setState(() => _relationType = value),
                  ),
                  const SizedBox(height: 10),
                  _TaskTextField(
                    controller: _explanation,
                    label: 'Explanation',
                    maxLines: 3,
                  ),
                ],
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: targets.isEmpty ? null : _save,
          child: const Text('Add'),
        ),
      ],
    );
  }

  /// Saves the explicit relation through graph-backed context tools.
  Future<void> _save() async {
    if (_targetTaskId.isEmpty) {
      return;
    }
    await widget.controller.upsertTaskRelationFromUi(
      fromTaskId: widget.task.id,
      toTaskId: _targetTaskId,
      relationType: _relationType,
      explanation: _explanation.text.trim(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

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

/// Shows the context creation dialog.
Future<void> _showTaskCreateDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskCreateDialog(controller: controller);
    },
  );
}

class _TaskCreateDialog extends StatefulWidget {
  const _TaskCreateDialog({required this.controller});

  final AgentAwesomeAppController controller;

  @override
  State<_TaskCreateDialog> createState() => _TaskCreateDialogState();
}

class _TaskCreateDialogState extends State<_TaskCreateDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  String _priority = 'normal';
  bool _linkMemory = false;

  /// Cleans up dialog controllers.
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _topics.dispose();
    super.dispose();
  }

  /// Builds the context creation dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Backlog Item'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _TaskTextField(controller: _title, label: 'Title'),
            const SizedBox(height: 10),
            _TaskTextField(
              controller: _description,
              label: 'Description',
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            _TaskDropdown(
              value: _priority,
              values: _taskPriorities,
              tooltip: 'Priority',
              onChanged: (value) => setState(() => _priority = value),
            ),
            const SizedBox(height: 10),
            _TaskTextField(controller: _topics, label: 'Topics'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Link selected memory'),
              value: _linkMemory,
              onChanged: widget.controller.selectedMemory == null
                  ? null
                  : (value) => setState(() => _linkMemory = value ?? false),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }

  /// Creates the dialog backlog item.
  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      return;
    }
    await widget.controller.createTaskFromUi(
      title,
      description: _description.text.trim(),
      priority: _priority,
      topics: splitCommaSeparatedValues(_topics.text),
      linkSelectedMemory: _linkMemory,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Confirms a context write operation.
Future<bool> _confirmTaskWrite(BuildContext context, String message) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Confirm Change'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );
  return approved ?? false;
}

/// Returns whether a backlog item matches a panel query.
bool _matchesTask(WorkspaceTask task, String query) {
  return _matchesText(
    '${task.title} ${task.description} ${task.status} ${task.priority} '
    '${task.sourceLabel} ${task.topics.join(' ')}',
    query,
  );
}

/// Returns graph task ids for the active Queue insight preset.
Set<String> _queuePresetTaskIds(AgentAwesomeAppController controller) {
  final presetId = controller.taskInsightPresetId;
  if (presetId == TaskInsightIds.all) {
    return const <String>{};
  }
  return controller.taskInsightIndex
      .tasksForInsight(presetId)
      .map((candidate) => candidate.taskId)
      .toSet();
}

/// Returns compact insight badges for one queue backlog item.
List<String> _insightBadgesForTask(
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) {
  final taskId = task.id;
  final badges = <String>[];
  if (controller.taskInsightIndex.candidateForTask(
        taskId,
        TaskInsightIds.agentHandoff,
      ) !=
      null) {
    final score = controller.taskInsightIndex.scoresFor(taskId);
    badges.add(
      (score?.agentSafety ?? 0) >=
              controller.taskInsightIndex.policy.safeAgentThreshold
          ? 'Agent-ready'
          : 'Needs review',
    );
  }
  final downstream = controller.taskInsightIndex.downstreamTasksFor(taskId);
  if (downstream.isNotEmpty) {
    badges.add('Blocks ${downstream.length}');
  }
  final gaps = controller.taskInsightIndex.metadataGapsFor(taskId);
  if (gaps.isNotEmpty) {
    badges.add('Missing ${gaps.first.field.replaceAll('_', ' ')}');
  }
  return badges.take(3).toList();
}

/// Returns the local date used by queue quick actions.
DateTime _todayDate() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Returns the task card accent color from the displayed score band.
Color _taskQueueAccentColor(BuildContext context, WorkspaceTask task) {
  return _taskQueueScoreColor(context, _taskQueueScore(task));
}

/// Returns a compact task description for queue cards.
String _taskQueueDescription(WorkspaceTask task) {
  if (task.description.trim().isNotEmpty) {
    return task.description.trim();
  }
  if (task.detail.trim().isNotEmpty) {
    return task.detail.trim();
  }
  if (task.dueAt == null && task.scheduledAt == null) {
    return 'No date is attached yet.';
  }
  return '';
}

/// Returns the suggested next action for a queue card.
String _taskSuggestedAction(WorkspaceTask task) {
  if (task.done) {
    return 'Already complete';
  }
  if (task.status == 'blocked') {
    return 'Clarify the blocker';
  }
  if (task.status == 'waiting') {
    return 'Follow up or snooze';
  }
  if (task.scheduledAt == null) {
    return 'Schedule for today';
  }
  return 'Mark done when finished';
}

/// Returns the action category label for a queue card.
String _taskActionTypeLabel(WorkspaceTask task) {
  if (task.status == 'blocked' || task.description.trim().isEmpty) {
    return 'Clarify';
  }
  if (task.scheduledAt == null) {
    return 'Schedule';
  }
  return 'Do';
}

/// Returns the action category icon for a queue card.
IconData _taskActionTypeIcon(WorkspaceTask task) {
  if (task.status == 'blocked' || task.description.trim().isEmpty) {
    return Icons.format_list_bulleted_add;
  }
  if (task.scheduledAt == null) {
    return Icons.calendar_today_outlined;
  }
  return Icons.task_alt_outlined;
}

/// Returns a simple queue priority score for attention-style display.
int _taskQueueScore(WorkspaceTask task) {
  var score = 48;
  if (task.overdue) {
    score += 22;
  }
  if (task.dueAt == null && task.scheduledAt == null) {
    score += 10;
  }
  if (task.priority == 'urgent') {
    score += 22;
  } else if (task.priority == 'high') {
    score += 15;
  } else if (task.priority == 'low') {
    score -= 8;
  }
  if (task.status == 'blocked') {
    score += 12;
  }
  if (task.description.trim().isEmpty) {
    score += 8;
  }
  return score.clamp(0, 99);
}

/// Returns the queue score band label.
String _taskQueueScoreLabel(int score) {
  if (score >= 75) {
    return 'High';
  }
  if (score >= 55) {
    return 'Medium';
  }
  return 'Low';
}

/// Returns the queue score band color.
Color _taskQueueScoreColor(BuildContext context, int score) {
  final colors = context.agentAwesomeColors;
  if (score >= 75) {
    return colors.coral;
  }
  if (score >= 55) {
    return context.agentAwesomeWarningAccent;
  }
  return context.agentAwesomeLowAccent;
}

/// Returns memory links filtered by the panel query.
List<TaskMemoryLink> _filteredLinks(List<TaskMemoryLink> links, String query) {
  return links.where((link) {
    return _matchesText(
      '${link.relationship} ${link.note} ${link.memoryId} '
      '${link.memoryEvidenceId}',
      query,
    );
  }).toList();
}

/// Returns whether text contains every query character in order.
bool _matchesText(String value, String query) {
  final normalizedValue = value.toLowerCase();
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }
  var cursor = 0;
  for (final codeUnit in normalizedQuery.codeUnits) {
    cursor = normalizedValue.indexOf(String.fromCharCode(codeUnit), cursor);
    if (cursor == -1) {
      return false;
    }
    cursor++;
  }
  return true;
}

/// Returns the selected semantic Queue preset, falling back to All.
TaskInsightPreset _selectedTaskInsightPreset(
  AgentAwesomeAppController controller,
) {
  for (final preset in TaskInsightPresetRegistry.queuePresets) {
    if (preset.id == controller.taskInsightPresetId) {
      return preset;
    }
  }
  return TaskInsightPresetRegistry.queuePresets.first;
}

/// Returns a preset label with candidate count when the preset is semantic.
String _presetLabel(
  AgentAwesomeAppController controller,
  TaskInsightPreset preset,
) {
  if (preset.id == TaskInsightIds.all) {
    return preset.label;
  }
  final count = controller.taskInsightIndex.tasksForInsight(preset.id).length;
  return '${preset.label} $count';
}

/// Returns the visible insight dropdown label.
String _presetButtonLabel(
  AgentAwesomeAppController controller,
  TaskInsightPreset preset,
) {
  if (preset.id == TaskInsightIds.all) {
    return preset.label;
  }
  return _presetLabel(controller, preset);
}

/// Reports whether the filter state matches the bundled Active view.
bool _isActiveTaskView(TaskFilterState filters) {
  return _sameFilterValues(filters.statuses, _activeTaskStatuses);
}

/// Returns the visible icon for the bundled task view control.
IconData _taskViewIcon(TaskFilterState filters) {
  if (_isActiveTaskView(filters)) {
    return Icons.playlist_play;
  }
  if (filters.statuses.isEmpty) {
    return Icons.all_inbox_outlined;
  }
  return Icons.tune;
}

/// Returns the visible label for the bundled task view control.
String _taskViewLabel(TaskFilterState filters) {
  if (_isActiveTaskView(filters)) {
    return 'Active tasks';
  }
  if (filters.statuses.isEmpty) {
    return 'All tasks';
  }
  return 'Custom tasks';
}

/// Returns the compact status filter summary.
String _statusFilterLabel(TaskFilterState filters) {
  if (filters.statuses.isEmpty || _isActiveTaskView(filters)) {
    return filters.overdueOnly ? 'Overdue' : 'Status';
  }
  final statusLabel = filters.statuses.length == 1
      ? _taskLabel(filters.statuses.first)
      : 'Status ${filters.statuses.length}';
  return filters.overdueOnly ? '$statusLabel + overdue' : statusLabel;
}

/// Returns the compact priority filter summary.
String _priorityFilterLabel(TaskFilterState filters) {
  if (filters.priorities.isEmpty) {
    return 'Priority';
  }
  if (filters.priorities.length == 1) {
    return _taskLabel(filters.priorities.first);
  }
  return 'Priority ${filters.priorities.length}';
}

/// Returns the compact topic filter summary.
String _topicFilterLabel(TaskFilterState filters) {
  if (filters.topics.isEmpty) {
    return 'Topics';
  }
  if (filters.topics.length == 1) {
    return filters.topics.first;
  }
  return 'Topics ${filters.topics.length}';
}

/// Returns topic filter choices with selected topics kept visible.
List<String> _topicFilterOptions(
  TaskFilterState filters,
  Iterable<String> availableTopics,
) {
  final seen = <String>{};
  final topics = <String>[];
  for (final topic in <String>[
    ...filters.topics,
    ...availableTopics.take(16),
  ]) {
    final trimmed = topic.trim();
    if (trimmed.isNotEmpty && seen.add(trimmed)) {
      topics.add(trimmed);
    }
  }
  return topics;
}

/// Reports whether two filter value lists contain the same values.
bool _sameFilterValues(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  final rightValues = right.toSet();
  return left.every(rightValues.contains);
}

/// Formats a normalized score for inspector display.
String _formatTaskScore(double value) {
  if (value <= 0) {
    return '';
  }
  return '${(value * 100).round()}%';
}

/// Summarizes proposed task metadata fields for the inspector.
String _metadataSuggestionSummary(TaskMetadataSuggestion suggestion) {
  final parts = <String>[
    if (suggestion.estimateMinutes > 0) '${suggestion.estimateMinutes} min',
    if (suggestion.energyRequired.isNotEmpty) suggestion.energyRequired,
    if (suggestion.context.isNotEmpty) suggestion.context,
    if (suggestion.domain.isNotEmpty) suggestion.domain,
    if (suggestion.location.isNotEmpty) suggestion.location,
    if (suggestion.effort > 0) 'effort ${_formatTaskScore(suggestion.effort)}',
    if (suggestion.value > 0) 'value ${_formatTaskScore(suggestion.value)}',
    if (suggestion.urgency > 0)
      'urgency ${_formatTaskScore(suggestion.urgency)}',
    if (suggestion.risk > 0) 'risk ${_formatTaskScore(suggestion.risk)}',
  ];
  if (parts.isEmpty) {
    return suggestion.explanation;
  }
  return parts.join(' • ');
}

/// Summarizes proposed commitment fields for the inspector.
String _commitmentSuggestionSummary(TaskCommitmentSuggestion suggestion) {
  final parts = <String>[
    if (suggestion.domain.isNotEmpty) suggestion.domain,
    if (suggestion.project.isNotEmpty) suggestion.project,
    if (suggestion.timeWindow.isNotEmpty) suggestion.timeWindow,
    if (suggestion.responsibility.isNotEmpty) suggestion.responsibility,
    if (suggestion.promiseSource.isNotEmpty) suggestion.promiseSource,
    if (suggestion.consequence.isNotEmpty) suggestion.consequence,
  ];
  if (parts.isEmpty) {
    return suggestion.explanation;
  }
  return parts.join(' • ');
}

/// Formats a normalized score for dialog input.
String _scoreInputText(double value) {
  if (value <= 0) {
    return '';
  }
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Parses a dialog score where blank means no explicit signal.
double? _parseDialogScore(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return 0;
  }
  final score = double.tryParse(text);
  if (score == null || score < 0 || score > 1) {
    return null;
  }
  return score;
}

/// Builds dialog field decoration consistent with context text fields.
InputDecoration _taskDialogDecoration(BuildContext context, String label) {
  final colors = context.agentAwesomeColors;
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: colors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.searchBorder),
    ),
  );
}

/// Resolves a task title for graph rows.
String _taskTitleFor(AgentAwesomeAppController controller, String taskId) {
  final indexedTitle = controller.taskInsightIndex.titleForTaskId(taskId);
  if (indexedTitle != taskId) {
    return indexedTitle;
  }
  for (final task in controller.workspace.tasks) {
    if (task.id == taskId) {
      return task.title;
    }
  }
  return taskId.isEmpty ? 'Unknown backlog item' : taskId;
}

/// Reports whether an edge endpoint is a constellation anchor, not a task.
bool _isConstellationAnchorEndpoint(String id) {
  return id.startsWith('anchor:');
}

/// Resolves task and anchor endpoint labels for graph rows.
String _constellationEndpointLabel(
  AgentAwesomeAppController controller,
  String endpointId,
) {
  if (_isConstellationAnchorEndpoint(endpointId)) {
    return endpointId.substring('anchor:'.length);
  }
  return _taskTitleFor(controller, endpointId);
}

/// Returns an icon for one AI screen change.
IconData _screenChangeIcon(ScreenChange change) {
  if (change.status == ScreenChangeStatus.rejected) {
    return Icons.block_outlined;
  }
  if (change.status == ScreenChangeStatus.failed) {
    return Icons.error_outline;
  }
  if (change.status == ScreenChangeStatus.applied) {
    return Icons.check_circle_outline;
  }
  return switch (change.operation) {
    ScreenChangeOperation.createTask => Icons.add_task_outlined,
    ScreenChangeOperation.updateTask => Icons.edit_outlined,
    ScreenChangeOperation.completeTask => Icons.task_alt_outlined,
    ScreenChangeOperation.cancelTask => Icons.cancel_outlined,
    ScreenChangeOperation.deleteTask => Icons.delete_outline,
    ScreenChangeOperation.upsertTaskRelation => Icons.account_tree_outlined,
    ScreenChangeOperation.deleteTaskRelation => Icons.link_off_outlined,
    ScreenChangeOperation.linkTaskMemory => Icons.link_outlined,
  };
}

/// Returns a color for one AI screen change status.
Color _screenChangeColor(BuildContext context, ScreenChange change) {
  final colors = context.agentAwesomeColors;
  return switch (change.status) {
    ScreenChangeStatus.applied => context.agentAwesomeLowAccent,
    ScreenChangeStatus.rejected || ScreenChangeStatus.failed => colors.coral,
    ScreenChangeStatus.undone => colors.muted,
    ScreenChangeStatus.proposed =>
      change.safety == ScreenChangeSafety.autoApply
          ? context.agentAwesomeLowAccent
          : context.agentAwesomeWarningAccent,
  };
}

/// Formats one AI screen change operation label.
String _screenChangeOperationLabel(ScreenChangeOperation operation) {
  return screenChangeOperationToolName(operation).replaceAll('_', ' ');
}

/// Formats one AI screen change status label.
String _screenChangeStatusLabel(ScreenChange change) {
  return switch (change.status) {
    ScreenChangeStatus.proposed =>
      change.safety == ScreenChangeSafety.autoApply
          ? 'Auto safe'
          : 'Needs review',
    ScreenChangeStatus.applied => 'Applied',
    ScreenChangeStatus.rejected => 'Rejected',
    ScreenChangeStatus.failed => 'Failed',
    ScreenChangeStatus.undone => 'Undone',
  };
}

/// Formats a screen-change diff value.
String _screenValueLabel(dynamic value) {
  if (value == null || value.toString().trim().isEmpty) {
    return '-';
  }
  if (value is List) {
    return value.map((item) => item.toString()).join(', ');
  }
  return value.toString();
}

/// Formats a compact inline diff for a task tile.
String _inlineScreenChangeDiff(ScreenChange change) {
  final keys = <String>{
    ...change.beforeValues.keys,
    ...change.afterValues.keys,
  }.take(3);
  return keys
      .map((key) {
        final before = _screenValueLabel(change.beforeValues[key]);
        final after = _screenValueLabel(change.afterValues[key]);
        return '${_taskLabel(key)}: $before -> $after';
      })
      .join(' • ');
}

/// Parses a human-entered task date.
DateTime? _parseTaskDateInput(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  final direct = DateTime.tryParse(text);
  if (direct != null) {
    return direct;
  }
  final spaced = DateTime.tryParse(text.replaceFirst(' ', 'T'));
  if (spaced != null) {
    return spaced;
  }
  final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (dateOnly == null) {
    return null;
  }
  return DateTime(
    int.parse(dateOnly.group(1)!),
    int.parse(dateOnly.group(2)!),
    int.parse(dateOnly.group(3)!),
  );
}

/// Converts controlled task vocabulary to readable labels.
String _taskLabel(String value) {
  if (value.isEmpty) {
    return '';
  }
  return value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
