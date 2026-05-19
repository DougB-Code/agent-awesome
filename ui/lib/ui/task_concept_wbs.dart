/// Work breakdown structure task projection widgets.
part of 'task_concept_views.dart';

class _TaskWbsView extends StatelessWidget {
  const _TaskWbsView({required this.controller});

  final AgentAwesomeAppController controller;

  /// Builds the work-breakdown structure tree.
  @override
  Widget build(BuildContext context) {
    final tasks =
        controller.workspace.tasks
            .where((task) => taskWbsHasContent(task.workBreakdown))
            .toList()
          ..sort(compareWorkspaceTasksByWbs);
    if (tasks.isEmpty) {
      return PanelEmptyBlock(
        label: _emptyProjectionLabel(
          controller,
          'No WBS metadata yet. Add WBS details to a backlog item or generate a project breakdown.',
        ),
      );
    }
    final roots = buildTaskWbsTree(tasks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: PanelSectionBlock(
            child: ListView.builder(
              itemCount: roots.length,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemBuilder: (context, index) {
                return _WbsTreeNodeView(
                  node: roots[index],
                  controller: controller,
                  depth: 0,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _WbsTreeNodeView extends StatelessWidget {
  const _WbsTreeNodeView({
    required this.node,
    required this.controller,
    required this.depth,
  });

  final TaskWbsTreeNode node;
  final AgentAwesomeAppController controller;
  final int depth;

  /// Builds one recursive WBS tree node.
  @override
  Widget build(BuildContext context) {
    if (node.isWorkPackage) {
      return _WbsWorkPackageNode(
        node: node,
        controller: controller,
        depth: depth,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _WbsBranchNode(node: node, depth: depth),
        for (final child in node.children)
          _WbsTreeNodeView(
            node: child,
            controller: controller,
            depth: depth + 1,
          ),
      ],
    );
  }
}

const int _maxWbsVisualDepth = 8;
const double _baseWbsIndent = 14;
const double _wbsIndentStep = 18;

/// Returns bounded WBS indentation for deeply decomposed project trees.
double _wbsIndentForDepth(int depth) {
  final boundedDepth = math.max(0, math.min(depth, _maxWbsVisualDepth));
  return _baseWbsIndent + boundedDepth * _wbsIndentStep;
}

class _WbsBranchNode extends StatelessWidget {
  const _WbsBranchNode({required this.node, required this.depth});

  final TaskWbsTreeNode node;
  final int depth;

  /// Builds one non-leaf WBS decomposition bucket.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final isRoot = node.kind == TaskWbsTreeNodeKind.root;
    return Container(
      margin: EdgeInsets.only(top: isRoot && depth == 0 ? 8 : 0),
      padding: EdgeInsets.fromLTRB(_wbsIndentForDepth(depth), 10, 14, 10),
      decoration: BoxDecoration(
        color: isRoot
            ? colors.greenSoft.withValues(alpha: 0.32)
            : colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isRoot ? Icons.account_tree_outlined : Icons.folder_open_outlined,
            size: isRoot ? 20 : 18,
            color: colors.green,
          ),
          const SizedBox(width: 10),
          _WbsCodeBadge(code: node.code),
          Expanded(
            child: Text(
              node.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isRoot ? colors.green : colors.ink,
                fontSize: isRoot ? 15 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _WbsNodeStats(node: node),
        ],
      ),
    );
  }
}

class _WbsWorkPackageNode extends StatelessWidget {
  const _WbsWorkPackageNode({
    required this.node,
    required this.controller,
    required this.depth,
  });

  final TaskWbsTreeNode node;
  final AgentAwesomeAppController controller;
  final int depth;

  /// Builds one leaf WBS work package.
  @override
  Widget build(BuildContext context) {
    final task = node.task;
    if (task == null) {
      return const SizedBox.shrink();
    }
    final workBreakdown = task.workBreakdown;
    final gaps = _wbsMissingFields(task);
    final colors = context.agentAwesomeColors;
    return InkWell(
      onTap: () => controller.selectTask(task.id),
      child: Container(
        padding: EdgeInsets.fromLTRB(_wbsIndentForDepth(depth), 10, 14, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.border.withValues(alpha: 0.62)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.task_alt_outlined, size: 18, color: colors.muted),
            const SizedBox(width: 10),
            _WbsCodeBadge(code: workBreakdown.code),
            Expanded(
              child: _WbsWorkPackageContent(task: task, gaps: gaps),
            ),
          ],
        ),
      ),
    );
  }
}

class _WbsNodeStats extends StatelessWidget {
  const _WbsNodeStats({required this.node});

  final TaskWbsTreeNode node;

  /// Builds aggregate stats for a WBS bucket.
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: <Widget>[
        _MiniBadge(label: '${node.workPackageCount} packages'),
        if (node.estimateMinutes > 0)
          _MiniBadge(
            label: '${(node.estimateMinutes / 60).toStringAsFixed(1)}h',
          ),
        if (node.estimatedCostCents > 0)
          _MiniBadge(
            label: formatMinorUnitSpend(
              node.estimatedCostCents,
              node.costCurrency,
            ),
          ),
      ],
    );
  }
}

class _WbsCodeBadge extends StatelessWidget {
  const _WbsCodeBadge({required this.code});

  final String code;

  /// Builds the WBS hierarchy code badge.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final label = code.isEmpty ? 'No code' : code;
    return Tooltip(
      message: label,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          gradient: context.agentAwesomeControlGradient,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _WbsWorkPackageContent extends StatelessWidget {
  const _WbsWorkPackageContent({required this.task, required this.gaps});

  final WorkspaceTask task;
  final List<String> gaps;

  /// Builds one leaf task plus its WBS source context.
  @override
  Widget build(BuildContext context) {
    final workBreakdown = task.workBreakdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _WbsTaskSummary(task: task, gaps: gaps),
            ),
            const SizedBox(width: 12),
            _WbsLeafSpend(workBreakdown: workBreakdown),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 12,
          children: <Widget>[
            _WbsDetailBlock(
              label: 'Start',
              child: _WbsTextList(values: workBreakdown.startCriteria),
            ),
            _WbsDetailBlock(
              label: 'Done',
              child: _WbsTextList(values: workBreakdown.acceptanceCriteria),
            ),
            _WbsDetailBlock(
              label: 'Resources',
              child: _WbsResourceSummary(resources: workBreakdown.resources),
            ),
          ],
        ),
      ],
    );
  }
}

