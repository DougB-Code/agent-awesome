/// Tests deterministic routing for top-bar screen commands.
library;

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/ui/command_bar/command_context.dart';
import 'package:agentawesome_ui/ui/command_bar/command_router.dart';
import 'package:agentawesome_ui/ui/shell/app_sections.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs command router unit tests.
void main() {
  test('routes Backlog Stream commands to task filters before navigation', () {
    final route = _router().route(
      const CommandContext(
        section: AppSections.backlog,
        area: 'Stream',
        text: 'show blocked backlog',
      ),
    );

    expect(route.kind, CommandRouteKind.taskFilter);
    expect(route.taskFilters?.statuses, <String>['blocked']);
  });

  test('routes explicit navigation commands to sections', () {
    final route = _router().route(
      const CommandContext(
        section: AppSections.backlog,
        area: 'Stream',
        text: 'open chat',
      ),
    );

    expect(route.kind, CommandRouteKind.navigateSection);
    expect(route.section, 'Chat');
  });

  test('wraps unknown screen commands with current UI context', () {
    final route = _router().route(
      const CommandContext(
        section: AppSections.backlog,
        area: 'Stream',
        text: 'plan the next move',
        selectedTaskId: 'task-123',
      ),
    );

    expect(route.kind, CommandRouteKind.assistant);
    expect(route.assistantText, contains('Backlog / Stream'));
    expect(route.assistantText, contains('task-123'));
  });
}

/// Creates a router with default empty filters.
CommandRouter _router() {
  return const CommandRouter(
    taskFilters: TaskFilterState(),
    memoryFilters: MemoryFilterState(),
  );
}
