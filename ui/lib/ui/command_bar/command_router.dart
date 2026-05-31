/// Routes global command-bar text to deterministic UI actions when possible.
library;

import '../../domain/models.dart';
import '../../domain/user_message_text.dart';
import '../shell/app_sections.dart';
import 'command_context.dart';

/// CommandRouteKind describes how a screen command should be handled.
enum CommandRouteKind {
  /// No action should be taken.
  none,

  /// Open a top-level workspace section.
  navigateSection,

  /// Open one settings subsection.
  openSettings,

  /// Apply backlog queue filters.
  taskFilter,

  /// Refresh context data from the graph service.
  refreshTasks,

  /// Apply memory retrieval filters.
  memoryFilter,

  /// Refresh memory data from the graph service.
  refreshMemory,

  /// Send a screen-scoped command to structured AI planning.
  screenAi,

  /// Send a screen-scoped instruction to Agent Awesome.
  assistant,
}

/// CommandRoute stores one deterministic command-bar routing decision.
class CommandRoute {
  /// Creates a command routing result.
  const CommandRoute({
    required this.kind,
    this.section = '',
    this.settingsSection = '',
    this.taskFilters,
    this.memoryFilters,
    this.assistantText = '',
    this.displayText = '',
  });

  /// No-op routing result.
  const CommandRoute.none()
    : kind = CommandRouteKind.none,
      section = '',
      settingsSection = '',
      taskFilters = null,
      memoryFilters = null,
      assistantText = '',
      displayText = '';

  /// Routing action kind.
  final CommandRouteKind kind;

  /// Target top-level section for navigation.
  final String section;

  /// Target settings subsection.
  final String settingsSection;

  /// Context filters to apply.
  final TaskFilterState? taskFilters;

  /// Memory filters to apply.
  final MemoryFilterState? memoryFilters;

  /// Screen-scoped assistant instruction.
  final String assistantText;

  /// User-facing text to display when assistantText contains hidden context.
  final String displayText;
}

/// CommandRouter converts global command text into UI actions.
class CommandRouter {
  /// Creates a router with the current app filter state.
  const CommandRouter({required this.taskFilters, required this.memoryFilters});

  /// Current task filters used as a base for local task commands.
  final TaskFilterState taskFilters;

  /// Current memory filters used as a base for local memory commands.
  final MemoryFilterState memoryFilters;

  /// Routes one global command in the supplied screen context.
  CommandRoute route(CommandContext context) {
    final text = context.text.trim();
    if (text.isEmpty) {
      return const CommandRoute.none();
    }
    final navigation = _navigationRoute(text);
    if (navigation != null) {
      return navigation;
    }
    if (_isSettingsContext(context)) {
      final settings = _settingsRoute(text);
      if (settings != null) {
        return settings;
      }
    }
    if (_isTaskContext(context)) {
      final tasks = _taskRoute(text);
      if (tasks != null) {
        return tasks;
      }
    }
    if (_isMemoryContext(context)) {
      final memory = _memoryRoute(text);
      if (memory != null) {
        return memory;
      }
    }
    if (_isTaskContext(context)) {
      return const CommandRoute(kind: CommandRouteKind.screenAi);
    }
    return CommandRoute(
      kind: CommandRouteKind.assistant,
      assistantText: _screenInstruction(context),
      displayText: context.text.trim(),
    );
  }