class _WbsLeafSpend extends StatelessWidget {
  const _WbsLeafSpend({required this.workBreakdown});

  final TaskWorkBreakdown workBreakdown;

  /// Builds the leaf package spend label.
  @override
  Widget build(BuildContext context) {
    final label = formatTaskWbsSpend(workBreakdown);
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 128),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _WbsDetailBlock extends StatelessWidget {
  const _WbsDetailBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  /// Builds one compact leaf detail block.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.subtle,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          child,
        ],
      ),
    );
  }
}

class _WbsTaskSummary extends StatelessWidget {
  const _WbsTaskSummary({required this.task, required this.gaps});

  final WorkspaceTask task;
  final List<String> gaps;

  /// Builds title, deliverable, traceability, and gap badges.
  @override
  Widget build(BuildContext context) {
    final workBreakdown = task.workBreakdown;
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.ink, fontWeight: FontWeight.w800),
          ),
          if (workBreakdown.deliverable.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              workBreakdown.deliverable,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              if (task.estimateMinutes > 0)
                _MiniBadge(label: '${task.estimateMinutes}m'),
              for (final ref in workBreakdown.requirementRefs.take(2))
                _MiniBadge(label: ref),
              for (final ref in workBreakdown.rubricRefs.take(2))
                _MiniBadge(label: ref),
              if (gaps.isNotEmpty) _MiniBadge(label: '${gaps.length} gaps'),
            ],
          ),
        ],
      ),
    );
  }
}

class _WbsTextList extends StatelessWidget {
  const _WbsTextList({required this.values});

  final List<String> values;

  /// Builds compact multi-line WBS criteria text.
  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Text(
        'Missing',
        style: TextStyle(color: context.agentAwesomeColors.muted, fontSize: 12),
      );
    }
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final value in values.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.ink, fontSize: 12, height: 1.25),
              ),
            ),
        ],
      ),
    );
  }
}

class _WbsResourceSummary extends StatelessWidget {
  const _WbsResourceSummary({required this.resources});

  final List<TaskResourceRequirement> resources;

  /// Builds compact resource requirements for a WBS row.
  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return Text(
        'Missing',
        style: TextStyle(color: context.agentAwesomeColors.muted, fontSize: 12),
      );
    }
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final resource in resources.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _resourceSummary(resource),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.ink, fontSize: 12, height: 1.25),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label});

  final String label;

  /// Builds a small inline WBS badge.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: colors.greenSoft.withValues(alpha: 0.34),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.green,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
