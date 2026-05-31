/// Backlog task capture and task detail editing widgets.
part of 'backlog_section.dart';

class _TaskCaptureContent extends StatefulWidget {
  const _TaskCaptureContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  @override
  State<_TaskCaptureContent> createState() => _TaskCaptureContentState();
}

class _TaskCaptureContentState extends State<_TaskCaptureContent> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  final TextEditingController _dueAt = TextEditingController();
  final TextEditingController _scheduledAt = TextEditingController();
  String _status = 'open';
  String _priority = 'normal';
  bool _linkMemory = false;
  String _message = '';

  /// Cleans up capture form controllers.
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _topics.dispose();
    _dueAt.dispose();
    _scheduledAt.dispose();
    super.dispose();
  }

  /// Builds the quick context capture form.
  @override
  Widget build(BuildContext context) {
    final matches = widget.controller.workspace.tasks
        .where((task) {
          return _title.text.trim().isNotEmpty &&
              _matchesTask(task, '${_title.text} ${widget.query}');
        })
        .take(4);
    return PanelFormView(
      children: <Widget>[
        PanelFormSection(
          title: 'Task',
          children: <Widget>[
            _TaskTextField(controller: _title, label: 'Title'),
            const SizedBox(height: PanelFormMetrics.fieldGap),
            _TaskTextField(
              controller: _description,
              label: 'Description',
              maxLines: 4,
            ),
            const SizedBox(height: PanelFormMetrics.fieldGap),
            PanelFieldGrid(
              children: <Widget>[
                _TaskDropdown(
                  value: _status,
                  values: _taskStatuses,
                  tooltip: 'Status',
                  onChanged: (value) => setState(() => _status = value),
                ),
                _TaskDropdown(
                  value: _priority,
                  values: _taskPriorities,
                  tooltip: 'Priority',
                  onChanged: (value) => setState(() => _priority = value),
                ),
                _TaskDatePickerField(controller: _dueAt, label: 'Due date'),
                _TaskDatePickerField(
                  controller: _scheduledAt,
                  label: 'Scheduled date',
                ),
              ],
            ),
            const SizedBox(height: PanelFormMetrics.fieldGap),
            _TaskTextField(controller: _topics, label: 'Topics'),
            const SizedBox(height: PanelFormMetrics.compactGap),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.trailing,
              title: const Text('Link selected memory'),
              value: _linkMemory,
              onChanged: widget.controller.selectedMemory == null
                  ? null
                  : (value) => setState(() => _linkMemory = value ?? false),
            ),
            if (_message.isNotEmpty) ...<Widget>[
              const SizedBox(height: PanelFormMetrics.compactGap),
              Text(
                _message,
                style: const TextStyle(color: AgentAwesomeColors.coral),
              ),
            ],
            const SizedBox(height: PanelFormMetrics.compactGap),
            FilledButton.icon(
              onPressed: widget.controller.tasksBusy ? null : _save,
              icon: const Icon(Icons.add_task),
              label: const Text('Create Backlog Item'),
            ),
          ],
        ),
        PanelFormSection(
          title: 'Nearby Backlog',
          children: <Widget>[
            if (matches.isEmpty)
              Text(
                'No nearby context',
                style: TextStyle(color: context.agentAwesomeColors.muted),
              )
            else
              for (final task in matches)
                _TaskQueueTile(
                  controller: widget.controller,
                  task: task,
                  selected: widget.controller.selectedTask?.id == task.id,
                  focused: false,
                  changes: const <ScreenChange>[],
                  onTap: () => widget.controller.inspectBacklogTask(task.id),
                ),
          ],
        ),
      ],
    );
  }

  /// Saves the captured backlog item.
  Future<void> _save() async {
    final dueAt = _parseTaskDateInput(_dueAt.text);
    final scheduledAt = _parseTaskDateInput(_scheduledAt.text);
    if (_dueAt.text.trim().isNotEmpty && dueAt == null) {
      setState(() => _message = 'Due date could not be parsed');
      return;
    }
    if (_scheduledAt.text.trim().isNotEmpty && scheduledAt == null) {
      setState(() => _message = 'Scheduled date could not be parsed');
      return;
    }
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _message = 'Title is required');
      return;
    }
    await widget.controller.createTaskFromUi(
      title,
      description: _description.text.trim(),
      status: _status,
      priority: _priority,
      dueAt: dueAt,
      scheduledAt: scheduledAt,
      topics: splitCommaSeparatedValues(_topics.text),
      linkSelectedMemory: _linkMemory,
    );
    if (!mounted) {
      return;
    }
    _title.clear();
    _description.clear();
    _topics.clear();
    _dueAt.clear();
    _scheduledAt.clear();
    setState(() {
      _message = '';
      _linkMemory = false;
    });
  }
}