  /// Routes short navigation commands to top-level workspaces.
  CommandRoute? _navigationRoute(String text) {
    final normalized = _normalize(text);
    const sections = <String, String>{
      'today': AppSections.today,
      'home': AppSections.today,
      'chat': AppSections.chat,
      'backlog': AppSections.backlog,
      'command': AppSections.backlog,
      'automation': AppSections.automationLaunchpad,
      'automations': AppSections.automationLaunchpad,
      'launch': AppSections.automationLaunchpad,
      'launchpad': AppSections.automationLaunchpad,
      'runbook': AppSections.automationRunbooks,
      'runbooks': AppSections.automationRunbooks,
      'agent': AppSections.automationAgents,
      'agents': AppSections.automationAgents,
      'mcp': AppSections.automationMcpServers,
      'server': AppSections.automationMcpServers,
      'servers': AppSections.automationMcpServers,
      'tool': AppSections.automationTools,
      'tools': AppSections.automationTools,
      'memory': AppSections.memory,
      'files': AppSections.files,
      'sources': AppSections.files,
      'people': AppSections.people,
      'settings': AppSections.settings,
    };
    final words = normalized.split(' ');
    final navigationVerb = words.first == 'open' || words.first == 'go';
    final directSection =
        words.length == 1 && sections.containsKey(words.first);
    final showSection = words.length == 2 && words.first == 'show';
    if (words.length <= 3 && (navigationVerb || directSection || showSection)) {
      for (final entry in sections.entries) {
        if (words.contains(entry.key)) {
          return CommandRoute(
            kind: CommandRouteKind.navigateSection,
            section: entry.value,
          );
        }
      }
    }
    return null;
  }

  /// Routes settings-context commands to a settings subsection.
  CommandRoute? _settingsRoute(String text) {
    final normalized = _normalize(text);
    const sections = <String, String>{
      'app': 'App',
      'model': 'Models',
      'models': 'Models',
      'provider': 'Models',
      'providers': 'Models',
      'credential': 'Models',
      'credentials': 'Models',
      'key': 'Models',
      'keys': 'Models',
    };
    for (final entry in sections.entries) {
      if (normalized.contains(entry.key)) {
        return CommandRoute(
          kind: CommandRouteKind.openSettings,
          settingsSection: entry.value,
        );
      }
    }
    return null;
  }

  /// Routes task-context commands to task filters or refreshes.
  CommandRoute? _taskRoute(String text) {
    final normalized = _normalize(text);
    if (_isRefresh(normalized)) {
      return const CommandRoute(kind: CommandRouteKind.refreshTasks);
    }
    final statuses = _taskStatuses(normalized);
    final priorities = _taskPriorities(normalized);
    final overdueOnly = normalized.contains('overdue');
    final clear = _isClear(normalized);
    if (clear) {
      return const CommandRoute(
        kind: CommandRouteKind.taskFilter,
        taskFilters: TaskFilterState(),
      );
    }
    if (statuses.isNotEmpty || priorities.isNotEmpty || overdueOnly) {
      return CommandRoute(
        kind: CommandRouteKind.taskFilter,
        taskFilters: taskFilters.copyWith(
          statuses: statuses.isEmpty ? taskFilters.statuses : statuses,
          priorities: priorities,
          overdueOnly: overdueOnly,
          search: _taskSearchText(normalized),
        ),
      );
    }
    if (_looksLikeFind(normalized)) {
      return CommandRoute(
        kind: CommandRouteKind.taskFilter,
        taskFilters: taskFilters.copyWith(search: _strippedFindText(text)),
      );
    }
    return null;
  }

  /// Routes memory-context commands to memory filters or refreshes.
  CommandRoute? _memoryRoute(String text) {
    final normalized = _normalize(text);
    if (_isRefresh(normalized)) {
      return const CommandRoute(kind: CommandRouteKind.refreshMemory);
    }
    if (_isClear(normalized)) {
      return const CommandRoute(
        kind: CommandRouteKind.memoryFilter,
        memoryFilters: MemoryFilterState(),
      );
    }
    if (normalized.startsWith('topic ')) {
      return CommandRoute(
        kind: CommandRouteKind.memoryFilter,
        memoryFilters: memoryFilters.copyWith(
          topics: <String>[_tail(text, 'topic')],
        ),
      );
    }
    if (normalized.startsWith('entity ')) {
      return CommandRoute(
        kind: CommandRouteKind.memoryFilter,
        memoryFilters: memoryFilters.copyWith(
          entityIds: <String>[_tail(text, 'entity')],
        ),
      );
    }
    if (_looksLikeFind(normalized)) {
      return CommandRoute(
        kind: CommandRouteKind.memoryFilter,
        memoryFilters: memoryFilters.copyWith(text: _strippedFindText(text)),
      );
    }
    return null;
  }

