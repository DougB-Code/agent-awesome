/// Backlog constellation edge inspector widget.
part of 'backlog_section.dart';

/// _TaskConstellationEdgeInspector shows one selected projection relation.
class _TaskConstellationEdgeInspector extends StatelessWidget {
  const _TaskConstellationEdgeInspector({
    required this.controller,
    required this.edge,
  });

  final AgentAwesomeAppController controller;
  final TaskConstellationEdge edge;

  /// Builds read-only details for a selected constellation edge.
  @override
  Widget build(BuildContext context) {
    final explicit = _matchingExplicitRelation();
    final fromIsAnchor = _isConstellationAnchorEndpoint(edge.fromTaskId);
    final toIsAnchor = _isConstellationAnchorEndpoint(edge.toTaskId);
    final factRows = _graphFactMetadataRows(explicit);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelSectionBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _TaskPanelLabel('Relation Edge'),
                const SizedBox(height: 12),
                _TaskGraphRow(
                  icon: Icons.account_tree_outlined,
                  title: _taskLabel(edge.relationType),
                  subtitle: edge.explanation,
                  badges: <String>[
                    _edgeRoleLabel(),
                    if (edge.sourceKind.isNotEmpty) _taskLabel(edge.sourceKind),
                    _formatTaskScore(edge.confidence),
                    if (explicit != null || edge.id.isNotEmpty) 'Graph fact',
                  ],
                  actions: const <Widget>[],
                ),
                const Divider(height: 22),
                _TaskMetadataRow(
                  label: 'From',
                  value: _constellationEndpointLabel(
                    controller,
                    edge.fromTaskId,
                  ),
                ),
                _TaskMetadataRow(
                  label: 'To',
                  value: _constellationEndpointLabel(controller, edge.toTaskId),
                ),
                _TaskMetadataRow(
                  label: 'Relationship',
                  value: _taskLabel(edge.relationType),
                ),
                _TaskMetadataRow(label: 'Role', value: _edgeRoleLabel()),
                _TaskMetadataRow(
                  label: 'Confidence',
                  value: _formatTaskScore(edge.confidence),
                ),
                ...factRows,
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!fromIsAnchor || !toIsAnchor)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                if (!fromIsAnchor)
                  OutlinedButton.icon(
                    onPressed: () => controller.selectTask(edge.fromTaskId),
                    icon: const Icon(Icons.arrow_back_outlined),
                    label: const Text('Open From Backlog'),
                  ),
                if (!toIsAnchor)
                  OutlinedButton.icon(
                    onPressed: () => controller.selectTask(edge.toTaskId),
                    icon: const Icon(Icons.arrow_forward_outlined),
                    label: const Text('Open To Backlog'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Returns the display role attached to this edge in the projection.
  String _edgeRoleLabel() {
    return edge.source.isEmpty ? 'Projected' : _taskLabel(edge.source);
  }

  /// Returns provenance and access metadata rows for the selected graph fact.
  List<Widget> _graphFactMetadataRows(TaskRelationRecord? explicit) {
    final rows = <Widget>[];
    final factSource = _edgeFactSource();
    final id = edge.id.isNotEmpty ? edge.id : explicit?.id ?? '';
    final actor = edge.actor.isNotEmpty ? edge.actor : explicit?.actor ?? '';
    final createdAt = edge.createdAt ?? explicit?.createdAt;
    final updatedAt = edge.updatedAt ?? explicit?.updatedAt;
    if (id.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Relation id', value: id));
    }
    if (factSource.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Provenance', value: factSource));
    }
    if (edge.sourceKind.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Source kind', value: edge.sourceKind));
    }
    if (edge.firewall.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Domain', value: edge.firewall));
    }
    if (edge.sensitivity.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Sensitivity', value: edge.sensitivity));
    }
    if (edge.evidenceIds.isNotEmpty) {
      rows.add(
        _TaskMetadataRow(label: 'Sources', value: edge.evidenceIds.join(', ')),
      );
    }
    if (actor.isNotEmpty) {
      rows.add(_TaskMetadataRow(label: 'Actor', value: actor));
    }
    if (createdAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Created',
          value: formatOptionalLocalDateTime(createdAt),
        ),
      );
    }
    if (updatedAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Updated',
          value: formatOptionalLocalDateTime(updatedAt),
        ),
      );
    }
    if (edge.confirmedAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Confirmed',
          value: formatOptionalLocalDateTime(edge.confirmedAt),
        ),
      );
    }
    if (edge.dismissedAt != null) {
      rows.add(
        _TaskMetadataRow(
          label: 'Dismissed',
          value: formatOptionalLocalDateTime(edge.dismissedAt),
        ),
      );
    }
    if (rows.isEmpty) {
      rows.add(
        const _TaskMetadataRow(
          label: 'Provenance',
          value: 'No graph fact metadata in current projection',
        ),
      );
    }
    return rows;
  }

  /// Returns the original graph fact source when role highlighting replaced it.
  String _edgeFactSource() {
    if (edge.factSource.isNotEmpty) {
      return edge.factSource;
    }
    return switch (edge.source) {
      'query_path' ||
      'critical_path' ||
      'dependency_context' ||
      'materialized_risk' ||
      'risk_context' ||
      'constellation_anchor' => '',
      _ => edge.source,
    };
  }

  /// Finds an explicit relation backing this projection edge, when present.
  TaskRelationRecord? _matchingExplicitRelation() {
    if (_isConstellationAnchorEndpoint(edge.fromTaskId) ||
        _isConstellationAnchorEndpoint(edge.toTaskId)) {
      return null;
    }
    for (final relation in controller.taskRelations) {
      final relationFrom = relation.fromTaskId;
      final relationTo = relation.toTaskId;
      final sameDirection =
          relationFrom == edge.fromTaskId && relationTo == edge.toTaskId;
      final reverseDirection =
          relationFrom == edge.toTaskId && relationTo == edge.fromTaskId;
      if ((sameDirection || reverseDirection) &&
          relation.relationType == edge.relationType) {
        return relation;
      }
    }
    return null;
  }
}