class _TaskDetailEditor extends StatefulWidget {
  const _TaskDetailEditor({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  @override
  State<_TaskDetailEditor> createState() => _TaskDetailEditorState();
}

class _TaskDetailEditorState extends State<_TaskDetailEditor> {
  static const Duration _saveDelay = Duration(milliseconds: 500);

  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  final TextEditingController _dueAt = TextEditingController();
  final TextEditingController _scheduledAt = TextEditingController();
  Timer? _saveTimer;
  String _status = 'open';
  String _priority = 'normal';
  String _message = '';
  String _lastSavedFingerprint = '';

  /// Initializes editor fields from the selected backlog item.
  @override
  void initState() {
    super.initState();
    _title.addListener(_scheduleSave);
    _description.addListener(_scheduleSave);
    _topics.addListener(_scheduleSave);
    _dueAt.addListener(_scheduleSave);
    _scheduledAt.addListener(_scheduleSave);
    _syncFromTask();
  }

  /// Reloads editor fields when context selection changes.
  @override
  void didUpdateWidget(covariant _TaskDetailEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _syncFromTask();
    }
  }

  /// Cleans up editor controllers.
  @override
  void dispose() {
    _saveTimer?.cancel();
    _title.removeListener(_scheduleSave);
    _description.removeListener(_scheduleSave);
    _topics.removeListener(_scheduleSave);
    _dueAt.removeListener(_scheduleSave);
    _scheduledAt.removeListener(_scheduleSave);
    _title.dispose();
    _description.dispose();
    _topics.dispose();
    _dueAt.dispose();
    _scheduledAt.dispose();
    super.dispose();
  }

  /// Builds the selected backlog editor.
  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock.plain(
            title: 'Task',
            child: Column(
              children: <Widget>[
                _TaskTextField(controller: _title, label: 'Title'),
                const SizedBox(height: 10),
                _TaskTextField(
                  controller: _description,
                  label: 'Description',
                  maxLines: 5,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TaskDropdown(
                        value: _status,
                        values: _taskStatuses,
                        tooltip: 'Status',
                        onChanged: (value) => setState(() {
                          _status = value;
                          _scheduleSave();
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TaskDropdown(
                        value: _priority,
                        values: _taskPriorities,
                        tooltip: 'Priority',
                        onChanged: (value) => setState(() {
                          _priority = value;
                          _scheduleSave();
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TaskDatePickerField(
                        controller: _dueAt,
                        label: 'Due date',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TaskDatePickerField(
                        controller: _scheduledAt,
                        label: 'Scheduled date',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _TaskTextField(controller: _topics, label: 'Topics'),
              ],
            ),
          ),
          if (_message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _message,
              style: const TextStyle(color: AgentAwesomeColors.coral),
            ),
          ],
          const SizedBox(height: 14),
          _TaskMetadataBlock(controller: widget.controller, task: task),
          const SizedBox(height: 14),
          _TaskWbsBlock(controller: widget.controller, task: task),
          const SizedBox(height: 14),
          _TaskGraphDetailsBlock(controller: widget.controller, task: task),
        ],
      ),
    );
  }

  /// Copies selected backlog data into text fields.
  void _syncFromTask() {
    _title.text = widget.task.title;
    _description.text = widget.task.description;
    _topics.text = widget.task.topics.join(', ');
    _dueAt.text = formatOptionalLocalDate(widget.task.dueAt);
    _scheduledAt.text = formatOptionalLocalDate(widget.task.scheduledAt);
    _status = widget.task.status;
    _priority = widget.task.priority;
    _message = '';
    _lastSavedFingerprint = _taskFingerprint();
  }

  /// Saves editor changes through graph-backed context tools.
  Future<void> _save() async {
    _saveTimer?.cancel();
    if (widget.controller.tasksBusy) {
      _scheduleSave();
      return;
    }
    final fingerprint = _taskFingerprint();
    if (fingerprint == _lastSavedFingerprint) {
      return;
    }
    final dueAt = _parseTaskDateInput(_dueAt.text);
    final scheduledAt = _parseTaskDateInput(_scheduledAt.text);
    if (_dueAt.text.trim().isNotEmpty && dueAt == null) {
      setState(() => _message = 'Due date could not be parsed');
      return;
    }
    if (_scheduledAt.text.trim().isNotEmpty && scheduledAt == null) {
      setState(() => _message = 'Scheduled date could not be parsed');
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _message = 'Title is required');
      return;
    }
    _lastSavedFingerprint = fingerprint;
    await widget.controller.updateTaskFromUi(
      taskId: widget.task.id,
      title: _title.text.trim(),
      description: _description.text.trim(),
      status: _status,
      priority: _priority,
      dueAt: dueAt,
      clearDueAt: _dueAt.text.trim().isEmpty && widget.task.dueAt != null,
      scheduledAt: scheduledAt,
      clearScheduledAt:
          _scheduledAt.text.trim().isEmpty && widget.task.scheduledAt != null,
      topics: splitCommaSeparatedValues(_topics.text),
    );
    if (mounted) {
      setState(() => _message = '');
    }
  }

  /// Schedules one task save after a short edit pause.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_save()));
  }

  /// Returns a stable comparison key for persisted task editor fields.
  String _taskFingerprint() {
    return jsonEncode(<String, Object?>{
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'status': _status,
      'priority': _priority,
      'dueAt': _dueAt.text.trim(),
      'scheduledAt': _scheduledAt.text.trim(),
      'topics': splitCommaSeparatedValues(_topics.text),
    });
  }
}