  /// Builds an assistant prompt scoped to the current screen.
  String _screenInstruction(CommandContext context) {
    final selected = <String>[
      if (context.selectedTaskId.isNotEmpty)
        'selected backlog id: ${context.selectedTaskId}',
      if (context.selectedMemoryId.isNotEmpty)
        'selected memory id: ${context.selectedMemoryId}',
    ].join(', ');
    return buildScreenCommandPrompt(
      scopeLabel: context.scopeLabel,
      userText: context.text,
      relevantIds: selected,
    );
  }

  /// Reports whether the command is running in the backlog workspace.
  bool _isTaskContext(CommandContext context) {
    return context.section == AppSections.backlog;
  }

  /// Reports whether the command is running in a memory-backed workspace.
  bool _isMemoryContext(CommandContext context) {
    return const <String>{
      'Memory',
      'Files',
      'People',
    }.contains(context.section);
  }

  /// Reports whether the command is running in settings.
  bool _isSettingsContext(CommandContext context) {
    return context.section == 'Settings';
  }

  /// Reports whether normalized text is a refresh command.
  bool _isRefresh(String normalized) {
    return normalized == 'refresh' ||
        normalized == 'reload' ||
        normalized == 'sync' ||
        normalized.startsWith('refresh ');
  }

  /// Reports whether normalized text is a filter reset command.
  bool _isClear(String normalized) {
    return normalized == 'clear' ||
        normalized == 'clear filters' ||
        normalized == 'reset' ||
        normalized == 'reset filters' ||
        normalized == 'show all';
  }

  /// Reports whether normalized text is a search-style command.
  bool _looksLikeFind(String normalized) {
    return normalized.startsWith('find ') ||
        normalized.startsWith('search ') ||
        normalized.startsWith('show ');
  }

  /// Extracts supported task statuses from normalized text.
  List<String> _taskStatuses(String normalized) {
    final statuses = <String>[];
    for (final status in const <String>[
      'open',
      'waiting',
      'blocked',
      'done',
      'canceled',
    ]) {
      if (normalized.contains(status)) {
        statuses.add(status);
      }
    }
    return statuses;
  }

  /// Extracts supported task priorities from normalized text.
  List<String> _taskPriorities(String normalized) {
    final priorities = <String>[];
    for (final priority in const <String>['urgent', 'high', 'normal', 'low']) {
      if (normalized.contains(priority)) {
        priorities.add(priority);
      }
    }
    return priorities;
  }

  /// Removes filter keywords to leave a task search phrase.
  String _taskSearchText(String normalized) {
    final noise = <String>{
      'show',
      'only',
      'backlog',
      'tasks',
      'task',
      'work',
      'items',
      'item',
      'open',
      'waiting',
      'blocked',
      'done',
      'canceled',
      'urgent',
      'high',
      'normal',
      'low',
      'priority',
      'overdue',
    };
    return normalized
        .split(' ')
        .where((word) => word.isNotEmpty && !noise.contains(word))
        .join(' ');
  }

  /// Removes a search command prefix from raw text.
  String _strippedFindText(String text) {
    final trimmed = text.trim();
    final normalized = _normalize(trimmed);
    for (final prefix in const <String>['find ', 'search ', 'show ']) {
      if (normalized.startsWith(prefix)) {
        return trimmed.substring(prefix.length).trim();
      }
    }
    return trimmed;
  }

  /// Returns raw text after a known command prefix.
  String _tail(String text, String prefix) {
    return text.trim().substring(prefix.length).trim();
  }

  /// Normalizes command text for deterministic routing.
  String _normalize(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
