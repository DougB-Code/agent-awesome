/// Chat runtime summary aggregation helpers.
part of 'agent_awesome_shell.dart';

List<_ChatRuntimeSummary> _chatRuntimeSummaries(
  AgentAwesomeAppController controller,
) {
  return <_ChatRuntimeSummary>[
    _chatSessionRuntimeSummary(controller),
    ..._chatModelRuntimeSummaries(controller),
    ..._chatMemoryRuntimeSummaries(controller),
  ];
}

/// Returns model summaries for every model available to the active profile.
List<_ChatRuntimeSummary> _chatModelRuntimeSummaries(
  AgentAwesomeAppController controller,
) {
  final choices = controller.chatModelChoices;
  if (choices.isEmpty) {
    return const <_ChatRuntimeSummary>[
      _ChatRuntimeSummary(
        title: 'Chat model',
        detail: 'No model configured',
        state: ConnectionStateKind.disconnected,
        icon: Icons.psychology_alt_outlined,
        message: 'Select a model in Settings.',
      ),
    ];
  }
  final activeRef = controller.activeChatModelRef;
  final activeChoice = _chatModelChoiceByRef(choices, activeRef);
  final ordered = <ModelConfigChoice>[
    ?activeChoice,
    for (final choice in choices)
      if (choice.ref != activeRef) choice,
  ];
  return <_ChatRuntimeSummary>[
    for (final choice in ordered)
      _chatModelRuntimeSummary(choice, selected: choice.ref == activeRef),
  ];
}

/// Returns one model row for the runtime overview.
_ChatRuntimeSummary _chatModelRuntimeSummary(
  ModelConfigChoice choice, {
  required bool selected,
}) {
  return _ChatRuntimeSummary(
    title: selected ? 'Selected model' : 'Available model',
    detail: _chatModelChoiceDetail(choice),
    state: ConnectionStateKind.connected,
    icon: Icons.psychology_alt_outlined,
    message: '',
  );
}

/// Returns the display detail for a runtime model choice.
String _chatModelChoiceDetail(ModelConfigChoice choice) {
  final modelName = choice.modelName.trim();
  if (modelName.isEmpty || modelName == choice.modelId) {
    return choice.label;
  }
  return '${choice.label} - $modelName';
}

/// Finds a configured model choice by provider:model ref.
ModelConfigChoice? _chatModelChoiceByRef(
  List<ModelConfigChoice> choices,
  String ref,
) {
  for (final choice in choices) {
    if (choice.ref == ref) {
      return choice;
    }
  }
  return null;
}

/// Returns memory sources granted to the active runtime profile.
List<_ChatRuntimeSummary> _chatMemoryRuntimeSummaries(
  AgentAwesomeAppController controller,
) {
  final memoryServers = _activeMemoryServers(controller);
  if (memoryServers.isEmpty) {
    return <_ChatRuntimeSummary>[_chatMemoryRuntimeSummary(controller, null)];
  }
  return <_ChatRuntimeSummary>[
    for (final server in memoryServers)
      _chatMemoryRuntimeSummary(controller, server),
  ];
}

/// Returns one memory source runtime summary.
_ChatRuntimeSummary _chatMemoryRuntimeSummary(
  AgentAwesomeAppController controller,
  McpServerRuntime? memoryServer,
) {
  final name = memoryServer?.label ?? 'No memory domain configured';
  final endpoint = _statusNamed(controller.endpointStatuses, name);
  final process = _statusNamed(controller.localProcessStatuses, name);
  final state = _combinedRuntimeState(endpoint?.state, process?.state);
  return _ChatRuntimeSummary(
    title: 'Memory',
    detail: name,
    state: state,
    icon: Icons.auto_awesome_mosaic_outlined,
    message: _memoryRuntimeAccessLabel(controller, memoryServer),
  );
}

/// Returns active memory servers in profile grant order.
List<McpServerRuntime> _activeMemoryServers(
  AgentAwesomeAppController controller,
) {
  final profile = controller.runtimeProfile;
  if (profile == null) {
    return const <McpServerRuntime>[];
  }
  final grantedIds = _orderedMemoryGrantIds(profile.agentMemory);
  final servers = <McpServerRuntime>[];
  for (final id in grantedIds) {
    for (final server in profile.mcpServers) {
      if (server.enabled && server.kind == 'memory' && server.id == id) {
        servers.add(server);
        break;
      }
    }
  }
  return servers;
}

/// Returns memory domain ids in stable display order for runtime cards.
List<String> _orderedMemoryGrantIds(AgentMemoryRuntime agentMemory) {
  final ids = <String>[];
  for (final id in <String>[
    agentMemory.defaultWriteDomain,
    ...agentMemory.writeDomains,
    ...agentMemory.readDomains,
  ]) {
    if (id.trim().isNotEmpty && !ids.contains(id)) {
      ids.add(id);
    }
  }
  return ids;
}

/// Returns the profile access grants shown on a memory runtime card.
String _memoryRuntimeAccessLabel(
  AgentAwesomeAppController controller,
  McpServerRuntime? memoryServer,
) {
  if (memoryServer == null) {
    return 'Select memory domains in Settings.';
  }
  final memory = controller.runtimeProfile?.agentMemory;
  if (memory == null) {
    return '';
  }
  final flags = <String>[
    if (memory.readDomains.contains(memoryServer.id)) 'read',
    if (memory.writeDomains.contains(memoryServer.id)) 'write',
    if (memory.defaultWriteDomain == memoryServer.id) 'default',
  ];
  return flags.join(' / ');
}

/// Returns the active chat session runtime without exposing API plumbing names.
_ChatRuntimeSummary _chatSessionRuntimeSummary(
  AgentAwesomeAppController controller,
) {
  final profile = controller.runtimeProfile;
  final label = profile?.label ?? 'No profile selected';
  final serviceLabel = profile?.gateway.label ?? '';
  final endpoint = _statusNamed(controller.endpointStatuses, 'Agent API');
  final process = _statusNamed(controller.localProcessStatuses, serviceLabel);
  final state = _combinedRuntimeState(endpoint?.state, process?.state);
  final message = endpoint?.message.isNotEmpty == true
      ? endpoint!.message
      : process?.message ?? '';
  return _ChatRuntimeSummary(
    title: 'Profile',
    detail: label,
    state: state,
    icon: Icons.forum_outlined,
    message: message,
  );
}

/// Returns a status by display name.
dynamic _statusNamed(Iterable<dynamic> statuses, String name) {
  for (final status in statuses) {
    if (status.name == name) {
      return status;
    }
  }
  return null;
}

/// Combines process and endpoint availability into one user-facing state.
ConnectionStateKind _combinedRuntimeState(
  ConnectionStateKind? endpoint,
  ConnectionStateKind? process,
) {
  if (endpoint == ConnectionStateKind.connected ||
      process == ConnectionStateKind.connected) {
    return ConnectionStateKind.connected;
  }
  if (endpoint == ConnectionStateKind.disconnected ||
      process == ConnectionStateKind.disconnected) {
    return ConnectionStateKind.disconnected;
  }
  return ConnectionStateKind.unknown;
}
