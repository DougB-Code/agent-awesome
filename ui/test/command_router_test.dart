/// Tests deterministic routing for top-bar screen commands.
library;

import 'package:agentawesome_ui/domain/models.dart';
import 'package:agentawesome_ui/domain/user_message_text.dart';
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

  test('routes unknown Backlog commands to structured screen AI', () {
    final route = _router().route(
      const CommandContext(
        section: AppSections.backlog,
        area: 'Stream',
        text: 'plan the next move',
        selectedTaskId: 'task-123',
      ),
    );

    expect(route.kind, CommandRouteKind.screenAi);
    expect(route.assistantText, isEmpty);
  });

  test('routes official command panel commands through the task path', () {
    final route = _router().route(
      const CommandContext(
        section: AppSections.backlog,
        area: 'Queue',
        text: 'show high waiting',
      ),
    );

    expect(route.kind, CommandRouteKind.taskFilter);
    expect(route.taskFilters?.statuses, <String>['waiting']);
    expect(route.taskFilters?.priorities, <String>['high']);
  });

  test('routes command panel navigation aliases to Backlog', () {
    final route = _router().route(
      const CommandContext(
        section: AppSections.backlog,
        area: 'Queue',
        text: 'open command',
      ),
    );

    expect(route.kind, CommandRouteKind.navigateSection);
    expect(route.section, AppSections.backlog);
  });

  test('routes runbook authoring aliases to Runbooks', () {
    final route = _router().route(
      const CommandContext(
        section: AppSections.memory,
        area: 'Library',
        text: 'open runbooks',
      ),
    );

    expect(route.kind, CommandRouteKind.navigateSection);
    expect(route.section, AppSections.automationRunbooks);
  });

  test('routes agent authoring aliases to Automations Agents', () {
    final route = _router().route(
      const CommandContext(
        section: AppSections.memory,
        area: 'Library',
        text: 'open agents',
      ),
    );

    expect(route.kind, CommandRouteKind.navigateSection);
    expect(route.section, AppSections.automationAgents);
  });

  test('does not route removed task authoring aliases', () {
    final route = _router().route(
      const CommandContext(
        section: AppSections.memory,
        area: 'Library',
        text: 'open tasks',
      ),
    );

    expect(route.kind, CommandRouteKind.assistant);
    expect(route.section, isEmpty);
  });

  test('wraps unknown non-Backlog commands with current UI context', () {
    final route = _router().route(
      const CommandContext(
        section: AppSections.memory,
        area: 'Library',
        text: 'what does this screen mean?',
        selectedMemoryId: 'mem-123',
      ),
    );

    expect(route.kind, CommandRouteKind.assistant);
    expect(route.assistantText, contains('Memory / Library'));
    expect(route.assistantText, contains('mem-123'));
    expect(
      displayTextFromUserPrompt(route.assistantText),
      'what does this screen mean?',
    );
  });
}

/// Creates a router with default empty filters.
CommandRouter _router() {
  return const CommandRouter(
    taskFilters: TaskFilterState(),
    memoryFilters: MemoryFilterState(),
  );
}
