/// Chat runtime summary aggregation helpers.
part of 'agent_awesome_shell.dart';

List<_ChatRuntimeSummary> _chatRuntimeSummaries(
  AgentAwesomeAppController controller,
) {
  return <_ChatRuntimeSummary>[
    _chatModelRuntimeSummary(controller),
    _chatMemoryRuntimeSummary(controller),
    _chatSessionRuntimeSummary(controller),
  ];
}

/// Returns the chat model selected by the active runtime profile.
_ChatRuntimeSummary _chatModelRuntimeSummary(
  AgentAwesomeAppController controller,
) {
  final entry = _activeModelConfigEntry(controller);
  final choice = _defaultModelChoice(entry);
  final label = choice == null ? 'No model configured' : choice.label;
  final modelName = choice?.modelName.trim() ?? '';
  final detail = modelName.isEmpty || modelName == choice?.modelId
      ? label
      : '$label - $modelName';
  return _ChatRuntimeSummary(
    title: 'Chat model',
    detail: detail,
    state: choice == null
        ? ConnectionStateKind.disconnected
        : ConnectionStateKind.connected,
    icon: Icons.memory_outlined,
    message: entry == null ? 'Select a model in Settings.' : '',
  );
}

/// Returns the default model choice from a config entry.
dynamic _defaultModelChoice(dynamic entry) {
  if (entry == null || entry.modelChoices.isEmpty) {
    return null;
  }
  for (final choice in entry.modelChoices) {
    if (choice.isDefault) {
      return choice;
    }
  }
  return entry.modelChoices.first;
}

/// Returns the memory source configured for the active runtime profile.
_ChatRuntimeSummary _chatMemoryRuntimeSummary(
  AgentAwesomeAppController controller,
) {
  final memoryServer = _activeMemoryServer(controller);
  final name = memoryServer?.label ?? 'Memory';
  final endpoint = _statusNamed(controller.endpointStatuses, name);
  final process = _statusNamed(controller.localProcessStatuses, name);
  final state = _combinedRuntimeState(endpoint?.state, process?.state);
  final message = endpoint?.message.isNotEmpty == true
      ? endpoint!.message
      : process?.message ?? '';
  return _ChatRuntimeSummary(
    title: 'Memory',
    detail: name,
    state: state,
    icon: Icons.auto_awesome_mosaic_outlined,
    message: message,
  );
}

/// Returns the first enabled memory server from the active runtime profile.
dynamic _activeMemoryServer(AgentAwesomeAppController controller) {
  final profile = controller.runtimeProfile;
  if (profile == null) {
    return null;
  }
  for (final server in profile.mcpServers) {
    if (server.enabled && server.kind == 'memory') {
      return server;
    }
  }
  return null;
}

/// Returns the active chat session runtime without exposing API plumbing names.
_ChatRuntimeSummary _chatSessionRuntimeSummary(
  AgentAwesomeAppController controller,
) {
  final gateway = controller.runtimeProfile?.gateway;
  final profile = controller.runtimeProfile;
  final label = profile?.label ?? 'No profile selected';
  final serviceLabel = gateway != null && gateway.enabled
      ? gateway.label
      : profile?.harness.label ?? '';
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

/// Returns the model config entry assigned to the active runtime profile.
dynamic _activeModelConfigEntry(AgentAwesomeAppController controller) {
  final path = controller.runtimeProfile?.harness.modelConfigPath.trim() ?? '';
  for (final entry in controller.availableModelConfigs) {
    if (entry.path == path || entry.assigned) {
      return entry;
    }
  }
  return null;
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
