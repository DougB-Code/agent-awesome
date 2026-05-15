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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            title: 'Task',
            child: Column(
              children: <Widget>[
                _TaskTextField(controller: _title, label: 'Title'),
                const SizedBox(height: 10),
                _TaskTextField(
                  controller: _description,
                  label: 'Description',
                  maxLines: 4,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TaskDropdown(
                        value: _status,
                        values: _taskStatuses,
                        tooltip: 'Status',
                        onChanged: (value) => setState(() => _status = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TaskDropdown(
                        value: _priority,
                        values: _taskPriorities,
                        tooltip: 'Priority',
                        onChanged: (value) => setState(() => _priority = value),
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
          if (_message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _message,
              style: const TextStyle(color: AgentAwesomeColors.coral),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.controller.tasksBusy ? null : _save,
            icon: const Icon(Icons.add_task),
            label: const Text('Create Backlog Item'),
          ),
          const SizedBox(height: 14),
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _TaskPanelLabel('Nearby Backlog'),
                const SizedBox(height: 10),
                if (matches.isEmpty)
                  Text(
                    'No nearby context',
                    style: TextStyle(color: context.agentAwesomeColors.muted),
                  )
                else
                  for (final task in matches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TaskQueueTile(
                        task: task,
                        selected: widget.controller.selectedTask?.id == task.id,
                        focused: false,
                        changes: const <ScreenChange>[],
                        onTap: () =>
                            widget.controller.inspectBacklogTask(task.id),
                        onScheduleToday: () => unawaited(
                          widget.controller.updateTaskFromUi(
                            taskId: task.id,
                            scheduledAt: _todayDate(),
                          ),
                        ),
                        onSnooze: () => unawaited(
                          widget.controller.updateTaskFromUi(
                            taskId: task.id,
                            scheduledAt: _todayDate().add(
                              const Duration(days: 1),
                            ),
                          ),
                        ),
                        onComplete: null,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
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
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  final TextEditingController _dueAt = TextEditingController();
  final TextEditingController _scheduledAt = TextEditingController();
  String _status = 'open';
  String _priority = 'normal';
  String _message = '';

  /// Initializes editor fields from the selected backlog item.
  @override
  void initState() {
    super.initState();
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
    final terminal = task.status == 'done' || task.status == 'canceled';
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
                        onChanged: (value) => setState(() => _status = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TaskDropdown(
                        value: _priority,
                        values: _taskPriorities,
                        tooltip: 'Priority',
                        onChanged: (value) => setState(() => _priority = value),
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: widget.controller.tasksBusy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.tasksBusy || terminal
                    ? null
                    : () => unawaited(_complete()),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Complete'),
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.tasksBusy || terminal
                    ? null
                    : () => unawaited(_cancel()),
                icon: const Icon(Icons.block_outlined),
                label: const Text('Cancel'),
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.tasksBusy
                    ? null
                    : () => unawaited(_delete()),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
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
  }

  /// Saves editor changes through graph-backed context tools.
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
    if (_title.text.trim().isEmpty) {
      setState(() => _message = 'Title is required');
      return;
    }
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

  /// Completes the selected backlog item after confirmation.
  Future<void> _complete() async {
    if (!await _confirmTaskWrite(
      context,
      'Complete backlog item "${widget.task.title}"?',
    )) {
      return;
    }
    await widget.controller.completeTaskFromUi(widget.task.id);
  }

  /// Cancels the selected backlog item after confirmation.
  Future<void> _cancel() async {
    if (!await _confirmTaskWrite(
      context,
      'Cancel backlog item "${widget.task.title}"?',
    )) {
      return;
    }
    await widget.controller.cancelTaskFromUi(widget.task.id);
  }

  /// Deletes the selected backlog item after confirmation.
  Future<void> _delete() async {
    if (!await _confirmTaskWrite(
      context,
      'Delete backlog item "${widget.task.title}"?',
    )) {
      return;
    }
    await widget.controller.deleteTaskFromUi(widget.task.id);
  }
}
