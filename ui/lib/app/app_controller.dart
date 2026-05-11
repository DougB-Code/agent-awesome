/// Owns Agent Awesome UI state and coordinates service clients.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../clients/assistant_client.dart';
import '../clients/chat_title_client.dart';
import '../clients/executive_summary_client.dart';
import '../clients/mcp_client.dart';
import '../clients/screen_command_client.dart';
import '../domain/executive_summary.dart';
import '../domain/json_value.dart';
import '../domain/model_config.dart';
import '../domain/models.dart';
import '../domain/screen_command.dart';
import '../domain/task_insight_index.dart';
import '../domain/task_insight_query.dart';
import '../domain/task_projection_adapters.dart';
import '../domain/today_task_insight_metrics.dart';
import '../domain/today_state.dart';
import '../domain/user_message_text.dart';
import 'app_config.dart';
import 'app_logger.dart';
import 'app_settings.dart';
import 'chat_history.dart';
import 'config_files.dart';
import 'credential_store.dart';
import 'file_import.dart';
import 'local_model_runtime.dart';
import 'local_services.dart';
import 'model_file_capabilities.dart';
import 'onboarding_model_setup.dart';
import 'process_supervisor.dart';
import 'runtime_profile.dart';
import 'system_capabilities.dart';
import 'tool_config.dart';

const List<String> _requiredTaskProjectionTools = <String>[
  'task_graph_projection',
];

/// _TaskGraphCorrectionState groups user-correctable graph records per source.
class _TaskGraphCorrectionState {
  /// Creates graph correction records returned by one graph-backed source.
  const _TaskGraphCorrectionState({
    this.relations = const <TaskRelationRecord>[],
    this.commitments = const <TaskCommitment>[],
    this.relationSuggestions = const <TaskRelationSuggestion>[],
    this.metadataSuggestions = const <TaskMetadataSuggestion>[],
    this.commitmentSuggestions = const <TaskCommitmentSuggestion>[],
  });

  /// Explicit relation records.
  final List<TaskRelationRecord> relations;

  /// First-class commitments.
  final List<TaskCommitment> commitments;

  /// Inferred relation suggestions.
  final List<TaskRelationSuggestion> relationSuggestions;

  /// Inferred metadata suggestions.
  final List<TaskMetadataSuggestion> metadataSuggestions;

  /// Inferred commitment suggestions.
  final List<TaskCommitmentSuggestion> commitmentSuggestions;
}

/// RuntimeProfileFileEntry describes one editable profile JSON file.
class RuntimeProfileFileEntry {
  /// Creates a runtime profile file entry.
  const RuntimeProfileFileEntry({
    required this.path,
    required this.id,
    required this.label,
    required this.active,
  });

  /// Profile JSON path.
  final String path;

  /// Profile id parsed from JSON or path.
  final String id;

  /// Display label parsed from JSON or path.
  final String label;

  /// Whether the app is currently using this profile.
  final bool active;
}

/// AgentAwesomeAppController stores app state and service orchestration.
class AgentAwesomeAppController extends ChangeNotifier {
  /// Creates the app controller and its service clients.
  factory AgentAwesomeAppController({
    required AppConfig config,
    ProcessSupervisor? processSupervisor,
    AssistantClient? assistantClient,
    MemoryClient? memoryClient,
    TasksClient? tasksClient,
    ExecutiveSummaryClient? executiveSummaryClient,
    LocalServiceSupervisor? localServices,
    LocalModelRuntime? localModels,
    ConfigFileStore? configFiles,
    AgentAwesomeAppSettingsStore? appSettingsStore,
    ChatHistoryStore? chatHistoryStore,
    CredentialStore? credentialStore,
    ChatTitleClient? titleClient,
    ScreenCommandPlanner? screenCommandPlanner,
    AgentFileImporter? fileImporter,
    AppLogger? logger,
  }) {
    final effectiveLogger =
        logger ?? AppLogger(directory: config.serviceLogDirectory);
    final effectiveProcessSupervisor =
        processSupervisor ??
        ProcessSupervisor(
          logDirectory: config.serviceLogDirectory,
          workspaceRoot: config.workspaceRoot,
        );
    final commandRunner = ProcessSupervisorCommandRunner(
      effectiveProcessSupervisor,
    );
    return AgentAwesomeAppController._(
      config: config,
      processSupervisor: effectiveProcessSupervisor,
      logger: effectiveLogger,
      assistantClient:
          assistantClient ??
          AssistantClient(
            baseUrl: config.agentApiBaseUrl,
            appName: config.agentAppName,
            userId: config.agentUserId,
            logger: effectiveLogger,
          ),
      memoryClient:
          memoryClient ??
          MemoryClient(
            rpc: GatewayContextClient(
              baseUrl: config.agentGatewayContextBaseUrl,
              headers: config.gatewayAuthHeaders,
              logger: effectiveLogger,
            ),
          ),
      tasksClient:
          tasksClient ??
          TasksClient(
            rpc: GatewayContextClient(
              baseUrl: config.agentGatewayContextBaseUrl,
              headers: config.gatewayAuthHeaders,
              logger: effectiveLogger,
            ),
          ),
      executiveSummaryClient:
          executiveSummaryClient ??
          ExecutiveSummaryClient(
            rpc: GatewayContextClient(
              baseUrl: config.agentGatewayContextBaseUrl,
              headers: config.gatewayAuthHeaders,
              logger: effectiveLogger,
            ),
          ),
      localServices:
          localServices ??
          LocalServiceSupervisor(
            config: config,
            processSupervisor: effectiveProcessSupervisor,
          ),
      localModels:
          localModels ??
          LiteRtLocalModelRuntime(
            config: config,
            processSupervisor: effectiveProcessSupervisor,
          ),
      configFiles: configFiles ?? const ConfigFileStore(),
      appSettingsStore:
          appSettingsStore ?? const AgentAwesomeAppSettingsStore(),
      chatHistoryStore: chatHistoryStore ?? const ChatHistoryStore(),
      credentialStore:
          credentialStore ?? CredentialStore(commandRunner: commandRunner),
      titleClient:
          titleClient ??
          ChatTitleClient(
            localModelChatCompletionsUrl: config.localModelChatCompletionsUrl,
            logger: effectiveLogger,
          ),
      screenCommandPlanner:
          screenCommandPlanner ?? ScreenCommandClient(logger: effectiveLogger),
      fileImporter: fileImporter ?? const FileSelectorAgentFileImporter(),
      assistantClientInjected: assistantClient != null,
      memoryClientInjected: memoryClient != null,
      tasksClientInjected: tasksClient != null,
      executiveSummaryClientInjected: executiveSummaryClient != null,
      screenCommandPlannerInjected: screenCommandPlanner != null,
    );
  }

  /// Creates the controller after dependencies have been resolved once.
  AgentAwesomeAppController._({
    required this.config,
    required this.processSupervisor,
    required this.logger,
    required this.assistantClient,
    required this.memoryClient,
    required this.tasksClient,
    required this.executiveSummaryClient,
    required this.localServices,
    required this.localModels,
    required this.configFiles,
    required this.appSettingsStore,
    required this.chatHistoryStore,
    required this.credentialStore,
    required this.titleClient,
    required this.screenCommandPlanner,
    required this.fileImporter,
    required bool assistantClientInjected,
    required bool memoryClientInjected,
    required bool tasksClientInjected,
    required bool executiveSummaryClientInjected,
    required bool screenCommandPlannerInjected,
  }) : _assistantClientInjected = assistantClientInjected,
       _memoryClientInjected = memoryClientInjected,
       _tasksClientInjected = tasksClientInjected,
       _executiveSummaryClientInjected = executiveSummaryClientInjected,
       _screenCommandPlannerInjected = screenCommandPlannerInjected;

  /// Runtime service configuration.
  final AppConfig config;

  /// File logger for UI and client diagnostics.
  final AppLogger logger;

  /// Shared owner for all app-started subprocesses.
  final ProcessSupervisor processSupervisor;

  /// ADK assistant client.
  AssistantClient assistantClient;

  /// Memory MCP client.
  MemoryClient memoryClient;

  /// Client for graph-backed task tools exposed by the memory service.
  TasksClient tasksClient;

  /// Client for the canonical Today projection tools.
  ExecutiveSummaryClient executiveSummaryClient;

  /// Local process supervisor for the pilot service stack.
  final LocalServiceSupervisor localServices;

  /// Local model installer and runtime supervisor.
  final LocalModelRuntime localModels;

  /// File store for editable model and agent configurations.
  final ConfigFileStore configFiles;

  /// Store for app-owned settings.
  final AgentAwesomeAppSettingsStore appSettingsStore;

  /// Store for local cross-profile chat metadata.
  final ChatHistoryStore chatHistoryStore;

  /// Store for display-safe provider credential lookups.
  final CredentialStore credentialStore;

  /// Client used for app-owned chat title generation.
  final ChatTitleClient titleClient;

  /// Client used for structured current-screen AI command planning.
  final ScreenCommandPlanner screenCommandPlanner;

  /// Imports source files through the platform file picker.
  final AgentFileImporter fileImporter;

  final bool _assistantClientInjected;
  final bool _memoryClientInjected;
  final bool _tasksClientInjected;
  final bool _executiveSummaryClientInjected;
  final bool _screenCommandPlannerInjected;

  /// Active runtime profile for harness configs and MCP topology.
  RuntimeProfile? runtimeProfile;

  /// Filesystem path for the loaded runtime profile.
  String runtimeProfilePath = '';

  /// Profile files available in the app config directory.
  List<String> availableProfilePaths = const <String>[];

  /// Runtime profile files available in the app config directory.
  List<RuntimeProfileFileEntry> availableProfiles =
      const <RuntimeProfileFileEntry>[];

  /// Model config files available in the app config directory.
  List<ConfigFileEntry> availableModelConfigs = const <ConfigFileEntry>[];

  /// Agent config files available in the app config directory.
  List<ConfigFileEntry> availableAgentConfigs = const <ConfigFileEntry>[];

  /// Tool config files available in the app config directory.
  List<ConfigFileEntry> availableToolConfigs = const <ConfigFileEntry>[];

  /// App-specific settings outside runtime profile ownership.
  AgentAwesomeAppSettings appSettings = const AgentAwesomeAppSettings();

  Future<void>? _initialization;
  bool _initialized = false;
  bool _shellDecisionReady = false;
  bool _clientsClosed = false;
  Future<void>? _localServicesCloseFuture;
  Future<void>? _localModelsCloseFuture;
  Future<void>? _closeFuture;
  bool _closing = false;

  /// All known chat sessions.
  List<ChatSession> sessions = const <ChatSession>[];

  /// App-owned chat metadata across profiles.
  List<ChatHistoryEntry> chatHistory = const <ChatHistoryEntry>[];

  /// Currently selected chat session id.
  String? selectedSessionId;

  /// Current chat messages.
  List<ChatMessage> messages = const <ChatMessage>[];

  /// In-memory task ids created while a chat is active.
  final Map<String, Set<String>> _chatTaskIds = <String, Set<String>>{};

  /// Home execution steps.
  List<WorkspaceTask> executionSteps = const <WorkspaceTask>[];

  /// Focused project workspace state.
  ProjectWorkspace workspace = const ProjectWorkspace(
    title: 'Workspace',
    subtitle: 'Live connected workspace',
    tasks: <WorkspaceTask>[],
    sources: <SourceItem>[],
    memoryRecords: <MemoryRecord>[],
  );

  /// Active task queue filters.
  TaskFilterState taskFilters = const TaskFilterState();

  /// Active semantic task insight preset for Queue.
  String taskInsightPresetId = TaskInsightIds.all;

  /// Latest canonical projection graph shared by task views.
  TaskProjectionGraph taskProjectionGraph = const TaskProjectionGraph();

  /// Latest task insight read model shared by task views.
  TaskInsightIndex taskInsightIndex = TaskInsightIndex.empty;

  /// Latest named insight summaries.
  List<TaskInsightQuerySummary> taskInsightSummaries =
      const <TaskInsightQuerySummary>[];

  /// Latest task stream projection.
  TaskStreamProjection taskStreamProjection = const TaskStreamProjection();

  /// Latest priority terrain projection.
  PriorityTerrainProjection priorityTerrainProjection =
      const PriorityTerrainProjection();

  /// Latest task constellation projection.
  TaskConstellationProjection taskConstellationProjection =
      const TaskConstellationProjection();

  /// Latest canonical Today projection state.
  TodayState todayState = const TodayState();

  /// Last task projection loading problem.
  String taskProjectionMessage = '';

  /// Last task insight consistency or loading problem.
  String taskInsightMessage = '';

  /// Explicit task relations loaded from the task graph service.
  List<TaskRelationRecord> taskRelations = const <TaskRelationRecord>[];

  /// First-class commitments loaded from the task graph service.
  List<TaskCommitment> taskCommitments = const <TaskCommitment>[];

  /// Inferred relation suggestions awaiting user review.
  List<TaskRelationSuggestion> taskRelationSuggestions =
      const <TaskRelationSuggestion>[];

  /// Inferred metadata suggestions awaiting user review.
  List<TaskMetadataSuggestion> taskMetadataSuggestions =
      const <TaskMetadataSuggestion>[];

  /// Inferred commitment suggestions awaiting user review.
  List<TaskCommitmentSuggestion> taskCommitmentSuggestions =
      const <TaskCommitmentSuggestion>[];

  /// Currently selected graph backlog item id.
  String? selectedTaskId;

  /// Currently selected task constellation relation edge.
  TaskConstellationEdge? selectedTaskConstellationEdge;

  /// Current graph backlog selection kind.
  String taskSelectionKind = 'task';

  /// Whether a backlog operation is currently running.
  bool tasksBusy = false;

  /// Last backlog-specific operation message.
  String tasksMessage = 'Backlog is ready';

  /// Whether a structured Backlog screen command is currently planning.
  bool screenCommandBusy = false;

  /// Last Backlog screen-command status message.
  String screenCommandMessage = 'Screen AI is ready';

  /// Latest Backlog screen-command run held for review.
  ScreenCommandRun? activeScreenCommandRun;

  /// Whether the Backlog side pane is showing review changes.
  bool backlogReviewPanelOpen = false;

  /// Whether Backlog is showing the auxiliary chat pane.
  bool backlogChatPanelOpen = false;

  /// Task id requested by the review panel for queue focus.
  String focusedBacklogTaskId = '';

  /// Change id requested by the review panel for queue focus.
  String focusedScreenChangeId = '';

  /// Active memory retrieval and stewardship filters.
  MemoryFilterState memoryFilters = const MemoryFilterState();

  /// Currently selected memory record id.
  String? selectedMemoryId;

  /// Last loaded compiled entity page or timeline.
  CompiledMemoryPage? selectedMemoryPage;

  /// Whether a memory operation is currently running.
  bool memoryBusy = false;

  /// Last memory-specific operation message.
  String memoryMessage = 'Memory is ready for review';

  /// Endpoint statuses displayed in settings.
  List<EndpointStatus> endpointStatuses = const <EndpointStatus>[];

  /// Local service process statuses displayed in settings.
  List<ServiceProcessStatus> localProcessStatuses =
      const <ServiceProcessStatus>[];

  /// Tool names advertised by the active primary memory MCP endpoint.
  Set<String> primaryMemoryToolNames = const <String>{};

  /// Pending ADK confirmation request.
  ConfirmationRequest? pendingConfirmation;

  /// Whether a message is currently streaming.
  bool sending = false;

  /// Last high-level error for status display.
  String statusMessage = 'Preparing managed runtime';

  /// Loads initial service data from connected services.
  Future<void> initialize() async {
    if (_isClosing) {
      return;
    }
    _initialization ??= _initialize();
    return _initialization!;
  }

  /// Returns whether startup settings have resolved the initial app shell.
  bool get shellDecisionReady {
    return _shellDecisionReady;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await initialize();
  }

  /// Returns whether app-managed runtime shutdown has started.
  bool get _isClosing {
    return _closing || processSupervisor.isClosing;
  }

  /// Rejects work that could start subprocesses during shutdown.
  void _throwIfClosing() {
    if (_isClosing) {
      throw StateError('Agent Awesome runtime is shutting down');
    }
  }

  Future<void> _initialize() async {
    await _log('initialize start');
    localProcessStatuses = const <ServiceProcessStatus>[];
    try {
      appSettings = await appSettingsStore.load();
      _shellDecisionReady = true;
      notifyListeners();
      chatHistory = await chatHistoryStore.load();
      await _log(
        'loaded chat history ${chatHistory.length} from ${chatHistoryPath()}',
      );
      final loader = RuntimeProfileLoader(config);
      final profileFile = await _resolveInitialProfileFile(loader);
      await _log('resolved runtime profile ${profileFile.path}');
      runtimeProfilePath = profileFile.path;
      runtimeProfile = await loader.loadFile(profileFile);
      runtimeProfile = await _migrateDefaultProfileConfigs(runtimeProfile!);
      await _refreshConfigCollections();
      _configureClientsForRuntimeProfile(runtimeProfile!);
      await _log('loaded runtime profile ${runtimeProfile!.id}');
    } catch (error) {
      await _log('runtime profile load failed: $error');
      _shellDecisionReady = true;
      runtimeProfile = null;
      runtimeProfilePath = config.runtimeProfilePath;
      endpointStatuses = <EndpointStatus>[
        EndpointStatus(
          name: 'Runtime Profile',
          url: config.runtimeProfilePath,
          state: ConnectionStateKind.disconnected,
          message: error.toString(),
        ),
      ];
      localProcessStatuses = const <ServiceProcessStatus>[];
      statusMessage = 'Runtime profile failed to load: $error';
      _initialized = true;
      notifyListeners();
      return;
    }
    endpointStatuses = <EndpointStatus>[
      EndpointStatus(
        name: 'Agent API',
        url: runtimeProfile!.harness.apiBaseUrl,
        state: ConnectionStateKind.unknown,
      ),
      for (final server in runtimeProfile!.mcpServers.where(
        (server) => server.enabled,
      ))
        EndpointStatus(
          name: server.label,
          url: server.endpoint,
          state: ConnectionStateKind.unknown,
        ),
    ];
    notifyListeners();
    if (_isClosing) {
      statusMessage = 'Agent Awesome runtime is shutting down';
      _initialized = true;
      notifyListeners();
      return;
    }
    try {
      _throwIfClosing();
      await _log('starting required local services');
      localProcessStatuses = await localServices.startRequiredServices(
        runtimeProfile!,
        restartAutoStarted: true,
      );
      for (final status in localProcessStatuses) {
        await _log(
          'service status ${status.name} ${status.state.name}: ${status.message}',
        );
      }
    } catch (error) {
      await _log('local service startup failed: $error');
      localProcessStatuses = <ServiceProcessStatus>[
        ServiceProcessStatus(
          name: 'Local Services',
          url: config.workspaceRoot,
          state: ConnectionStateKind.disconnected,
          message: error.toString(),
        ),
      ];
    }
    try {
      await _startConfiguredLocalModelRuntime();
    } catch (error) {
      if (_isClosing) {
        statusMessage = 'Agent Awesome runtime is shutting down';
        _initialized = true;
        notifyListeners();
        return;
      }
      await _log('local model startup failed: $error');
    }
    notifyListeners();
    await _loadToolCapabilities();
    await _log('loading sessions, memory, and tasks');
    await Future.wait(<Future<void>>[
      _loadSessions(),
      _loadMemory(),
      _loadTasks(),
    ]);
    _initialized = true;
    await _log('initialize complete');
  }

  /// Resolves the startup profile from env override, app default, or template.
  Future<File> _resolveInitialProfileFile(RuntimeProfileLoader loader) async {
    if (config.runtimeProfilePath.trim().isNotEmpty) {
      return loader.resolveProfileFile();
    }
    final defaultChatProfile = appSettings.defaultChatProfilePath.trim();
    if (defaultChatProfile.isNotEmpty) {
      final file = File(defaultChatProfile);
      if (await file.exists()) {
        return file;
      }
      await _log('default chat profile missing: $defaultChatProfile');
    }
    return loader.resolveProfileFile();
  }

  /// Lists editable runtime profiles from the app config directory.
  Future<List<String>> listRuntimeProfilePaths() async {
    final directory = Directory(runtimeProfilesDirectoryPath());
    if (!await directory.exists()) {
      return const <String>[];
    }
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    return files.map((file) => file.path).toList();
  }

  /// Lists editable runtime profiles with labels parsed from profile JSON.
  Future<List<RuntimeProfileFileEntry>> listRuntimeProfileFiles() async {
    final paths = await listRuntimeProfilePaths();
    final entries = <RuntimeProfileFileEntry>[];
    for (final path in paths) {
      entries.add(await _profileEntryForPath(path));
    }
    if (runtimeProfilePath.isNotEmpty &&
        !entries.any((entry) => entry.path == runtimeProfilePath)) {
      entries.insert(0, await _profileEntryForPath(runtimeProfilePath));
    }
    return entries;
  }

  /// Starts an already installed local model when the active config selects it.
  Future<void> _startConfiguredLocalModelRuntime() async {
    _throwIfClosing();
    final provider = await _activeLocalProviderConfig();
    if (provider == null) {
      return;
    }
    final descriptor = onboardingLocalModelDescriptor(provider.defaultModel);
    if (!await localModels.isInstalled(descriptor)) {
      final status = ServiceProcessStatus(
        name: 'Local model',
        url: config.localModelHealthUrl,
        state: ConnectionStateKind.disconnected,
        message: '${descriptor.displayName} is not installed',
      );
      localProcessStatuses = <ServiceProcessStatus>[
        ...localProcessStatuses.where((item) => item.name != 'Local model'),
        status,
      ];
      await _log('local model not installed: ${descriptor.id}');
      return;
    }
    final status = await localModels.start(descriptor);
    localProcessStatuses = <ServiceProcessStatus>[
      ...localProcessStatuses.where((item) => item.name != 'Local model'),
      status,
    ];
    await _log('local model status ${status.state.name}: ${status.message}');
  }

  /// Returns the active local provider from the current model config.
  Future<ModelProviderConfig?> _activeLocalProviderConfig() async {
    final profile = runtimeProfile;
    if (profile == null) {
      return null;
    }
    final path = profile.harness.modelConfigPath.trim();
    if (path.isEmpty) {
      return null;
    }
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final document = ModelConfigDocument.parse(await file.readAsString());
    final defaultProvider = document.defaultRef.split(':').first.trim();
    if (defaultProvider != 'local') {
      return null;
    }
    for (final provider in document.providers) {
      if (provider.id == defaultProvider && provider.adapter == 'litert') {
        return provider;
      }
    }
    return null;
  }

  /// Reloads profile, model, and agent file collection metadata.
  Future<void> _refreshConfigCollections() async {
    final profile = runtimeProfile;
    availableProfilePaths = await listRuntimeProfilePaths();
    availableProfiles = await listRuntimeProfileFiles();
    availableModelConfigs = await configFiles.list(
      kind: ConfigFileKind.model,
      assignedPath: profile?.harness.modelConfigPath ?? '',
    );
    availableAgentConfigs = await configFiles.list(
      kind: ConfigFileKind.agent,
      assignedPath: profile?.harness.agentConfigPath ?? '',
    );
    availableToolConfigs = await configFiles.list(
      kind: ConfigFileKind.tool,
      assignedPath: profile?.harness.toolConfigPath ?? '',
    );
  }

  /// Refreshes file-backed profile, model, and agent collections.
  Future<void> refreshConfigurationCollections() async {
    await _refreshConfigCollections();
    notifyListeners();
  }

  /// Returns the profile path used by one-click new chat creation.
  String get defaultChatProfilePath {
    final configured = appSettings.defaultChatProfilePath.trim();
    return configured.isEmpty ? runtimeProfilePath : configured;
  }

  /// Returns the model config path used for app-owned chat title summaries.
  String get summaryModelConfigPath {
    final configured = appSettings.summaryModelConfigPath.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    return runtimeProfile?.harness.modelConfigPath.trim() ?? '';
  }

  /// Returns the provider:model ref used for app-owned chat title summaries.
  String get summaryModelRef {
    return appSettings.summaryModelRef.trim();
  }

  /// Returns whether the first-launch setup guide should stay hidden.
  bool get gettingStartedCompleted {
    return appSettings.gettingStartedCompleted;
  }

  /// Returns whether the active profile has at least one selectable model.
  bool get hasConfiguredModel {
    final profile = runtimeProfile;
    if (profile == null) {
      return false;
    }
    final modelConfigPath = profile.harness.modelConfigPath.trim();
    if (modelConfigPath.isEmpty) {
      return false;
    }
    for (final entry in availableModelConfigs) {
      if (entry.path == modelConfigPath || entry.assigned) {
        return entry.modelChoices.isNotEmpty;
      }
    }
    return false;
  }

  /// Returns whether the UI should allow user-initiated chat entry points.
  bool get canStartChat {
    return true;
  }

  /// Returns the standard user-facing message for model-gated surfaces.
  String get modelRequiredMessage {
    return 'Set up a model to use model-backed responses.';
  }

  /// Returns the current reason chat entry points are unavailable.
  String get chatUnavailableMessage {
    return modelRequiredMessage;
  }

  /// Returns the selected chat history key, if a chat is active.
  String get selectedChatKey {
    final sessionId = selectedSessionId;
    if (sessionId == null || sessionId.isEmpty || runtimeProfilePath.isEmpty) {
      return '';
    }
    return _chatHistoryKey(runtimeProfilePath, sessionId);
  }

  /// Returns the selected chat history entry, if it exists.
  ChatHistoryEntry? get selectedChatEntry {
    final key = selectedChatKey;
    if (key.isEmpty) {
      return null;
    }
    for (final entry in chatHistory) {
      if (entry.key == key) {
        return entry;
      }
    }
    return null;
  }

  /// Saves app-owned settings.
  Future<void> saveAppSettings(AgentAwesomeAppSettings settings) async {
    appSettings = settings;
    await appSettingsStore.save(settings);
    statusMessage = 'App settings saved';
    notifyListeners();
  }

  /// Selects the default runtime profile for fast-path new chats.
  Future<void> setDefaultChatProfile(String profilePath) async {
    await saveAppSettings(
      appSettings.copyWith(defaultChatProfilePath: profilePath.trim()),
    );
  }

  /// Selects the app-owned model config for chat title summaries.
  Future<void> setSummaryModelConfig(String modelConfigPath) async {
    await saveAppSettings(
      appSettings.copyWith(summaryModelConfigPath: modelConfigPath.trim()),
    );
  }

  /// Selects the exact app-owned model for chat title summaries.
  Future<void> setSummaryModelSelection({
    required String modelConfigPath,
    required String modelRef,
  }) async {
    await saveAppSettings(
      appSettings.copyWith(
        summaryModelConfigPath: modelConfigPath.trim(),
        summaryModelRef: modelRef.trim(),
      ),
    );
  }

  /// Enables or disables app-owned chat title summarization.
  Future<void> setChatTitleSummariesEnabled(bool enabled) async {
    await saveAppSettings(
      appSettings.copyWith(chatTitleSummariesEnabled: enabled),
    );
  }

  /// Shows or hides the first-launch setup guide.
  Future<void> setGettingStartedCompleted(bool completed) async {
    await saveAppSettings(
      appSettings.copyWith(gettingStartedCompleted: completed),
    );
  }

  /// Reads local system capability facts through supervised probes.
  Future<SystemCapabilitySnapshot> readSystemCapabilities() {
    return SystemCapabilityReader(
      commandRunner: ProcessSupervisorCommandRunner(processSupervisor),
    ).read();
  }

  /// Resolves one credential reference for display or explicit reveal.
  Future<CredentialLookup> lookupCredential(String reference) {
    return credentialStore.lookup(reference);
  }

  /// Stores one provider credential in the app-owned credential store.
  Future<CredentialMutationResult> storeCredential({
    required String reference,
    required String secret,
  }) {
    return credentialStore.store(reference: reference, secret: secret);
  }

  /// Deletes one provider credential from the app-owned credential store.
  Future<CredentialMutationResult> deleteCredential(String reference) {
    return credentialStore.delete(reference);
  }

  /// Stores a cloud API key and makes the selected model the active default.
  Future<OnboardingModelSetupResult> configureOnboardingCloudModel({
    required String providerId,
    required String modelId,
    required String apiKey,
  }) async {
    if (_isClosing) {
      return const OnboardingModelSetupResult(
        success: false,
        message: 'Agent Awesome runtime is shutting down',
      );
    }
    final provider = onboardingCloudProviderById(providerId);
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      return const OnboardingModelSetupResult(
        success: false,
        message: 'API key is required',
      );
    }
    final credentialResult = await credentialStore.store(
      reference: provider.credentialReference,
      secret: trimmedKey,
    );
    if (!credentialResult.success) {
      return OnboardingModelSetupResult(
        success: false,
        message: credentialResult.message,
        providerName: provider.name,
        modelId: modelId,
      );
    }
    final result = await _saveOnboardingProviderConfig(
      provider.toProviderConfig(modelId: modelId),
    );
    if (!result.success) {
      return result;
    }
    return OnboardingModelSetupResult(
      success: true,
      message: 'Model connection saved',
      providerName: provider.name,
      modelId: provider.modelForId(modelId).id,
    );
  }

  /// Makes a local LiteRT model artifact the active default.
  Future<OnboardingModelSetupResult> configureOnboardingLocalModel({
    required String modelId,
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    if (_isClosing) {
      return const OnboardingModelSetupResult(
        success: false,
        message: 'Agent Awesome runtime is shutting down',
        providerName: 'Local model',
      );
    }
    final model = onboardingLocalModelById(modelId);
    final descriptor = onboardingLocalModelDescriptor(model.id);
    late final LocalModelInstall install;
    late final String executable;
    try {
      _throwIfClosing();
      install = await localModels.ensureInstalled(
        descriptor,
        onProgress: onProgress,
      );
      _throwIfClosing();
      executable = await const LocalModelExecutableResolver().resolve(
        configuredExecutable: config.litertLmExecutable,
        dataDirectory: agentAwesomeDataDirectoryPath(),
      );
    } catch (error) {
      return OnboardingModelSetupResult(
        success: false,
        message: error.toString(),
        providerName: 'Local model',
        modelId: model.id,
      );
    }
    onProgress?.call(
      const LocalModelInstallProgress(
        phase: 'saving',
        message: 'Saving local model configuration',
      ),
    );
    final result = await _saveOnboardingProviderConfig(
      onboardingLocalProviderConfig(
        modelId: model.id,
        executable: executable,
        modelPath: install.modelPath,
      ),
    );
    if (!result.success) {
      return result;
    }
    return OnboardingModelSetupResult(
      success: true,
      message: 'Local model saved',
      providerName: 'Local model',
      modelId: model.id,
    );
  }

  /// Writes the active model provider into the current model config file.
  Future<OnboardingModelSetupResult> _saveOnboardingProviderConfig(
    ModelProviderConfig provider,
  ) async {
    final profile = runtimeProfile;
    if (profile == null) {
      return const OnboardingModelSetupResult(
        success: false,
        message: 'Runtime profile is not loaded',
      );
    }
    final path = profile.harness.modelConfigPath.trim();
    if (path.isEmpty) {
      return const OnboardingModelSetupResult(
        success: false,
        message: 'Model config path is not configured',
      );
    }
    final file = File(path);
    final content = await file.exists() ? await file.readAsString() : '';
    final document = ModelConfigDocument.parse(content);
    final providers = await _configuredModelProviders(
      document,
      replacingProvider: provider,
    );
    final next = document.copyWith(
      defaultRef: modelProviderDefaultRef(provider),
      providers: providers,
    );
    final validationError = modelConfigValidationError(next);
    if (validationError.isNotEmpty) {
      return OnboardingModelSetupResult(
        success: false,
        message: validationError,
        providerName: provider.displayName,
        modelId: provider.defaultModel,
      );
    }
    await saveConfigurationFile(path, next.toYaml());
    await refreshConfigurationCollections();
    statusMessage = 'Model configured: ${provider.displayName}';
    notifyListeners();
    return OnboardingModelSetupResult(
      success: true,
      message: 'Model config saved',
      providerName: provider.displayName,
      modelId: provider.defaultModel,
    );
  }

  /// Saves the active runtime profile JSON and reconnects owned clients.
  Future<void> saveRuntimeProfile(RuntimeProfile profile) async {
    final path = runtimeProfilePath.trim().isEmpty
        ? RuntimeProfileLoader(config).defaultRuntimeProfilePath()
        : runtimeProfilePath;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(encodeRuntimeProfileJson(profile));
    runtimeProfilePath = path;
    runtimeProfile = profile;
    await _refreshConfigCollections();
    _configureClientsForRuntimeProfile(profile);
    _refreshEndpointSkeleton(profile);
    statusMessage = 'Runtime profile saved';
    notifyListeners();
  }

  /// Loads a different profile from disk and applies its runtime bindings.
  Future<void> loadRuntimeProfileFromPath(
    String path, {
    bool reloadData = true,
  }) async {
    final file = File(path);
    final profile = await RuntimeProfileLoader(config).loadFile(file);
    runtimeProfilePath = file.path;
    runtimeProfile = profile;
    await _refreshConfigCollections();
    _configureClientsForRuntimeProfile(profile);
    _refreshEndpointSkeleton(profile);
    statusMessage = 'Runtime profile loaded';
    notifyListeners();
    if (reloadData) {
      await _loadToolCapabilities();
      await Future.wait(<Future<void>>[
        _loadSessions(),
        _loadMemory(),
        _loadTasks(),
      ]);
    }
  }

  /// Reads a text configuration file referenced by the active profile.
  Future<String> readConfigurationFile(String path) async {
    return configFiles.read(path);
  }

  /// Saves a text configuration file referenced by the active profile.
  Future<void> saveConfigurationFile(String path, String content) async {
    await configFiles.write(path, content);
    statusMessage = 'Saved $path';
    notifyListeners();
  }

  /// Creates a new runtime profile file copied from the active profile.
  Future<void> createRuntimeProfileFile() async {
    final profile = _activeRuntimeProfile();
    final directory = Directory(runtimeProfilesDirectoryPath());
    await directory.create(recursive: true);
    final nextPath = await _uniqueRuntimeProfilePath(
      directory.path,
      profile.id,
    );
    final nextId = _profileIdFromPath(nextPath);
    final next = profile.copyWith(id: nextId, label: 'New Profile');
    await File(nextPath).writeAsString(encodeRuntimeProfileJson(next));
    await loadRuntimeProfileFromPath(nextPath);
  }

  /// Duplicates the active runtime profile file and loads the duplicate.
  Future<void> duplicateRuntimeProfileFile() async {
    final profile = _activeRuntimeProfile();
    final directory = Directory(runtimeProfilesDirectoryPath());
    await directory.create(recursive: true);
    final nextPath = await _uniqueRuntimeProfilePath(
      directory.path,
      profile.id,
    );
    final nextId = _profileIdFromPath(nextPath);
    final next = profile.copyWith(id: nextId, label: '${profile.label} Copy');
    await File(nextPath).writeAsString(encodeRuntimeProfileJson(next));
    await loadRuntimeProfileFromPath(nextPath);
  }

  /// Deletes the active runtime profile file and loads another available file.
  Future<void> deleteActiveRuntimeProfileFile() async {
    final paths = await listRuntimeProfilePaths();
    if (paths.length <= 1) {
      throw const FileSystemException('Cannot delete the only runtime profile');
    }
    final current = runtimeProfilePath;
    final nextPath = paths.firstWhere((path) => path != current);
    await File(current).delete();
    await loadRuntimeProfileFromPath(nextPath);
  }

  /// Creates a new model or agent config file.
  Future<String> createConfigFile(ConfigFileKind kind) async {
    final path = await configFiles.create(kind);
    await _refreshConfigCollections();
    notifyListeners();
    return path;
  }

  /// Duplicates a model or agent config file.
  Future<String> duplicateConfigFile(ConfigFileEntry entry) async {
    final path = await configFiles.duplicate(entry.path, entry.kind);
    await _refreshConfigCollections();
    notifyListeners();
    return path;
  }

  /// Deletes a model or agent config file when it is not actively assigned.
  Future<void> deleteConfigFile(ConfigFileEntry entry) async {
    final profile = _activeRuntimeProfile();
    if (entry.path == profile.harness.modelConfigPath ||
        entry.path == profile.harness.agentConfigPath ||
        entry.path == profile.harness.toolConfigPath) {
      throw FileSystemException(
        'Cannot delete an assigned config file',
        entry.path,
      );
    }
    await configFiles.delete(entry.path);
    await _refreshConfigCollections();
    notifyListeners();
  }

  /// Assigns a model or agent config file to the active profile.
  Future<void> assignConfigFile(ConfigFileEntry entry) async {
    await _assignConfigFile(entry.kind, entry.path);
  }

  /// Saves one required memory server config file.
  Future<void> saveRequiredServerRuntime({
    required String originalId,
    required McpServerRuntime server,
  }) async {
    final profile = _activeRuntimeProfile();
    final index = profile.mcpServers.indexWhere(
      (candidate) => candidate.id == originalId,
    );
    if (index < 0) {
      throw FileSystemException('MCP server is not referenced', originalId);
    }
    final servers = <McpServerRuntime>[
      for (var i = 0; i < profile.mcpServers.length; i++)
        i == index ? server : profile.mcpServers[i],
    ];
    await _saveRequiredServer(profile, server);
    _applyRuntimeProfileServers(profile.copyWith(mcpServers: servers));
    statusMessage = '${server.kind} server saved';
    notifyListeners();
  }

  /// Enables the selected MCP server for its runtime role.
  Future<void> assignMcpServerForKind(McpServerRuntime selected) async {
    final profile = _activeRuntimeProfile();
    final servers = <McpServerRuntime>[
      for (final server in profile.mcpServers)
        server.kind == selected.kind
            ? server.copyWith(enabled: server.id == selected.id)
            : server,
    ];
    for (var index = 0; index < servers.length; index++) {
      if (servers[index].enabled != profile.mcpServers[index].enabled) {
        await _saveRequiredServer(profile, servers[index]);
      }
    }
    _applyRuntimeProfileServers(profile.copyWith(mcpServers: servers));
    statusMessage = '${selected.kind} server assigned';
    notifyListeners();
  }

  /// Renames a model or agent config file and updates active assignments.
  Future<String> renameConfigFile(ConfigFileEntry entry, String name) async {
    final nextPath = await configFiles.rename(entry, name);
    final profile = _activeRuntimeProfile();
    var harness = profile.harness;
    if (profile.harness.modelConfigPath == entry.path) {
      harness = harness.copyWith(modelConfigPath: nextPath);
    }
    if (profile.harness.agentConfigPath == entry.path) {
      harness = harness.copyWith(agentConfigPath: nextPath);
    }
    if (profile.harness.toolConfigPath == entry.path) {
      harness = harness.copyWith(toolConfigPath: nextPath);
    }
    runtimeProfile = profile.copyWith(harness: harness);
    await saveRuntimeProfile(runtimeProfile!);
    return nextPath;
  }

  /// Assigns a config path to the active profile for a config kind.
  Future<void> _assignConfigFile(ConfigFileKind kind, String path) async {
    final profile = _activeRuntimeProfile();
    final harness = switch (kind) {
      ConfigFileKind.model => profile.harness.copyWith(modelConfigPath: path),
      ConfigFileKind.agent => profile.harness.copyWith(agentConfigPath: path),
      ConfigFileKind.tool => profile.harness.copyWith(toolConfigPath: path),
    };
    await saveRuntimeProfile(profile.copyWith(harness: harness));
  }

  /// Migrates default profile config files into app-owned editable locations.
  Future<RuntimeProfile> _migrateDefaultProfileConfigs(
    RuntimeProfile profile,
  ) async {
    if (config.runtimeProfilePath.trim().isNotEmpty) {
      return profile;
    }
    final storageProfile = _withDefaultMemoryStorage(profile);
    final harness = profile.harness;
    final modelPath = await _ensureSharedModelConfig(
      sourcePath: harness.modelConfigPath,
    );
    final agentPath = await _copyConfigIntoAppDirectory(
      sourcePath: harness.agentConfigPath,
      targetDirectory: agentConfigsDirectoryPath(),
      targetName: '${profile.id}-agent.yaml',
    );
    final toolPath = await _copyConfigIntoAppDirectory(
      sourcePath: harness.toolConfigPath,
      targetDirectory: toolConfigsDirectoryPath(),
      targetName: '${profile.id}-tool.yaml',
    );
    final serverPaths = await _copyRequiredServerConfigsIntoAppDirectory(
      storageProfile,
    );
    final graphToolPath = await _writeDefaultGraphToolConfig(
      profile: storageProfile,
      requestedPath: toolPath ?? harness.toolConfigPath,
      targetName: '${profile.id}-tool.yaml',
    );
    final next = storageProfile.copyWith(
      harness: harness.copyWith(
        modelConfigPath: modelPath,
        agentConfigPath: agentPath ?? harness.agentConfigPath,
        toolConfigPath: graphToolPath,
      ),
      memoryServerConfigPath: serverPaths.memoryServerConfigPath,
    );
    if (next.harness.modelConfigPath != harness.modelConfigPath ||
        next.harness.agentConfigPath != harness.agentConfigPath ||
        next.harness.toolConfigPath != harness.toolConfigPath ||
        next.memoryServerConfigPath != profile.memoryServerConfigPath) {
      final file = File(runtimeProfilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(encodeRuntimeProfileJson(next));
    }
    return next;
  }

  /// Places default managed memory files in the OS app data directory.
  RuntimeProfile _withDefaultMemoryStorage(RuntimeProfile profile) {
    return profile.copyWith(
      mcpServers: profile.mcpServers.map((server) {
        if (server.kind != 'memory' || !server.autoStart) {
          return server;
        }
        return server.copyWith(
          arguments: _memoryStorageArguments(server.arguments),
        );
      }).toList(),
    );
  }

  /// Creates or migrates the shared model config referenced by all profiles.
  Future<String> _ensureSharedModelConfig({required String sourcePath}) async {
    final target = File(defaultModelConfigPath());
    await target.parent.create(recursive: true);
    if (!await target.exists()) {
      final document = await _configuredModelDocumentFromSource(sourcePath);
      await target.writeAsString(document.toYaml());
    }
    return target.path;
  }

  /// Reads configured model providers from a source config file.
  Future<ModelConfigDocument> _configuredModelDocumentFromSource(
    String sourcePath,
  ) async {
    final path = sourcePath.trim();
    if (path.isEmpty) {
      return emptyModelConfigDocument();
    }
    final source = File(path);
    if (!await source.exists()) {
      return emptyModelConfigDocument();
    }
    final document = ModelConfigDocument.parse(await source.readAsString());
    return _modelDocumentWithConfiguredProviders(
      document,
      await _configuredModelProviders(document),
    );
  }

  /// Keeps only model providers the app can prove were configured.
  Future<List<ModelProviderConfig>> _configuredModelProviders(
    ModelConfigDocument document, {
    ModelProviderConfig? replacingProvider,
  }) async {
    final providers = <ModelProviderConfig>[];
    for (final candidate in document.providers) {
      if (candidate.id == replacingProvider?.id) {
        continue;
      }
      if (await _isConfiguredModelProvider(candidate)) {
        providers.add(candidate);
      }
    }
    if (replacingProvider != null) {
      providers.add(replacingProvider);
    }
    return providers;
  }

  /// Returns whether a provider has local runtime or stored credential backing.
  Future<bool> _isConfiguredModelProvider(ModelProviderConfig provider) async {
    if (provider.id == 'local') {
      return true;
    }
    if (provider.apiKey.trim().isEmpty) {
      return false;
    }
    if (_isClosing) {
      return false;
    }
    final lookup = await credentialStore.lookup(provider.apiKey);
    return lookup.found;
  }

  /// Builds a model document whose default points at an available provider.
  ModelConfigDocument _modelDocumentWithConfiguredProviders(
    ModelConfigDocument document,
    List<ModelProviderConfig> providers,
  ) {
    final refs = <String>{
      for (final provider in providers)
        for (final model in provider.models) '${provider.id}:${model.id}',
    };
    final defaultRef = refs.contains(document.defaultRef)
        ? document.defaultRef
        : providers.isEmpty
        ? ''
        : modelProviderDefaultRef(providers.first);
    return document.copyWith(defaultRef: defaultRef, providers: providers);
  }

  /// Rewrites memory daemon storage arguments while preserving other flags.
  List<String> _memoryStorageArguments(List<String> arguments) {
    final withoutStorageFlags = <String>[];
    for (var index = 0; index < arguments.length; index++) {
      final value = arguments[index];
      if (value == '--db' || value == '--data') {
        index++;
        continue;
      }
      withoutStorageFlags.add(value);
    }
    return <String>[
      ...withoutStorageFlags,
      '--db',
      defaultMemoryDatabasePath(),
      '--data',
      defaultMemoryDataDirectoryPath(),
    ];
  }

  /// Writes the target graph-backed MCP tool config before harness startup.
  Future<String> _writeDefaultGraphToolConfig({
    required RuntimeProfile profile,
    required String requestedPath,
    required String targetName,
  }) async {
    final graphServer = _serverForKind(profile, 'memory');
    if (graphServer == null) {
      throw FileSystemException('Memory MCP server is missing', profile.id);
    }
    var path = requestedPath.trim();
    var file = File(path);
    if (path.isEmpty || !await file.exists()) {
      final directory = Directory(toolConfigsDirectoryPath());
      await directory.create(recursive: true);
      path = '${directory.path}/$targetName';
      file = File(path);
    }

    final document = await file.exists()
        ? ToolConfigDocument.parse(await file.readAsString())
        : emptyToolConfigDocument();
    final target = graphBackedMemoryToolConfig(
      server: graphServer,
      localExec: document.localExec,
      headersFromEnv: _mcpHeadersFromEnv(profile, graphServer),
      extra: document.extra,
    );
    final validationError = toolConfigValidationError(target);
    if (validationError.isNotEmpty) {
      throw FileSystemException(validationError, path);
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(target.toYaml());
    await _log('wrote graph-backed MCP tool config $path');
    return path;
  }

  /// Persists one required app service server config.
  Future<void> _saveRequiredServer(
    RuntimeProfile profile,
    McpServerRuntime server,
  ) async {
    final path = _requiredServerConfigPath(profile, server.kind);
    if (path.isEmpty) {
      throw FileSystemException(
        'Server config reference is missing',
        server.id,
      );
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(encodeMcpServerRuntimeJson(server));
  }

  /// Applies changed server configs without rewriting the profile JSON.
  void _applyRuntimeProfileServers(RuntimeProfile profile) {
    runtimeProfile = profile;
    _configureClientsForRuntimeProfile(profile);
    _refreshEndpointSkeleton(profile);
  }

  /// Copies the default memory server config into the app config tree.
  Future<({String memoryServerConfigPath})>
  _copyRequiredServerConfigsIntoAppDirectory(RuntimeProfile profile) async {
    final memoryServer = _serverForKind(profile, 'memory');
    final memoryPath = await _copyConfigIntoAppDirectory(
      sourcePath: profile.memoryServerConfigPath,
      targetDirectory: memoryServerConfigsDirectoryPath(),
      targetName: '${_serverFileName(memoryServer, 'memory')}.json',
    );
    if (memoryServer != null && memoryPath != null) {
      await File(
        memoryPath,
      ).writeAsString(encodeMcpServerRuntimeJson(memoryServer));
    }
    return (
      memoryServerConfigPath: memoryPath ?? profile.memoryServerConfigPath,
    );
  }

  /// Releases HTTP clients while leaving managed local services running.
  void closeClients() {
    if (_clientsClosed) {
      return;
    }
    _clientsClosed = true;
    assistantClient.close();
    memoryClient.close();
    tasksClient.close();
    executiveSummaryClient.close();
    titleClient.close();
    if (!_screenCommandPlannerInjected &&
        screenCommandPlanner is ScreenCommandClient) {
      (screenCommandPlanner as ScreenCommandClient).close();
    }
  }

  /// Releases HTTP clients and stops locally started service processes.
  Future<void> close({void Function(String message)? onStatus}) {
    return _closeFuture ??= () async {
      _closing = true;
      processSupervisor.beginClosing();

      onStatus?.call('Closing service clients');
      closeClients();

      onStatus?.call('Stopping local model runtime');
      await _closeLocalModels();

      onStatus?.call('Stopping managed service processes');
      await _closeLocalServices(onStatus: onStatus);

      onStatus?.call('Stopping remaining subprocesses');
      await processSupervisor.close(onStatus: onStatus);

      onStatus?.call('Managed runtime stopped');
    }();
  }

  /// Stops locally started local model runtime resources once.
  Future<void> _closeLocalModels() {
    return _localModelsCloseFuture ??= localModels.close();
  }

  /// Stops locally started service processes once.
  Future<void> _closeLocalServices({void Function(String message)? onStatus}) {
    return _localServicesCloseFuture ??= localServices.close(
      onStatus: onStatus,
    );
  }

  /// Rebuilds owned service clients from the active runtime profile.
  void _configureClientsForRuntimeProfile(RuntimeProfile profile) {
    if (!_assistantClientInjected) {
      final gateway = profile.gateway;
      final assistantBaseUrl = gateway != null && gateway.enabled
          ? gateway.apiBaseUrl
          : profile.harness.apiBaseUrl;
      assistantClient.close();
      assistantClient = AssistantClient(
        baseUrl: assistantBaseUrl,
        appName: profile.harness.appName,
        userId: profile.harness.userId,
        headers: _gatewayHeadersForProfile(profile),
        logger: logger,
      );
    }
    if (!_memoryClientInjected) {
      memoryClient.close();
      memoryClient = MemoryClient(
        rpc: GatewayContextClient(
          baseUrl: _contextBaseUrl(profile),
          headers: _gatewayHeadersForProfile(profile),
          logger: logger,
        ),
      );
    }
    if (!_tasksClientInjected) {
      tasksClient.close();
      tasksClient = TasksClient(
        rpc: GatewayContextClient(
          baseUrl: _contextBaseUrl(profile),
          headers: _gatewayHeadersForProfile(profile),
          logger: logger,
        ),
      );
    }
    if (!_executiveSummaryClientInjected) {
      executiveSummaryClient.close();
      executiveSummaryClient = ExecutiveSummaryClient(
        rpc: GatewayContextClient(
          baseUrl: _contextBaseUrl(profile),
          headers: _gatewayHeadersForProfile(profile),
          logger: logger,
        ),
      );
    }
  }

  /// Selects the home workspace without fabricating local data.
  void openHome() {
    unawaited(_loadToday(quiet: true));
    notifyListeners();
  }

  /// Refreshes the Today projection from the UI.
  Future<void> refreshTodayFromUi() async {
    await _loadToday();
  }

  /// Loads an explanation for one Today projection item.
  Future<void> explainTodayItem(String itemId) async {
    final trimmed = itemId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    todayState = todayState.copyWith(
      busy: true,
      error: '',
      selectedExplanationItemId: trimmed,
    );
    notifyListeners();
    try {
      final explanation = await executiveSummaryClient
          .explainExecutiveSummaryItem(trimmed);
      todayState = todayState.copyWith(
        busy: false,
        error: '',
        explanation: explanation,
      );
    } catch (error) {
      todayState = todayState.copyWith(busy: false, error: error.toString());
    }
    notifyListeners();
  }

  /// Clears the selected Today explanation.
  void clearTodayExplanation() {
    todayState = todayState.copyWith(
      selectedExplanationItemId: '',
      explanation: const ExecutiveSummaryItemExplanation(),
    );
    notifyListeners();
  }

  /// Selects the workflow workspace without fabricating local data.
  void openWorkspace() {
    notifyListeners();
  }

  /// Selects a chat session and loads its events when connected.
  Future<void> selectSession(String sessionId) async {
    await _log('select session requested $sessionId');
    try {
      final events = await assistantClient.loadSessionEvents(sessionId);
      _rememberLiveSession(sessionId);
      selectedSessionId = sessionId;
      await _touchHistoryChat(sessionId);
      messages = events
          .map(_messageFromEvent)
          .whereType<ChatMessage>()
          .toList();
      _scheduleChatTitleRefresh(
        profilePath: runtimeProfilePath,
        sessionId: sessionId,
        transcript: List<ChatMessage>.from(messages),
      );
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.connected,
        'Loaded session',
      );
    } catch (error) {
      await _log('select session failed $sessionId: $error');
      if (selectedSessionId == sessionId) {
        selectedSessionId = null;
        messages = const <ChatMessage>[];
      }
      await _log('preserving chat history entry for unavailable session');
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    }
    notifyListeners();
  }

  /// Selects a saved chat, switching profiles when necessary.
  Future<void> selectHistoryChat(String chatKey) async {
    ChatHistoryEntry? target;
    for (final entry in chatHistory) {
      if (entry.key == chatKey) {
        target = entry;
        break;
      }
    }
    if (target == null) {
      final parsed = _parseChatHistoryKey(chatKey);
      if (parsed == null) {
        return;
      }
      if (parsed.profilePath != runtimeProfilePath) {
        try {
          await loadRuntimeProfileFromPath(
            parsed.profilePath,
            reloadData: false,
          );
        } catch (error) {
          _setEndpoint(
            'Runtime Profile',
            ConnectionStateKind.disconnected,
            error.toString(),
          );
          notifyListeners();
          return;
        }
        if (!await _ensureChatRuntimeReady()) {
          return;
        }
        await Future.wait(<Future<void>>[_loadMemory(), _loadTasks()]);
      }
      await selectSession(parsed.sessionId);
      return;
    }
    if (target.profilePath != runtimeProfilePath) {
      try {
        await loadRuntimeProfileFromPath(target.profilePath, reloadData: false);
      } catch (error) {
        _setEndpoint(
          'Runtime Profile',
          ConnectionStateKind.disconnected,
          error.toString(),
        );
        notifyListeners();
        return;
      }
      if (!await _ensureChatRuntimeReady()) {
        return;
      }
      await Future.wait(<Future<void>>[_loadMemory(), _loadTasks()]);
    }
    await selectSession(target.sessionId);
  }

  /// Deletes a saved chat and its backing ADK session.
  Future<void> deleteHistoryChat(String chatKey) async {
    await _ensureInitialized();
    await _log('delete chat requested $chatKey');
    final target = _chatTargetFromKey(chatKey);
    if (target == null) {
      await _log('delete chat ignored: target not found');
      return;
    }
    final originalProfilePath = runtimeProfilePath;
    final shouldRestoreProfile =
        originalProfilePath.isNotEmpty &&
        target.profilePath != originalProfilePath;
    try {
      if (target.profilePath.isNotEmpty &&
          target.profilePath != runtimeProfilePath) {
        await loadRuntimeProfileFromPath(target.profilePath, reloadData: false);
      }
      if (!await _ensureChatRuntimeReady()) {
        await _log('delete chat blocked: managed runtime unavailable');
        notifyListeners();
        throw StateError(statusMessage);
      }
      await assistantClient.deleteSession(target.sessionId);
      await _removeHistoryChat(
        profilePath: target.profilePath,
        sessionId: target.sessionId,
      );
      _chatTaskIds.remove(target.sessionId);
      if (target.profilePath == runtimeProfilePath) {
        sessions = sessions
            .where((session) => session.id != target.sessionId)
            .toList();
        if (selectedSessionId == target.sessionId) {
          pendingConfirmation = null;
          if (sessions.isEmpty) {
            selectedSessionId = null;
            messages = const <ChatMessage>[];
          } else {
            selectedSessionId = sessions.first.id;
            await selectSession(sessions.first.id);
          }
        }
      }
      _setEndpoint('Agent API', ConnectionStateKind.connected, 'Deleted chat');
      await _log('deleted chat session ${target.sessionId}');
    } catch (error) {
      await _log('delete chat failed: $error');
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.disconnected,
        error.toString(),
      );
      rethrow;
    } finally {
      if (shouldRestoreProfile && runtimeProfilePath != originalProfilePath) {
        try {
          await loadRuntimeProfileFromPath(originalProfilePath);
        } catch (error) {
          await _log('delete chat profile restore failed: $error');
          _setEndpoint(
            'Runtime Profile',
            ConnectionStateKind.disconnected,
            error.toString(),
          );
          notifyListeners();
        }
      } else {
        notifyListeners();
      }
    }
  }

  /// Creates a new chat session.
  Future<bool> createChat({String profilePath = ''}) async {
    await _ensureInitialized();
    await _log('create chat requested');
    if (runtimeProfile == null) {
      await _log('create chat blocked: runtime profile missing');
      _setEndpoint(
        'Runtime Profile',
        ConnectionStateKind.disconnected,
        statusMessage,
      );
      notifyListeners();
      return false;
    }
    final targetProfilePath = profilePath.trim().isEmpty
        ? defaultChatProfilePath
        : profilePath.trim();
    if (targetProfilePath.isNotEmpty &&
        targetProfilePath != runtimeProfilePath) {
      try {
        await loadRuntimeProfileFromPath(targetProfilePath, reloadData: false);
      } catch (error) {
        await _log('create chat profile switch failed: $error');
        _setEndpoint(
          'Runtime Profile',
          ConnectionStateKind.disconnected,
          error.toString(),
        );
        notifyListeners();
        return false;
      }
    }
    if (!await _ensureChatRuntimeReady()) {
      await _log('create chat blocked: managed runtime unavailable');
      notifyListeners();
      return false;
    }
    try {
      final session = await assistantClient.createSession();
      sessions = <ChatSession>[session, ...sessions];
      selectedSessionId = session.id;
      messages = const <ChatMessage>[];
      await _upsertHistoryChat(session);
      _setEndpoint('Agent API', ConnectionStateKind.connected, 'Created chat');
      await _log('created chat session ${session.id}');
      unawaited(Future.wait(<Future<void>>[_loadMemory(), _loadTasks()]));
      notifyListeners();
      return true;
    } catch (error) {
      await _log('create chat failed: $error');
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    }
    notifyListeners();
    return false;
  }

  /// Sends a user-authored chat message with optional hidden routing context.
  Future<void> sendUserMessage(String text, {String displayText = ''}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || sending) {
      await _log(
        'send user message ignored empty=${trimmed.isEmpty} sending=$sending',
      );
      return;
    }
    final visibleText = displayText.trim().isEmpty
        ? displayTextFromUserPrompt(trimmed)
        : displayText.trim();
    await _log('send user message requested length=${trimmed.length}');
    statusMessage = 'Preparing managed chat runtime';
    notifyListeners();
    final runtimeReady = await _ensureChatRuntimeReady();
    final ready = runtimeReady && await _ensureLiveSession();
    final sessionId = selectedSessionId;
    messages = <ChatMessage>[
      ...messages,
      ChatMessage(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        role: ChatRole.user,
        author: 'You',
        text: visibleText,
        createdAt: DateTime.now(),
      ),
    ];
    if (!ready || sessionId == null) {
      await _log('send user message blocked: no live session');
      messages = <ChatMessage>[
        ...messages,
        ChatMessage(
          id: 'runtime-${DateTime.now().microsecondsSinceEpoch}',
          role: ChatRole.tool,
          author: 'Runtime',
          text: _agentUnavailableMessage(),
          createdAt: DateTime.now(),
        ),
      ];
      sending = false;
      notifyListeners();
      return;
    }
    sending = true;
    notifyListeners();
    await _log('streaming run for session $sessionId');
    await _streamRun(sessionId: sessionId, text: trimmed);
  }

  /// Responds to a pending ADK confirmation request.
  Future<void> answerConfirmation(ConfirmationOption option) async {
    final confirmation = pendingConfirmation;
    final sessionId = selectedSessionId;
    if (confirmation == null || sessionId == null) {
      return;
    }
    pendingConfirmation = null;
    notifyListeners();
    await _sendConfirmationReply(
      sessionId: sessionId,
      confirmation: confirmation,
      option: option,
    );
  }

  /// Sends an ADK confirmation response back to the active assistant session.
  Future<void> _sendConfirmationReply({
    required String sessionId,
    required ConfirmationRequest confirmation,
    required ConfirmationOption option,
  }) async {
    await _streamRun(
      sessionId: sessionId,
      reply: ConfirmationReply(
        callId: confirmation.callId,
        confirmed: option.action != 'deny',
        action: option.action,
      ),
    );
  }

  /// Returns the best non-denial option for an auto-approved task operation.
  ConfirmationOption _approvalOption(ConfirmationRequest confirmation) {
    return confirmation.options.firstWhere(
      (option) => option.action != 'deny',
      orElse: () =>
          const ConfirmationOption(action: 'approve_once', label: 'Approve'),
    );
  }

  /// Reports whether a confirmation can be satisfied without user interaction.
  bool _shouldAutoApproveTaskConfirmation(ConfirmationRequest confirmation) {
    return _taskWriteToolNames.contains(confirmation.toolName);
  }

  /// Creates a task after local UI confirmation.
  Future<void> createTaskFromUi(
    String title, {
    String description = '',
    String status = 'open',
    String priority = 'normal',
    DateTime? dueAt,
    DateTime? scheduledAt,
    List<String> topics = const <String>[],
    bool linkSelectedMemory = false,
  }) async {
    final server = _primaryGraphServer();
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      notifyListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Creating backlog item';
    notifyListeners();
    try {
      final memoryLinks = linkSelectedMemory
          ? _selectedMemoryLinkDrafts('originated_from')
          : const <TaskMemoryLinkDraft>[];
      await _withTasksClientForGraphServer(server, (client) {
        return client.createTask(
          title: title,
          description: description,
          status: status,
          priority: priority,
          dueAt: dueAt,
          scheduledAt: scheduledAt,
          topics: topics,
          memoryLinks: memoryLinks,
        );
      });
      await _loadTasks();
      taskSelectionKind = 'task';
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Backlog item created',
      );
      tasksMessage = 'Backlog item created';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
    }
    notifyListeners();
  }

  /// Returns the selected task when the task inspector is active.
  WorkspaceTask? get selectedTask {
    if (taskSelectionKind != 'task') {
      return null;
    }
    if (selectedTaskId != null) {
      final indexedTask = taskInsightIndex.workspaceTaskForId(selectedTaskId);
      if (indexedTask != null) {
        return indexedTask;
      }
      for (final task in workspace.tasks) {
        if (task.id == selectedTaskId) {
          return task;
        }
      }
    }
    if (workspace.tasks.isEmpty) {
      return null;
    }
    return workspace.tasks.first;
  }

  /// Returns the selected task's graph task id.
  String get selectedGraphTaskId {
    final taskId = selectedTaskId;
    if (taskId != null && taskId.isNotEmpty) {
      return taskId;
    }
    final task = selectedTask;
    return task == null ? '' : task.id;
  }

  /// Returns explicit relation records connected to the selected task.
  List<TaskRelationRecord> get selectedTaskRelations {
    final task = selectedTask;
    if (task == null) {
      return const <TaskRelationRecord>[];
    }
    final taskId = task.id;
    return taskRelations.where((relation) {
      return relation.fromTaskId == taskId || relation.toTaskId == taskId;
    }).toList();
  }

  /// Returns inferred relation suggestions connected to the selected task.
  List<TaskRelationSuggestion> get selectedTaskRelationSuggestions {
    final task = selectedTask;
    if (task == null) {
      return const <TaskRelationSuggestion>[];
    }
    final taskId = task.id;
    return taskRelationSuggestions.where((suggestion) {
      return suggestion.fromTaskId == taskId || suggestion.toTaskId == taskId;
    }).toList();
  }

  /// Returns inferred metadata suggestions connected to the selected task.
  List<TaskMetadataSuggestion> get selectedTaskMetadataSuggestions {
    final task = selectedTask;
    if (task == null) {
      return const <TaskMetadataSuggestion>[];
    }
    final taskId = task.id;
    return taskMetadataSuggestions.where((suggestion) {
      return suggestion.taskId == taskId;
    }).toList();
  }

  /// Returns inferred commitment suggestions connected to the selected task.
  List<TaskCommitmentSuggestion> get selectedTaskCommitmentSuggestions {
    final task = selectedTask;
    if (task == null) {
      return const <TaskCommitmentSuggestion>[];
    }
    final taskId = task.id;
    return taskCommitmentSuggestions.where((suggestion) {
      return suggestion.taskId == taskId;
    }).toList();
  }

  /// Returns first-class commitments represented by the selected task.
  List<TaskCommitment> get selectedTaskCommitments {
    final task = selectedTask;
    if (task == null) {
      return const <TaskCommitment>[];
    }
    final taskId = task.id;
    return taskCommitments.where((commitment) {
      return commitment.taskId == taskId;
    }).toList();
  }

  /// Returns the selected constellation edge when the inspector is in edge mode.
  TaskConstellationEdge? get selectedConstellationEdge {
    if (taskSelectionKind != 'constellation_edge') {
      return null;
    }
    final edge = selectedTaskConstellationEdge;
    if (edge == null) {
      return null;
    }
    if (!taskInsightIndex.isVisibleEndpoint(edge.fromTaskId) ||
        !taskInsightIndex.isVisibleEndpoint(edge.toTaskId)) {
      return null;
    }
    return edge;
  }

  /// Returns tasks after applying local queue filters.
  List<WorkspaceTask> get filteredTasks {
    return workspace.tasks.where((task) {
      final terminal = task.status == 'done' || task.status == 'canceled';
      if (!taskFilters.includeDone && terminal) {
        return false;
      }
      if (taskFilters.statuses.isNotEmpty &&
          !taskFilters.statuses.contains(task.status)) {
        return false;
      }
      if (taskFilters.priorities.isNotEmpty &&
          !taskFilters.priorities.contains(task.priority)) {
        return false;
      }
      if (taskFilters.topics.isNotEmpty &&
          !task.topics.any(taskFilters.topics.contains)) {
        return false;
      }
      if (taskFilters.overdueOnly && !task.overdue) {
        return false;
      }
      final search = taskFilters.search.trim();
      if (search.isNotEmpty &&
          !_textContains('${task.title} ${task.description}', search)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Returns all task topics in count order.
  List<String> get taskTopics {
    final counts = <String, int>{};
    for (final task in workspace.tasks) {
      for (final topic in task.topics) {
        counts[topic] = (counts[topic] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((left, right) {
        final countCompare = right.value.compareTo(left.value);
        return countCompare == 0 ? left.key.compareTo(right.key) : countCompare;
      });
    return entries.map((entry) => entry.key).toList();
  }

  /// Returns tasks created from or otherwise associated with the selected chat.
  List<WorkspaceTask> get selectedChatTasks {
    final sessionId = selectedSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return const <WorkspaceTask>[];
    }
    final associatedTaskIds = _chatTaskIds[sessionId] ?? const <String>{};
    final conversationText = messages
        .map((message) => '${message.author} ${message.text}')
        .join('\n');
    return workspace.tasks.where((task) {
      return _taskBelongsToChat(task, sessionId) ||
          associatedTaskIds.contains(task.id) ||
          _taskTitleAppearsInChat(task, conversationText);
    }).toList();
  }

  /// Applies local task filters and refreshes the task surface.
  Future<void> applyTaskFilters(TaskFilterState filters) async {
    taskFilters = filters;
    notifyListeners();
  }

  /// Applies one semantic task insight preset to Queue.
  Future<void> applyTaskInsightPreset(String presetId) async {
    taskInsightPresetId = presetId;
    notifyListeners();
  }

  /// Refreshes graph-backed task state from memory graph servers.
  Future<void> refreshTasksFromUi() async {
    await _loadTasks();
  }

  /// Refreshes graph-backed memory records from memory MCP servers.
  Future<void> refreshMemoryFromUi() async {
    await _loadMemory();
  }

  /// Reports whether the primary memory server advertises a tool.
  bool primaryMemoryToolAvailable(String toolName) {
    return primaryMemoryToolNames.contains(toolName);
  }

  /// Selects a task for the inspector.
  void selectTask(String taskId) {
    taskSelectionKind = 'task';
    selectedTaskId = taskId;
    selectedTaskConstellationEdge = null;
    notifyListeners();
  }

  /// Selects a constellation relation edge for the inspector.
  void selectConstellationEdge(TaskConstellationEdge edge) {
    taskSelectionKind = 'constellation_edge';
    selectedTaskConstellationEdge = edge;
    selectedTaskId = null;
    notifyListeners();
  }

  /// Clears the selected constellation edge without changing task data.
  void clearConstellationEdgeSelection() {
    if (selectedTaskConstellationEdge == null &&
        taskSelectionKind != 'constellation_edge') {
      return;
    }
    selectedTaskConstellationEdge = null;
    if (taskSelectionKind == 'constellation_edge') {
      taskSelectionKind = 'task';
    }
    notifyListeners();
  }

  /// Runs a structured AI command against the Backlog screen.
  Future<void> runBacklogScreenCommand({
    required String text,
    required String scopeLabel,
  }) async {
    final command = text.trim();
    if (command.isEmpty || screenCommandBusy) {
      return;
    }
    screenCommandBusy = true;
    screenCommandMessage = 'Planning screen changes';
    notifyListeners();
    try {
      final profile = runtimeProfile;
      if (profile == null) {
        throw StateError('Runtime profile is not loaded');
      }
      final planned = await screenCommandPlanner.planBacklogCommand(
        modelConfigPath: profile.harness.modelConfigPath,
        command: command,
        snapshot: _backlogScreenSnapshot(scopeLabel),
      );
      if (planned.intent != ScreenCommandIntent.change) {
        activeScreenCommandRun = planned;
        backlogChatPanelOpen = true;
        backlogReviewPanelOpen = false;
        screenCommandMessage = planned.message.trim().isEmpty
            ? 'Opening chat for this screen'
            : planned.message.trim();
        notifyListeners();
        await sendUserMessage(
          buildScreenCommandPrompt(
            scopeLabel: scopeLabel,
            userText: command,
            relevantIds: _screenCommandRelevantIds(),
          ),
          displayText: command,
        );
        return;
      }
      final prepared = _preparedBacklogScreenRun(planned);
      activeScreenCommandRun = prepared;
      backlogReviewPanelOpen = prepared.changes.isNotEmpty;
      screenCommandMessage = _screenRunSummary(prepared);
      notifyListeners();
      await _applyAutoScreenChanges(prepared);
    } catch (error) {
      activeScreenCommandRun = ScreenCommandRun(
        id: 'screen-run-${DateTime.now().microsecondsSinceEpoch}',
        command: command,
        intent: ScreenCommandIntent.change,
        message: error.toString(),
        changes: const <ScreenChange>[],
        createdAt: DateTime.now(),
      );
      backlogReviewPanelOpen = true;
      screenCommandMessage = error.toString();
      await _log('backlog screen command failed: $error');
    } finally {
      screenCommandBusy = false;
      notifyListeners();
    }
  }

  /// Opens the Backlog review side panel.
  void openBacklogReviewPanel() {
    backlogReviewPanelOpen = true;
    notifyListeners();
  }

  /// Opens the Backlog inspector side panel.
  void openBacklogInspectorPanel() {
    backlogReviewPanelOpen = false;
    notifyListeners();
  }

  /// Closes the auxiliary Backlog chat panel.
  void closeBacklogChatPanel() {
    backlogChatPanelOpen = false;
    notifyListeners();
  }

  /// Selects a task from the queue and restores the inspector pane.
  void inspectBacklogTask(String taskId) {
    taskSelectionKind = 'task';
    selectedTaskId = taskId;
    selectedTaskConstellationEdge = null;
    backlogReviewPanelOpen = false;
    notifyListeners();
  }

  /// Focuses a review-panel change in the Backlog queue.
  void focusBacklogScreenChange(String changeId) {
    final change = screenChangeForId(changeId);
    if (change == null) {
      return;
    }
    focusedScreenChangeId = changeId;
    focusedBacklogTaskId = change.target.taskId;
    if (focusedBacklogTaskId.isNotEmpty) {
      taskSelectionKind = 'task';
      selectedTaskId = focusedBacklogTaskId;
      selectedTaskConstellationEdge = null;
    }
    notifyListeners();
  }

  /// Clears the pending Backlog queue focus request.
  void clearBacklogScreenFocus() {
    if (focusedBacklogTaskId.isEmpty && focusedScreenChangeId.isEmpty) {
      return;
    }
    focusedBacklogTaskId = '';
    focusedScreenChangeId = '';
    notifyListeners();
  }

  /// Returns the active screen changes for one backlog task.
  List<ScreenChange> screenChangesForTask(String taskId) {
    final run = activeScreenCommandRun;
    if (run == null || taskId.isEmpty) {
      return const <ScreenChange>[];
    }
    return run.changes.where((change) {
      return change.target.taskId == taskId &&
          change.status != ScreenChangeStatus.rejected &&
          change.status != ScreenChangeStatus.undone;
    }).toList();
  }

  /// Returns one active screen change by id.
  ScreenChange? screenChangeForId(String changeId) {
    final run = activeScreenCommandRun;
    if (run == null) {
      return null;
    }
    for (final change in run.changes) {
      if (change.id == changeId) {
        return change;
      }
    }
    return null;
  }

  /// Applies one reviewable Backlog screen change.
  Future<void> applyScreenChangeFromUi(String changeId) async {
    final change = screenChangeForId(changeId);
    if (change == null ||
        change.status != ScreenChangeStatus.proposed ||
        change.safety == ScreenChangeSafety.rejected) {
      return;
    }
    await _applyBacklogScreenChange(change);
  }

  /// Rejects one reviewable Backlog screen change.
  Future<void> rejectScreenChangeFromUi(String changeId) async {
    final change = screenChangeForId(changeId);
    if (change == null || change.status != ScreenChangeStatus.proposed) {
      return;
    }
    _replaceScreenChange(
      change.copyWith(
        status: ScreenChangeStatus.rejected,
        safety: ScreenChangeSafety.rejected,
        error: 'Rejected by user',
      ),
    );
    screenCommandMessage = 'Screen change rejected';
    notifyListeners();
  }

  /// Undoes one applied Backlog screen change when an inverse edit is known.
  Future<void> undoScreenChangeFromUi(String changeId) async {
    final change = screenChangeForId(changeId);
    if (change == null ||
        change.status != ScreenChangeStatus.applied ||
        !_screenChangeCanUndo(change)) {
      return;
    }
    final server = _primaryGraphServer();
    if (server == null) {
      _replaceScreenChange(
        change.copyWith(
          status: ScreenChangeStatus.failed,
          error: 'No graph memory server',
        ),
      );
      notifyListeners();
      return;
    }
    screenCommandBusy = true;
    screenCommandMessage = 'Undoing screen change';
    notifyListeners();
    try {
      if (change.operation == ScreenChangeOperation.createTask) {
        await _withTasksClientForGraphServer(server, (client) {
          return client.deleteTask(change.target.taskId);
        });
      } else {
        await _withTasksClientForGraphServer(server, (client) {
          return _updateTaskForScreenFields(
            client: client,
            taskId: change.target.taskId,
            fields: _undoFieldsForChange(change),
          );
        });
      }
      await _loadTasks();
      _replaceScreenChange(change.copyWith(status: ScreenChangeStatus.undone));
      screenCommandMessage = 'Screen change undone';
    } catch (error) {
      _replaceScreenChange(
        change.copyWith(status: ScreenChangeStatus.failed, error: '$error'),
      );
      screenCommandMessage = error.toString();
    } finally {
      screenCommandBusy = false;
      notifyListeners();
    }
  }

  /// Reports whether the UI can undo one applied screen change.
  bool screenChangeCanUndo(ScreenChange change) {
    return change.status == ScreenChangeStatus.applied &&
        _screenChangeCanUndo(change);
  }

  /// Returns the selected memory record when it is still visible.
  MemoryRecord? get selectedMemory {
    for (final record in workspace.memoryRecords) {
      if (record.id == selectedMemoryId) {
        return record;
      }
    }
    if (workspace.memoryRecords.isEmpty) {
      return null;
    }
    return workspace.memoryRecords.first;
  }

  /// Returns records after applying local filters unsupported by retrieval.
  List<MemoryRecord> get filteredMemoryRecords {
    return workspace.memoryRecords.where((record) {
      if (memoryFilters.localStatus.isNotEmpty &&
          record.status != memoryFilters.localStatus) {
        return false;
      }
      if (memoryFilters.localTrustLevel.isNotEmpty &&
          record.trustLevel != memoryFilters.localTrustLevel) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Applies memory filters and reloads records from the service.
  Future<void> applyMemoryFilters(MemoryFilterState filters) async {
    memoryFilters = filters;
    await _loadMemory();
  }

  /// Selects a memory and hydrates its source preview when possible.
  Future<void> selectMemory(String memoryId) async {
    selectedMemoryId = memoryId;
    selectedMemoryPage = null;
    notifyListeners();
    await hydrateSelectedMemorySource();
  }

  /// Loads raw source text for the selected memory without mutating source truth.
  Future<void> hydrateSelectedMemorySource() async {
    final memory = selectedMemory;
    if (memory == null || memory.rawContent.isNotEmpty) {
      return;
    }
    memoryBusy = true;
    memoryMessage = 'Loading source content';
    notifyListeners();
    try {
      final records = await memoryClient.searchSources(
        scope: memory.scope,
        text: memory.title,
        kinds: memoryFilters.kinds,
        allowedSensitivities: _sensitivitiesIncluding(memory.sensitivity),
        limit: memoryFilters.limit,
      );
      final hydrated = records.where((record) => record.id == memory.id);
      if (hydrated.isNotEmpty) {
        _replaceMemoryRecord(hydrated.first);
        memoryMessage = 'Source content loaded';
      } else {
        memoryMessage = 'Source content was not returned by search';
      }
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
    } catch (error) {
      memoryMessage = error.toString();
      workspace = ProjectWorkspace(
        title: workspace.title,
        subtitle: workspace.subtitle,
        tasks: workspace.tasks,
        sources: const <SourceItem>[],
        memoryRecords: const <MemoryRecord>[],
      );
      selectedMemoryId = null;
      selectedMemoryPage = null;
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      notifyListeners();
    }
  }

  /// Saves a reviewed memory candidate as immutable source-backed content.
  Future<void> saveMemoryCandidateFromUi(
    MemoryCaptureDraft draft, {
    String idempotencyKey = '',
  }) async {
    memoryBusy = true;
    memoryMessage = 'Saving reviewed memory candidate';
    notifyListeners();
    try {
      await memoryClient.saveMemoryCandidate(
        draft: draft,
        idempotencyKey: idempotencyKey.trim().isEmpty
            ? 'agent_awesome_ui:${DateTime.now().microsecondsSinceEpoch}:${draft.title}'
            : idempotencyKey.trim(),
      );
      memoryMessage = 'Memory candidate saved';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
      await _loadMemory();
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      notifyListeners();
    }
  }

  /// Imports a local source file and stores it as a memory-backed file.
  Future<void> importFileFromUi() async {
    memoryBusy = true;
    memoryMessage = 'Selecting file';
    notifyListeners();
    try {
      final imported = await fileImporter.pickFile();
      if (imported == null) {
        memoryMessage = 'File import canceled';
        return;
      }
      await memoryClient.saveMemoryCandidate(
        draft: imported.toMemoryDraft(),
        idempotencyKey: imported.idempotencyKey,
      );
      memoryMessage = 'Imported ${imported.name}';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
      await _loadMemory();
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      notifyListeners();
    }
  }

  /// Sends one indexed file to the current chat using the active model policy.
  Future<void> sendFileToChatFromUi(MemoryRecord file) async {
    final hydrated = await _hydratedFileRecord(file);
    final capabilities = await activeModelFileCapabilities();
    final payload = _fileChatPrompt(hydrated, capabilities);
    await sendUserMessage(payload, displayText: 'Review ${hydrated.title}');
  }

  /// Resolves the active model's file handling from the harness model config.
  Future<ModelFileCapabilities> activeModelFileCapabilities() async {
    final path = runtimeProfile?.harness.modelConfigPath.trim() ?? '';
    if (path.isEmpty) {
      return fallbackModelFileCapabilities('No active model config is loaded.');
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        return fallbackModelFileCapabilities(
          'The active model config was not found.',
        );
      }
      final document = ModelConfigDocument.parse(await file.readAsString());
      final selection = activeModelFileSelection(document);
      if (selection == null) {
        return fallbackModelFileCapabilities(
          'The active model config has no usable provider/model selection.',
        );
      }
      return modelFileCapabilitiesFor(
        provider: selection.provider,
        model: selection.model,
      );
    } catch (error) {
      return fallbackModelFileCapabilities(
        'Could not inspect model file support: $error',
      );
    }
  }

  /// Loads raw source text for a file record before sending it to chat.
  Future<MemoryRecord> _hydratedFileRecord(MemoryRecord file) async {
    if (file.rawContent.trim().isNotEmpty) {
      return file;
    }
    try {
      final records = await memoryClient.searchSources(
        scope: file.scope,
        text: file.title,
        kinds: <String>[file.kind],
        allowedSensitivities: _sensitivitiesIncluding(file.sensitivity),
        limit: 20,
      );
      for (final record in records) {
        if (record.id == file.id || record.evidenceId == file.evidenceId) {
          _replaceMemoryRecord(record);
          return record;
        }
      }
    } catch (error) {
      await _log('file source hydration failed: $error');
    }
    return file;
  }

  /// Builds the text payload used by the current ADK chat endpoint.
  String _fileChatPrompt(
    MemoryRecord file,
    ModelFileCapabilities capabilities,
  ) {
    final title = file.title.trim().isEmpty
        ? 'Untitled file'
        : file.title.trim();
    final mediaType = file.rawMediaType.trim().isEmpty
        ? 'application/octet-stream'
        : file.rawMediaType.trim();
    final content = file.rawContent.trim().isEmpty
        ? 'The source content has not been hydrated by the memory service.'
        : file.rawContent.trim();
    final transport = capabilities.usesBase64Fallback
        ? 'base64_text'
        : 'native_file_parts_requested';
    return '''
Please review this file and use it as source material for the conversation.

File name: $title
Media type: $mediaType
Source: ${file.sourceLabel}
Model: ${capabilities.modelName.isEmpty ? 'unknown' : capabilities.modelName}
Native file support detected: ${capabilities.nativeFileParts}
Transport selected: $transport
Transport reason: ${capabilities.reason}

--- file_payload ---
$content
'''
        .trim();
  }

  /// Repairs selected memory metadata without changing raw source content.
  Future<void> repairMemoryFromUi(MemoryRepairDraft draft) async {
    memoryBusy = true;
    memoryMessage = 'Repairing memory metadata';
    notifyListeners();
    try {
      final repaired = await memoryClient.repairMemoryRecord(draft: draft);
      _replaceMemoryRecord(repaired);
      selectedMemoryId = repaired.id;
      memoryMessage = 'Memory metadata repaired';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      notifyListeners();
    }
  }

  /// Stores a correction as a new source-backed memory.
  Future<void> submitMemoryCorrectionFromUi(String text) async {
    final memory = selectedMemory;
    if (memory == null) {
      return;
    }
    memoryBusy = true;
    memoryMessage = 'Submitting source-backed correction';
    notifyListeners();
    try {
      await memoryClient.submitMemoryCorrection(
        memoryId: memory.id,
        text: text,
        scope: memory.scope,
      );
      memoryMessage = 'Correction saved as new memory';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
      await _loadMemory();
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      notifyListeners();
    }
  }

  /// Loads or creates a compiled entity page for the selected memory.
  Future<void> loadEntityPageFromUi(MemoryRecord memory) async {
    if (memory.entityIds.isEmpty && memory.entityNames.isEmpty) {
      memoryMessage = 'Select a memory with an entity first';
      notifyListeners();
      return;
    }
    memoryBusy = true;
    memoryMessage = 'Loading compiled entity page';
    notifyListeners();
    try {
      selectedMemoryPage = await memoryClient.loadEntityPage(
        scope: memory.scope,
        entityId: memory.entityIds.isEmpty ? '' : memory.entityIds.first,
        title: memory.entityNames.isEmpty
            ? memory.title
            : memory.entityNames.first,
      );
      memoryMessage = 'Entity page loaded';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      notifyListeners();
    }
  }

  /// Loads or creates a compiled timeline for a topic.
  Future<void> loadTimelineFromUi(String topic) async {
    final memory = selectedMemory;
    if (memory == null || topic.trim().isEmpty) {
      return;
    }
    memoryBusy = true;
    memoryMessage = 'Loading source-backed timeline';
    notifyListeners();
    try {
      selectedMemoryPage = await memoryClient.loadTimeline(
        scope: memory.scope,
        topic: topic.trim(),
        entityId: memory.entityIds.isEmpty ? '' : memory.entityIds.first,
      );
      memoryMessage = 'Timeline loaded';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      notifyListeners();
    }
  }

  /// Refreshes the last loaded compiled memory page.
  Future<void> refreshSelectedMemoryPageFromUi() async {
    final page = selectedMemoryPage;
    if (page == null) {
      return;
    }
    memoryBusy = true;
    memoryMessage = 'Refreshing compiled page';
    notifyListeners();
    try {
      selectedMemoryPage = await memoryClient.refreshCompiledPage(
        kind: page.kind,
        scope: page.scope,
        title: page.title,
        topic: page.kind == 'timeline' ? page.title : '',
      );
      memoryMessage = 'Compiled page refreshed';
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.connected,
        memoryMessage,
      );
    } catch (error) {
      memoryMessage = error.toString();
      _setEndpoint(
        _primaryMemoryLabel(),
        ConnectionStateKind.disconnected,
        memoryMessage,
      );
    } finally {
      memoryBusy = false;
      notifyListeners();
    }
  }

  /// Completes a task after local UI confirmation.
  Future<void> completeTaskFromUi(String taskId) async {
    final server = _primaryGraphServer();
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      notifyListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Completing backlog item';
    notifyListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.completeTask(taskId);
      });
      await _loadTasks();
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Backlog item completed',
      );
      tasksMessage = 'Backlog item completed';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
    }
    notifyListeners();
  }

  /// Updates mutable task fields after local UI confirmation.
  Future<void> updateTaskFromUi({
    required String taskId,
    String? title,
    String? description,
    String? status,
    String? priority,
    DateTime? dueAt,
    bool clearDueAt = false,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
    List<String>? topics,
    int? estimateMinutes,
    String? energyRequired,
    double? effort,
    double? value,
    double? urgency,
    double? risk,
    String? context,
    String? domain,
    String? location,
    String? owner,
    String? source,
    TaskWorkBreakdown? workBreakdown,
    double? confidence,
  }) async {
    final server = _primaryGraphServer();
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      notifyListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Saving backlog item';
    notifyListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.updateTask(
          taskId: taskId,
          title: title,
          description: description,
          status: status,
          priority: priority,
          dueAt: dueAt,
          clearDueAt: clearDueAt,
          scheduledAt: scheduledAt,
          clearScheduledAt: clearScheduledAt,
          topics: topics,
          replaceTopics: topics != null,
          estimateMinutes: estimateMinutes,
          energyRequired: energyRequired,
          effort: effort,
          value: value,
          urgency: urgency,
          risk: risk,
          context: context,
          domain: domain,
          location: location,
          owner: owner,
          source: source,
          workBreakdown: workBreakdown,
          confidence: confidence,
        );
      });
      selectedTaskId = taskId;
      taskSelectionKind = 'task';
      await _loadTasks();
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Backlog item saved',
      );
      tasksMessage = 'Backlog item saved';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      notifyListeners();
    }
  }

  /// Creates or updates an explicit task relation from the inspector.
  Future<void> upsertTaskRelationFromUi({
    required String fromTaskId,
    required String toTaskId,
    String relationType = 'related_to',
    double confidence = 1,
    String explanation = '',
  }) async {
    await _mutateTaskGraphFromUi(
      server: _primaryGraphServer(),
      selectedTaskAfter: fromTaskId,
      busyMessage: 'Saving backlog relation',
      successMessage: 'Backlog relation saved',
      action: (client) async {
        await client.upsertTaskRelation(
          fromTaskId: fromTaskId,
          toTaskId: toTaskId,
          relationType: relationType,
          confidence: confidence,
          explanation: explanation,
        );
      },
    );
  }

  /// Deletes an explicit task relation from the inspector.
  Future<void> deleteTaskRelationFromUi(TaskRelationRecord relation) async {
    await _mutateTaskGraphFromUi(
      server: _primaryGraphServer(),
      selectedTaskAfter: relation.fromTaskId,
      busyMessage: 'Deleting backlog relation',
      successMessage: 'Backlog relation deleted',
      action: (client) async {
        await client.deleteTaskRelation(relation.id);
      },
    );
  }

  /// Accepts an inferred task relation suggestion as explicit metadata.
  Future<void> applyTaskSuggestionFromUi(String suggestionId) async {
    final taskId = _taskIdForSuggestion(suggestionId);
    await _mutateTaskGraphFromUi(
      server: _primaryGraphServer(),
      selectedTaskAfter: taskId,
      busyMessage: 'Accepting backlog suggestion',
      successMessage: 'Backlog suggestion accepted',
      action: (client) async {
        await client.applyTaskSuggestion(suggestionId);
      },
    );
  }

  /// Dismisses an inferred task relation suggestion.
  Future<void> dismissTaskSuggestionFromUi(String suggestionId) async {
    final taskId = _taskIdForSuggestion(suggestionId);
    await _mutateTaskGraphFromUi(
      server: _primaryGraphServer(),
      selectedTaskAfter: taskId,
      busyMessage: 'Dismissing backlog suggestion',
      successMessage: 'Backlog suggestion dismissed',
      action: (client) async {
        await client.dismissTaskSuggestion(suggestionId);
      },
    );
  }

  /// Creates or updates a first-class task commitment from the inspector.
  Future<void> upsertTaskCommitmentFromUi({
    String commitmentId = '',
    required String taskId,
    List<String> people = const <String>[],
    String domain = '',
    String project = '',
    String timeWindow = '',
    String responsibility = '',
    String promiseSource = '',
    String hardness = '',
    String consequence = '',
  }) async {
    await _mutateTaskGraphFromUi(
      server: _primaryGraphServer(),
      selectedTaskAfter: taskId,
      busyMessage: 'Saving backlog commitment',
      successMessage: 'Backlog commitment saved',
      action: (client) async {
        await client.upsertCommitment(
          commitmentId: commitmentId,
          taskId: taskId,
          people: people,
          domain: domain,
          project: project,
          timeWindow: timeWindow,
          responsibility: responsibility,
          promiseSource: promiseSource,
          hardness: hardness,
          consequence: consequence,
        );
      },
    );
  }

  /// Deletes one first-class task commitment from the inspector.
  Future<void> deleteTaskCommitmentFromUi(TaskCommitment commitment) async {
    await _mutateTaskGraphFromUi(
      server: _primaryGraphServer(),
      selectedTaskAfter: commitment.taskId,
      busyMessage: 'Deleting backlog commitment',
      successMessage: 'Backlog commitment deleted',
      action: (client) async {
        await client.deleteCommitment(commitment.id);
      },
    );
  }

  /// Cancels a task after local UI confirmation.
  Future<void> cancelTaskFromUi(String taskId) async {
    final server = _primaryGraphServer();
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      notifyListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Canceling backlog item';
    notifyListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.cancelTask(taskId);
      });
      selectedTaskId = taskId;
      await _loadTasks();
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Backlog item canceled',
      );
      tasksMessage = 'Backlog item canceled';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      notifyListeners();
    }
  }

  /// Deletes a task after local UI confirmation.
  Future<void> deleteTaskFromUi(String taskId) async {
    final server = _primaryGraphServer();
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      notifyListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Deleting backlog item';
    notifyListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.deleteTask(taskId);
      });
      if (selectedTaskId == taskId) {
        selectedTaskId = null;
      }
      await _loadTasks();
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Backlog item deleted',
      );
      tasksMessage = 'Backlog item deleted';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      notifyListeners();
    }
  }

  /// Links the selected memory record to a backlog item.
  Future<void> linkSelectedMemoryToTaskFromUi(String taskId) async {
    final server = _primaryGraphServer();
    final drafts = _selectedMemoryLinkDrafts('context');
    if (server == null || drafts.isEmpty) {
      tasksMessage = 'Select a graph memory server and memory record first';
      notifyListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Linking memory to backlog item';
    notifyListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.linkTaskMemory(taskId: taskId, link: drafts.first);
      });
      selectedTaskId = taskId;
      taskSelectionKind = 'task';
      await _loadTasks();
      _setEndpoint(
        server.label,
        ConnectionStateKind.connected,
        'Memory linked',
      );
      tasksMessage = 'Memory linked';
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      notifyListeners();
    }
  }

  /// Unlinks memory from a task.
  Future<void> unlinkTaskMemoryFromUi({
    required String taskId,
    required String linkId,
  }) async {
    final server = _primaryGraphServer();
    if (server == null) {
      return;
    }
    tasksBusy = true;
    tasksMessage = 'Unlinking memory';
    notifyListeners();
    try {
      await _withTasksClientForGraphServer(server, (client) {
        return client.unlinkTaskMemory(taskId: taskId, linkId: linkId);
      });
      selectedTaskId = taskId;
      taskSelectionKind = 'task';
      await _loadTasks();
      tasksMessage = 'Memory unlinked';
      _setEndpoint(server.label, ConnectionStateKind.connected, tasksMessage);
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      notifyListeners();
    }
  }

  /// Builds a compact Backlog snapshot for AI planning.
  BacklogScreenSnapshot _backlogScreenSnapshot(String scopeLabel) {
    return BacklogScreenSnapshot(
      scopeLabel: scopeLabel,
      selectedTaskId: selectedGraphTaskId,
      filters: <String, dynamic>{
        'statuses': taskFilters.statuses,
        'priorities': taskFilters.priorities,
        'topics': taskFilters.topics,
        'search': taskFilters.search,
        'overdue_only': taskFilters.overdueOnly,
        'include_done': taskFilters.includeDone,
      },
      availableTools: primaryMemoryToolNames.toList()..sort(),
      visibleTasks: filteredTasks.take(50).map((task) {
        return BacklogScreenTaskSnapshot(
          id: task.id,
          title: task.title,
          description: task.description,
          status: task.status,
          priority: task.priority,
          dueAt: _screenDateValue(task.dueAt),
          scheduledAt: _screenDateValue(task.scheduledAt),
          followUpAt: _screenDateValue(task.followUpAt),
          topics: task.topics,
          estimateMinutes: task.estimateMinutes,
          context: task.context,
          owner: task.owner,
        );
      }).toList(),
    );
  }

  /// Validates and classifies one Backlog screen-command run.
  ScreenCommandRun _preparedBacklogScreenRun(ScreenCommandRun planned) {
    final bulk = planned.changes.length > 1;
    final prepared = <ScreenChange>[
      for (final change in planned.changes)
        _preparedBacklogScreenChange(change, bulk: bulk),
    ];
    return planned.copyWith(changes: prepared);
  }

  /// Validates and classifies one Backlog screen-command change.
  ScreenChange _preparedBacklogScreenChange(
    ScreenChange change, {
    required bool bulk,
  }) {
    try {
      final toolName = screenChangeOperationToolName(change.operation);
      if (primaryMemoryToolNames.isNotEmpty &&
          !primaryMemoryToolNames.contains(toolName)) {
        return _rejectedScreenChange(change, 'Tool is unavailable: $toolName');
      }
      final target = _resolvedScreenChangeTarget(change);
      final fields = _normalizedScreenFields(change.fields);
      final invalidField = _invalidScreenChangeField(change.operation, fields);
      if (invalidField.isNotEmpty) {
        return _rejectedScreenChange(change, invalidField);
      }
      final beforeValues = _beforeValuesForChange(change, target, fields);
      final afterValues = _afterValuesForChange(change, target, fields);
      final safe =
          !bulk &&
          change.confidence >= 0.85 &&
          target.taskId.isNotEmpty &&
          const <ScreenChangeOperation>{
            ScreenChangeOperation.updateTask,
            ScreenChangeOperation.completeTask,
            ScreenChangeOperation.cancelTask,
          }.contains(change.operation);
      return change.copyWith(
        target: target,
        fields: fields,
        beforeValues: beforeValues,
        afterValues: afterValues,
        safety: safe
            ? ScreenChangeSafety.autoApply
            : ScreenChangeSafety.needsReview,
        status: ScreenChangeStatus.proposed,
        error: '',
      );
    } catch (error) {
      return _rejectedScreenChange(change, error.toString());
    }
  }

  /// Applies all auto-safe changes from a prepared run.
  Future<void> _applyAutoScreenChanges(ScreenCommandRun run) async {
    final autoChanges = run.changes.where((change) {
      return change.status == ScreenChangeStatus.proposed &&
          change.safety == ScreenChangeSafety.autoApply;
    }).toList();
    for (final change in autoChanges) {
      await _applyBacklogScreenChange(change);
    }
  }

  /// Applies one validated Backlog screen change through the task service.
  Future<void> _applyBacklogScreenChange(ScreenChange change) async {
    final server = _primaryGraphServer();
    if (server == null) {
      _replaceScreenChange(
        change.copyWith(
          status: ScreenChangeStatus.failed,
          error: 'No graph memory server',
        ),
      );
      notifyListeners();
      return;
    }
    screenCommandBusy = true;
    screenCommandMessage = 'Applying screen change';
    notifyListeners();
    try {
      String appliedTaskId = change.target.taskId;
      await _withTasksClientForGraphServer(server, (client) async {
        switch (change.operation) {
          case ScreenChangeOperation.createTask:
            final task = await _createTaskForScreenFields(
              client: client,
              fields: change.fields,
            );
            appliedTaskId = task.id;
          case ScreenChangeOperation.updateTask:
            await _updateTaskForScreenFields(
              client: client,
              taskId: change.target.taskId,
              fields: change.fields,
            );
          case ScreenChangeOperation.completeTask:
            await client.completeTask(change.target.taskId);
          case ScreenChangeOperation.cancelTask:
            await client.cancelTask(change.target.taskId);
          case ScreenChangeOperation.deleteTask:
            await client.deleteTask(change.target.taskId);
          case ScreenChangeOperation.upsertTaskRelation:
            await client.upsertTaskRelation(
              fromTaskId: _stringField(change.fields, 'from_task_id'),
              toTaskId: _stringField(change.fields, 'to_task_id'),
              relationType: _stringField(
                change.fields,
                'relation_type',
                fallback: 'related_to',
              ),
              confidence: _doubleField(change.fields, 'confidence'),
              explanation: _stringField(change.fields, 'note'),
            );
          case ScreenChangeOperation.deleteTaskRelation:
            await client.deleteTaskRelation(
              _stringField(change.fields, 'relation_id'),
            );
          case ScreenChangeOperation.linkTaskMemory:
            await client.linkTaskMemory(
              taskId: change.target.taskId,
              link: TaskMemoryLinkDraft(
                memoryId: _stringField(change.fields, 'memory_id'),
                memoryEvidenceId: _stringField(
                  change.fields,
                  'memory_evidence_id',
                ),
                relationship: _stringField(
                  change.fields,
                  'relationship',
                  fallback: 'context',
                ),
                note: _stringField(change.fields, 'note'),
              ),
            );
        }
      });
      if (appliedTaskId.isNotEmpty) {
        selectedTaskId = appliedTaskId;
        taskSelectionKind = 'task';
      }
      await _loadTasks();
      _replaceScreenChange(
        change.copyWith(
          target: change.target.copyWith(taskId: appliedTaskId),
          status: ScreenChangeStatus.applied,
          error: '',
        ),
      );
      screenCommandMessage = 'Screen change applied';
    } catch (error) {
      _replaceScreenChange(
        change.copyWith(status: ScreenChangeStatus.failed, error: '$error'),
      );
      screenCommandMessage = error.toString();
    } finally {
      screenCommandBusy = false;
      notifyListeners();
    }
  }

  /// Creates a task from screen-change fields.
  Future<WorkspaceTask> _createTaskForScreenFields({
    required TasksClient client,
    required Map<String, dynamic> fields,
  }) {
    return client.createTask(
      title: _stringField(fields, 'title'),
      description: _stringField(fields, 'description'),
      status: _stringField(fields, 'status', fallback: 'open'),
      priority: _stringField(fields, 'priority', fallback: 'normal'),
      dueAt: _dateField(fields, 'due_at'),
      scheduledAt: _dateField(fields, 'scheduled_at'),
      followUpAt: _dateField(fields, 'follow_up_at'),
      topics: _stringListField(fields, 'topics'),
      estimateMinutes: _intField(fields, 'estimate_minutes'),
      energyRequired: _stringField(fields, 'energy_required'),
      effort: _doubleField(fields, 'effort'),
      value: _doubleField(fields, 'value'),
      urgency: _doubleField(fields, 'urgency'),
      risk: _doubleField(fields, 'risk'),
      context: _stringField(fields, 'context'),
      domain: _stringField(fields, 'view'),
      project: _stringField(fields, 'project'),
      location: _stringField(fields, 'location'),
      owner: _stringField(fields, 'person'),
      source: _stringField(fields, 'source'),
      confidence: _doubleField(fields, 'confidence'),
    );
  }

  /// Updates a task from screen-change fields.
  Future<WorkspaceTask> _updateTaskForScreenFields({
    required TasksClient client,
    required String taskId,
    required Map<String, dynamic> fields,
  }) {
    return client.updateTask(
      taskId: taskId,
      title: _optionalStringField(fields, 'title'),
      description: _optionalStringField(fields, 'description'),
      status: _optionalStringField(fields, 'status'),
      priority: _optionalStringField(fields, 'priority'),
      dueAt: _dateField(fields, 'due_at'),
      clearDueAt: _boolField(fields, 'clear_due_at'),
      scheduledAt: _dateField(fields, 'scheduled_at'),
      clearScheduledAt: _boolField(fields, 'clear_scheduled_at'),
      followUpAt: _dateField(fields, 'follow_up_at'),
      clearFollowUpAt: _boolField(fields, 'clear_follow_up_at'),
      topics: fields.containsKey('topics')
          ? _stringListField(fields, 'topics')
          : null,
      replaceTopics: fields.containsKey('topics'),
      estimateMinutes: fields.containsKey('estimate_minutes')
          ? _intField(fields, 'estimate_minutes')
          : null,
      energyRequired: _optionalStringField(fields, 'energy_required'),
      effort: fields.containsKey('effort')
          ? _doubleField(fields, 'effort')
          : null,
      value: fields.containsKey('value') ? _doubleField(fields, 'value') : null,
      urgency: fields.containsKey('urgency')
          ? _doubleField(fields, 'urgency')
          : null,
      risk: fields.containsKey('risk') ? _doubleField(fields, 'risk') : null,
      context: _optionalStringField(fields, 'context'),
      domain: _optionalStringField(fields, 'view'),
      project: _optionalStringField(fields, 'project'),
      location: _optionalStringField(fields, 'location'),
      owner: _optionalStringField(fields, 'person'),
      source: _optionalStringField(fields, 'source'),
      confidence: fields.containsKey('confidence')
          ? _doubleField(fields, 'confidence')
          : null,
    );
  }

  /// Replaces one screen change in the active run.
  void _replaceScreenChange(ScreenChange replacement) {
    final run = activeScreenCommandRun;
    if (run == null) {
      return;
    }
    activeScreenCommandRun = run.copyWith(
      changes: run.changes.map((change) {
        return change.id == replacement.id ? replacement : change;
      }).toList(),
    );
  }

  /// Builds the selected ids line used when opening chat from a screen command.
  String _screenCommandRelevantIds() {
    return <String>[
      if (selectedGraphTaskId.isNotEmpty)
        'selected backlog id: $selectedGraphTaskId',
      if (selectedMemory?.id.isNotEmpty == true)
        'selected memory id: ${selectedMemory!.id}',
    ].join(', ');
  }

  /// Returns a concise user-facing summary for a prepared run.
  String _screenRunSummary(ScreenCommandRun run) {
    final rejected = run.changes
        .where((change) => change.safety == ScreenChangeSafety.rejected)
        .length;
    final auto = run.changes
        .where((change) => change.safety == ScreenChangeSafety.autoApply)
        .length;
    final review = run.changes
        .where((change) => change.safety == ScreenChangeSafety.needsReview)
        .length;
    return 'AI found ${run.changes.length} changes: $auto safe, $review review, $rejected rejected';
  }

  /// Resolves or validates the target for one change.
  ScreenChangeTarget _resolvedScreenChangeTarget(ScreenChange change) {
    if (change.operation == ScreenChangeOperation.createTask ||
        change.operation == ScreenChangeOperation.deleteTaskRelation ||
        change.operation == ScreenChangeOperation.upsertTaskRelation) {
      return change.target;
    }
    final taskId = change.target.taskId.trim();
    if (taskId.isNotEmpty) {
      if (_taskById(taskId) == null) {
        throw StateError('Unknown task id: $taskId');
      }
      return change.target.copyWith(taskId: taskId);
    }
    final title = change.target.taskTitle.trim();
    if (title.isEmpty) {
      throw StateError('Task id is required');
    }
    final matches = workspace.tasks.where((task) {
      return task.title.toLowerCase() == title.toLowerCase();
    }).toList();
    if (matches.length != 1) {
      throw StateError(
        matches.isEmpty
            ? 'No task matches "$title"'
            : 'Task title is ambiguous: "$title"',
      );
    }
    return change.target.copyWith(taskId: matches.single.id);
  }

  /// Returns one workspace task by id.
  WorkspaceTask? _taskById(String taskId) {
    for (final task in workspace.tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  /// Returns a rejected copy of a screen change.
  ScreenChange _rejectedScreenChange(ScreenChange change, String error) {
    return change.copyWith(
      status: ScreenChangeStatus.rejected,
      safety: ScreenChangeSafety.rejected,
      error: error,
    );
  }

  /// Normalizes field aliases in a screen-change payload.
  Map<String, dynamic> _normalizedScreenFields(Map<String, dynamic> fields) {
    final normalized = <String, dynamic>{};
    for (final entry in fields.entries) {
      final key = switch (entry.key.trim()) {
        'owner' => 'person',
        'domain' => 'view',
        'type' => 'relation_type',
        'explanation' => 'note',
        _ => entry.key.trim(),
      };
      normalized[key] = entry.value;
    }
    return normalized;
  }

  /// Returns a validation message for invalid operation fields.
  String _invalidScreenChangeField(
    ScreenChangeOperation operation,
    Map<String, dynamic> fields,
  ) {
    final allowed = switch (operation) {
      ScreenChangeOperation.createTask ||
      ScreenChangeOperation.updateTask => _taskScreenChangeFields,
      ScreenChangeOperation.completeTask ||
      ScreenChangeOperation.cancelTask ||
      ScreenChangeOperation.deleteTask => const <String>{},
      ScreenChangeOperation.upsertTaskRelation => const <String>{
        'from_task_id',
        'to_task_id',
        'relation_type',
        'note',
        'confidence',
      },
      ScreenChangeOperation.deleteTaskRelation => const <String>{'relation_id'},
      ScreenChangeOperation.linkTaskMemory => const <String>{
        'memory_id',
        'memory_evidence_id',
        'relationship',
        'note',
      },
    };
    for (final key in fields.keys) {
      if (!allowed.contains(key)) {
        return 'Unsupported field for ${screenChangeOperationToolName(operation)}: $key';
      }
    }
    if ((operation == ScreenChangeOperation.createTask ||
            operation == ScreenChangeOperation.updateTask) &&
        fields.containsKey('status') &&
        !_taskStatusValues.contains(_stringField(fields, 'status'))) {
      return 'Invalid task status: ${_stringField(fields, 'status')}';
    }
    if ((operation == ScreenChangeOperation.createTask ||
            operation == ScreenChangeOperation.updateTask) &&
        fields.containsKey('priority') &&
        !_taskPriorityValues.contains(_stringField(fields, 'priority'))) {
      return 'Invalid task priority: ${_stringField(fields, 'priority')}';
    }
    if (operation == ScreenChangeOperation.createTask &&
        _stringField(fields, 'title').isEmpty) {
      return 'Task title is required';
    }
    if (operation == ScreenChangeOperation.upsertTaskRelation &&
        (_stringField(fields, 'from_task_id').isEmpty ||
            _stringField(fields, 'to_task_id').isEmpty)) {
      return 'Relation changes require from_task_id and to_task_id';
    }
    if (operation == ScreenChangeOperation.deleteTaskRelation &&
        _stringField(fields, 'relation_id').isEmpty) {
      return 'Relation deletion requires relation_id';
    }
    if (operation == ScreenChangeOperation.linkTaskMemory &&
        _stringField(fields, 'memory_id').isEmpty &&
        _stringField(fields, 'memory_evidence_id').isEmpty) {
      return 'Memory link requires a memory id or source record id';
    }
    if (fields.containsKey('topics') && fields['topics'] is! List) {
      return 'topics must be a list';
    }
    for (final key in const <String>[
      'due_at',
      'scheduled_at',
      'follow_up_at',
    ]) {
      if (_stringField(fields, key).isNotEmpty &&
          _dateField(fields, key) == null) {
        return '$key must be an ISO date or timestamp';
      }
    }
    return '';
  }

  /// Captures before-values for a validated change.
  Map<String, dynamic> _beforeValuesForChange(
    ScreenChange change,
    ScreenChangeTarget target,
    Map<String, dynamic> fields,
  ) {
    final task = _taskById(target.taskId);
    if (task == null) {
      return const <String, dynamic>{};
    }
    if (change.operation == ScreenChangeOperation.completeTask ||
        change.operation == ScreenChangeOperation.cancelTask ||
        change.operation == ScreenChangeOperation.deleteTask) {
      return <String, dynamic>{
        'status': task.status,
        'title': task.title,
        'description': task.description,
        'priority': task.priority,
        'due_at': _screenDateValue(task.dueAt),
        'scheduled_at': _screenDateValue(task.scheduledAt),
        'follow_up_at': _screenDateValue(task.followUpAt),
      };
    }
    return <String, dynamic>{
      for (final key in fields.keys) key: _taskValueForField(task, key),
    };
  }

  /// Builds after-values for a validated change.
  Map<String, dynamic> _afterValuesForChange(
    ScreenChange change,
    ScreenChangeTarget target,
    Map<String, dynamic> fields,
  ) {
    if (change.operation == ScreenChangeOperation.completeTask) {
      return const <String, dynamic>{'status': 'done'};
    }
    if (change.operation == ScreenChangeOperation.cancelTask) {
      return const <String, dynamic>{'status': 'canceled'};
    }
    if (change.operation == ScreenChangeOperation.deleteTask) {
      return const <String, dynamic>{'status': 'deleted'};
    }
    return fields;
  }

  /// Returns one task field value in planner wire shape.
  dynamic _taskValueForField(WorkspaceTask task, String key) {
    return switch (key) {
      'title' => task.title,
      'description' => task.description,
      'status' => task.status,
      'priority' => task.priority,
      'due_at' => _screenDateValue(task.dueAt),
      'scheduled_at' => _screenDateValue(task.scheduledAt),
      'follow_up_at' => _screenDateValue(task.followUpAt),
      'topics' => task.topics,
      'estimate_minutes' => task.estimateMinutes,
      'energy_required' => task.energyRequired,
      'effort' => task.effort,
      'value' => task.value,
      'urgency' => task.urgency,
      'risk' => task.risk,
      'context' => task.context,
      'view' => task.domain,
      'project' => task.project,
      'location' => task.location,
      'person' => task.owner,
      'source' => task.source,
      'confidence' => task.confidence,
      'clear_due_at' => task.dueAt == null,
      'clear_scheduled_at' => task.scheduledAt == null,
      'clear_follow_up_at' => task.followUpAt == null,
      _ => '',
    };
  }

  /// Reports whether one applied change has a safe inverse.
  bool _screenChangeCanUndo(ScreenChange change) {
    if (change.operation == ScreenChangeOperation.createTask) {
      return change.target.taskId.isNotEmpty;
    }
    return const <ScreenChangeOperation>{
      ScreenChangeOperation.updateTask,
      ScreenChangeOperation.completeTask,
      ScreenChangeOperation.cancelTask,
    }.contains(change.operation);
  }

  /// Builds update_task fields that reverse one applied task edit.
  Map<String, dynamic> _undoFieldsForChange(ScreenChange change) {
    final fields = <String, dynamic>{};
    for (final entry in change.beforeValues.entries) {
      if (entry.key == 'due_at' && entry.value.toString().isEmpty) {
        fields['clear_due_at'] = true;
      } else if (entry.key == 'scheduled_at' &&
          entry.value.toString().isEmpty) {
        fields['clear_scheduled_at'] = true;
      } else if (entry.key == 'follow_up_at' &&
          entry.value.toString().isEmpty) {
        fields['clear_follow_up_at'] = true;
      } else {
        fields[entry.key] = entry.value;
      }
    }
    return fields;
  }

  /// Formats a nullable date for planner and diff display.
  String _screenDateValue(DateTime? value) {
    return value == null ? '' : value.toIso8601String();
  }

  Future<void> _loadSessions() async {
    await _log('load sessions start');
    try {
      final loaded = await assistantClient.listSessions();
      await _log('load sessions returned ${loaded.length}');
      sessions = loaded;
      if (loaded.isNotEmpty) {
        await _mergeHistorySessions(loaded);
        selectedSessionId = loaded.first.id;
        await selectSession(loaded.first.id);
      } else {
        await _log(
          'load sessions empty; preserving local chat history ${chatHistory.length}',
        );
        selectedSessionId = null;
        messages = const <ChatMessage>[];
      }
      _setEndpoint('Agent API', ConnectionStateKind.connected, 'Connected');
    } catch (error) {
      await _log('load sessions failed: $error');
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    }
  }

  /// Merges active-profile ADK sessions into the local chat history.
  Future<void> _mergeHistorySessions(List<ChatSession> loaded) async {
    var changed = false;
    final entriesByKey = <String, ChatHistoryEntry>{
      for (final entry in chatHistory) entry.key: entry,
    };
    if (runtimeProfile == null || runtimeProfilePath.isEmpty) {
      return;
    }
    for (final session in loaded) {
      final key = _chatHistoryKey(runtimeProfilePath, session.id);
      final existing = entriesByKey[key];
      final entry = _historyEntryForSession(session, existing: existing);
      if (existing == null ||
          existing.updatedAt != entry.updatedAt ||
          existing.profileLabel != entry.profileLabel) {
        entriesByKey[key] = entry;
        changed = true;
      }
    }
    if (!changed) {
      return;
    }
    chatHistory = _sortedHistory(entriesByKey.values);
    await chatHistoryStore.save(chatHistory);
  }

  /// Adds or updates one active-profile chat history entry.
  Future<void> _upsertHistoryChat(ChatSession session) async {
    final entriesByKey = <String, ChatHistoryEntry>{
      for (final entry in chatHistory) entry.key: entry,
    };
    final key = _chatHistoryKey(runtimeProfilePath, session.id);
    entriesByKey[key] = _historyEntryForSession(
      session,
      existing: entriesByKey[key],
    );
    chatHistory = _sortedHistory(entriesByKey.values);
    await chatHistoryStore.save(chatHistory);
  }

  /// Updates an active chat's history timestamp after it is selected.
  Future<void> _touchHistoryChat(String sessionId) async {
    if (runtimeProfile == null || runtimeProfilePath.isEmpty) {
      return;
    }
    final session = sessions.firstWhere(
      (candidate) => candidate.id == sessionId,
      orElse: () => ChatSession(
        id: sessionId,
        title: titleFromSession(sessionId),
        updatedAt: DateTime.now(),
      ),
    );
    await _upsertHistoryChat(session);
  }

  /// Builds a history entry for a session in the active profile.
  ChatHistoryEntry _historyEntryForSession(
    ChatSession session, {
    ChatHistoryEntry? existing,
  }) {
    final profile = _activeRuntimeProfile();
    final existingTitle = existing?.title.trim() ?? '';
    return ChatHistoryEntry(
      profilePath: runtimeProfilePath,
      profileId: profile.id,
      profileLabel: profile.label,
      sessionId: session.id,
      title: existingTitle.isEmpty ? session.title : existingTitle,
      createdAt: existing?.createdAt ?? session.updatedAt,
      updatedAt: session.updatedAt,
      titleStatus: existing?.titleStatus ?? 'session',
      titleError: existing?.titleError ?? '',
    );
  }

  /// Persists one chat history entry without re-reading the whole history.
  Future<void> _saveHistoryEntry(ChatHistoryEntry entry) async {
    final entriesByKey = <String, ChatHistoryEntry>{
      for (final existing in chatHistory) existing.key: existing,
    };
    entriesByKey[entry.key] = entry;
    chatHistory = _sortedHistory(entriesByKey.values);
    await chatHistoryStore.save(chatHistory);
    notifyListeners();
  }

  /// Removes one chat from the local history.
  Future<void> _removeHistoryChat({
    required String profilePath,
    required String sessionId,
  }) async {
    final key = _chatHistoryKey(profilePath, sessionId);
    chatHistory = _sortedHistory(
      chatHistory.where((entry) => entry.key != key),
    );
    await chatHistoryStore.save(chatHistory);
  }

  /// Reports whether the active harness session list includes a session.
  bool _hasLiveSession(String sessionId) {
    return sessions.any((session) => session.id == sessionId);
  }

  /// Ensures a successfully loaded session is present in local live state.
  void _rememberLiveSession(String sessionId) {
    if (_hasLiveSession(sessionId)) {
      return;
    }
    final entry = _historyEntryByKey(
      _chatHistoryKey(runtimeProfilePath, sessionId),
    );
    sessions = <ChatSession>[
      ChatSession(
        id: sessionId,
        title: entry?.title ?? titleFromSession(sessionId),
        updatedAt: entry?.updatedAt ?? DateTime.now(),
      ),
      ...sessions,
    ];
  }

  /// Returns one history entry by stable key.
  ChatHistoryEntry? _historyEntryByKey(String key) {
    for (final entry in chatHistory) {
      if (entry.key == key) {
        return entry;
      }
    }
    return null;
  }

  /// Resolves a chat picker key to a profile path and session id.
  ({String profilePath, String sessionId})? _chatTargetFromKey(String key) {
    final entry = _historyEntryByKey(key);
    if (entry != null) {
      return (profilePath: entry.profilePath, sessionId: entry.sessionId);
    }
    return _parseChatHistoryKey(key);
  }

  /// Starts model-backed chat title refresh without blocking chat display.
  void _scheduleChatTitleRefresh({
    required String profilePath,
    required String sessionId,
    required List<ChatMessage> transcript,
  }) {
    unawaited(
      _refreshChatTitle(
        profilePath: profilePath,
        sessionId: sessionId,
        transcript: transcript,
      ).catchError((Object error) {
        return _log('chat title refresh crashed for $sessionId: $error');
      }),
    );
  }

  /// Generates and persists a model-backed chat title when configured.
  Future<void> _refreshChatTitle({
    required String profilePath,
    required String sessionId,
    required List<ChatMessage> transcript,
  }) async {
    final titleModelConfigPath = summaryModelConfigPath;
    final titleModelRef = summaryModelRef;
    if (!appSettings.chatTitleSummariesEnabled) {
      await _log('chat title refresh skipped for $sessionId: disabled');
      return;
    }
    if (titleModelConfigPath.isEmpty) {
      await _log('chat title refresh skipped for $sessionId: no title model');
      return;
    }
    if (profilePath.trim().isEmpty || sessionId.trim().isEmpty) {
      await _log('chat title refresh skipped: missing profile or session id');
      return;
    }
    final key = _chatHistoryKey(profilePath, sessionId);
    final entry = _historyEntryByKey(key);
    if (entry == null) {
      await _log('chat title refresh skipped for $sessionId: no history entry');
      return;
    }
    final status = entry.titleStatus.trim();
    if (status == 'pending' || status == 'generated') {
      await _log('chat title refresh skipped for $sessionId: status=$status');
      return;
    }
    if (status == 'manual' && !_isFallbackChatTitle(entry.title, sessionId)) {
      await _log('chat title refresh skipped for $sessionId: manual title');
      return;
    }
    await _saveHistoryEntry(
      entry.copyWith(titleStatus: 'pending', titleError: ''),
    );
    await _log(
      'chat title refresh started for $sessionId using $titleModelConfigPath'
      '${titleModelRef.isEmpty ? '' : ' $titleModelRef'}',
    );
    try {
      final title = await titleClient.generateTitle(
        modelConfigPath: titleModelConfigPath,
        modelRef: titleModelRef,
        messages: transcript,
      );
      final current = _historyEntryByKey(key) ?? entry;
      await _saveHistoryEntry(
        current.copyWith(
          title: title,
          titleStatus: 'generated',
          titleError: '',
        ),
      );
      await _log('generated title for chat $sessionId: $title');
    } catch (error) {
      final current = _historyEntryByKey(key) ?? entry;
      await _saveHistoryEntry(
        current.copyWith(titleStatus: 'failed', titleError: error.toString()),
      );
      await _log('chat title generation failed for $sessionId: $error');
    }
  }

  Future<void> _loadMemory() async {
    await _log('load memory start');
    try {
      memoryBusy = true;
      memoryMessage = 'Searching memory';
      notifyListeners();
      final records = <MemoryRecord>[];
      final failures = <String>[];
      for (final server in _activeRuntimeProfile().memoryServers) {
        await _log('load memory via ${server.label} ${server.endpoint}');
        final client = _memoryClientFor(server);
        try {
          records.addAll(
            await client.searchMemory(
              scope: memoryFilters.scope,
              text: memoryFilters.text,
              kinds: memoryFilters.kinds,
              topics: memoryFilters.topics,
              entityIds: memoryFilters.entityIds,
              allowedSensitivities: memoryFilters.allowedSensitivities,
              limit: memoryFilters.limit,
            ),
          );
          _setEndpoint(
            server.label,
            ConnectionStateKind.connected,
            'Connected',
          );
        } catch (error) {
          await _log('load memory failed for ${server.label}: $error');
          failures.add('${server.label}: $error');
          _setEndpoint(
            server.label,
            ConnectionStateKind.disconnected,
            error.toString(),
          );
        } finally {
          if (!identical(client, memoryClient)) {
            client.close();
          }
        }
      }
      workspace = ProjectWorkspace(
        title: workspace.title,
        subtitle: workspace.subtitle,
        tasks: workspace.tasks,
        sources: records.map((record) {
          return SourceItem(
            id: record.id,
            title: record.title,
            detail: '${record.kind} • ${record.sourceLabel}',
          );
        }).toList(),
        memoryRecords: records,
      );
      if (records.isEmpty) {
        selectedMemoryId = null;
      } else if (selectedMemoryId == null ||
          !records.any((record) => record.id == selectedMemoryId)) {
        selectedMemoryId = records.first.id;
      }
      memoryMessage = records.isEmpty
          ? failures.isEmpty
                ? 'No memory records matched the current filters'
                : failures.join(' | ')
          : 'Loaded ${records.length} memory records';
      await _log('load memory complete records=${records.length}');
    } catch (error) {
      await _log('load memory failed: $error');
      memoryMessage = error.toString();
    } finally {
      memoryBusy = false;
    }
    notifyListeners();
  }

  /// Loads the memory-owned Today executive summary projection.
  Future<void> _loadToday({bool quiet = false}) async {
    final profile = runtimeProfile;
    if (profile == null || profile.memoryServers.isEmpty) {
      todayState = todayState.copyWith(
        busy: false,
        error: 'No graph memory server is configured',
      );
      if (!quiet) {
        notifyListeners();
      }
      return;
    }
    if (!quiet) {
      todayState = todayState.copyWith(busy: true, error: '');
      notifyListeners();
    }
    try {
      final projection = alignTodayProjectionWithTaskInsights(
        projection: await executiveSummaryClient.projectExecutiveSummary(),
        index: taskInsightIndex,
      );
      todayState = TodayState(projection: projection);
      _setEndpoint(
        profile.memoryServers.first.label,
        ConnectionStateKind.connected,
        'Today loaded',
      );
    } catch (error) {
      todayState = todayState.copyWith(busy: false, error: error.toString());
      _setEndpoint(
        profile.memoryServers.first.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    }
    notifyListeners();
  }

  /// Loads advertised MCP tool names from the primary graph server.
  Future<void> _loadToolCapabilities() async {
    final server = _primaryGraphServer();
    if (server == null) {
      primaryMemoryToolNames = const <String>{};
      return;
    }
    try {
      final names = await _withTasksClientForGraphServer(server, (client) {
        return client.listToolNames();
      });
      primaryMemoryToolNames = names.toSet();
      _setEndpoint(server.label, ConnectionStateKind.connected, 'Tools ready');
      await _log('loaded ${names.length} tools from ${server.label}');
    } catch (error) {
      primaryMemoryToolNames = const <String>{};
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
      await _log('load tool capabilities failed: $error');
    }
    notifyListeners();
  }

  Future<void> _loadTasks() async {
    await _log('load tasks start');
    tasksBusy = true;
    tasksMessage = 'Loading backlog';
    notifyListeners();
    final tasks = <WorkspaceTask>[];
    final failures = <String>[];
    final profile = runtimeProfile;
    if (profile == null) {
      workspace = ProjectWorkspace(
        title: workspace.title,
        subtitle: workspace.subtitle,
        tasks: const <WorkspaceTask>[],
        sources: workspace.sources,
        memoryRecords: workspace.memoryRecords,
      );
      _clearTaskProjections();
      tasksBusy = false;
      tasksMessage = 'Runtime profile is not loaded';
      notifyListeners();
      return;
    }
    for (final server in profile.memoryServers) {
      await _log('load tasks via ${server.label} ${server.endpoint}');
      final client = _tasksClientFor(server);
      try {
        final serverTasks = await client.listTasks(
          filters: const TaskFilterState(statuses: <String>[]),
          includeDone: true,
          includeLinks: true,
          limit: taskFilters.limit,
        );
        final workBreakdowns = await _loadTaskWorkBreakdowns(client);
        await _log('load tasks ${server.label} returned ${serverTasks.length}');
        tasks.addAll(
          serverTasks.map((task) {
            final workBreakdown =
                _taskWorkBreakdownHasContent(task.workBreakdown)
                ? task.workBreakdown
                : workBreakdowns[task.id];
            return task.copyWith(
              sourceId: server.id,
              sourceLabel: server.label,
              workBreakdown: workBreakdown,
            );
          }),
        );
        _setEndpoint(server.label, ConnectionStateKind.connected, 'Connected');
      } catch (error) {
        await _log('load tasks failed for ${server.label}: $error');
        failures.add('${server.label}: $error');
        _setEndpoint(
          server.label,
          ConnectionStateKind.disconnected,
          error.toString(),
        );
      } finally {
        if (!identical(client, tasksClient)) {
          client.close();
        }
      }
    }
    tasks.sort(_compareTasksForWorkQueue);
    workspace = ProjectWorkspace(
      title: workspace.title,
      subtitle: workspace.subtitle,
      tasks: tasks,
      sources: workspace.sources,
      memoryRecords: workspace.memoryRecords,
    );
    if (selectedTaskId != null &&
        !tasks.any((task) => task.id == selectedTaskId)) {
      selectedTaskId = null;
    }
    await _loadTaskProjections(profile.memoryServers, workspaceTasks: tasks);
    final selectedEdge = selectedTaskConstellationEdge;
    if (selectedEdge != null &&
        (!taskInsightIndex.isVisibleEndpoint(selectedEdge.fromTaskId) ||
            !taskInsightIndex.isVisibleEndpoint(selectedEdge.toTaskId))) {
      selectedTaskConstellationEdge = null;
    }
    tasksMessage = failures.isEmpty
        ? 'Loaded ${tasks.length} backlog items'
        : failures.join(' | ');
    tasksBusy = false;
    await _log('load tasks complete tasks=${tasks.length}');
    unawaited(_loadToday(quiet: true));
    notifyListeners();
  }

  /// Loads WBS graph facts that may be absent from the task DTO.
  Future<Map<String, TaskWorkBreakdown>> _loadTaskWorkBreakdowns(
    TasksClient client,
  ) async {
    try {
      return await client.getTaskWorkBreakdowns();
    } catch (error) {
      await _log('load task WBS facts failed: $error');
      return const <String, TaskWorkBreakdown>{};
    }
  }

  /// Loads read-only task graph projections from memory graph endpoints.
  Future<void> _loadTaskProjections(
    List<McpServerRuntime> servers, {
    required List<WorkspaceTask> workspaceTasks,
  }) async {
    if (servers.isEmpty) {
      _clearTaskProjections();
      return;
    }
    final failures = <String>[];
    var projectionGraph = const TaskProjectionGraph();
    final relationRecords = <TaskRelationRecord>[];
    final commitments = <TaskCommitment>[];
    final relationSuggestions = <TaskRelationSuggestion>[];
    final metadataSuggestions = <TaskMetadataSuggestion>[];
    final commitmentSuggestions = <TaskCommitmentSuggestion>[];
    final server = servers.first;
    final missing = await _missingGraphProjectionTools(server);
    if (missing.isNotEmpty) {
      final message =
          '${server.label} is missing projection tools: ${missing.join(', ')}';
      failures.add(message);
      await _log(message);
    } else {
      try {
        projectionGraph = await _withTasksClientForGraphServer(server, (
          client,
        ) {
          return client.getTaskProjectionGraph();
        });
      } catch (error) {
        failures.add('${server.label} Projection Graph: $error');
      }
    }
    final corrections = await _loadTaskGraphCorrectionsForGraphServer(server);
    relationRecords.addAll(corrections.relations);
    commitments.addAll(corrections.commitments);
    relationSuggestions.addAll(corrections.relationSuggestions);
    metadataSuggestions.addAll(corrections.metadataSuggestions);
    commitmentSuggestions.addAll(corrections.commitmentSuggestions);
    taskProjectionGraph = projectionGraph;
    taskRelations = relationRecords;
    taskCommitments = commitments;
    taskRelationSuggestions = relationSuggestions;
    taskMetadataSuggestions = metadataSuggestions;
    taskCommitmentSuggestions = commitmentSuggestions;
    taskInsightIndex = TaskInsightIndex.build(
      workspaceTasks: workspaceTasks,
      graph: taskProjectionGraph,
      taskRelations: taskRelations,
      taskCommitments: taskCommitments,
      metadataSuggestions: taskMetadataSuggestions,
    );
    taskInsightSummaries = taskInsightIndex.insightSummaries;
    taskStreamProjection = TaskInsightProjectionAdapters.stream(
      taskInsightIndex,
    );
    priorityTerrainProjection = TaskInsightProjectionAdapters.terrain(
      taskInsightIndex,
    );
    taskConstellationProjection = TaskInsightProjectionAdapters.constellation(
      taskInsightIndex,
    );
    taskInsightMessage = taskInsightIndex.projectionCoverageMessage;
    final messages = <String>[
      ...failures,
      if (taskInsightMessage.isNotEmpty) taskInsightMessage,
    ];
    taskProjectionMessage = messages.join(' | ');
    if (taskProjectionMessage.isNotEmpty) {
      await _log('load task projections: $taskProjectionMessage');
    }
  }

  /// Returns projection tools missing from a memory graph endpoint.
  Future<List<String>> _missingGraphProjectionTools(
    McpServerRuntime server,
  ) async {
    try {
      final names = await _withTasksClientForGraphServer(server, (client) {
        return client.listToolNames();
      });
      final available = names.toSet();
      return _requiredTaskProjectionTools
          .where((tool) => !available.contains(tool))
          .toList();
    } catch (error) {
      await _log('task projection tool check failed: $error');
      return const <String>[];
    }
  }

  /// Loads user-correctable graph state from one memory graph endpoint.
  Future<_TaskGraphCorrectionState> _loadTaskGraphCorrectionsForGraphServer(
    McpServerRuntime server,
  ) async {
    final relations = await _optionalTaskToolResult(
      server,
      'list_task_relations',
      const <TaskRelationRecord>[],
      (client) {
        return client.listTaskRelations();
      },
    );
    final commitments = await _optionalTaskToolResult(
      server,
      'list_commitments',
      const <TaskCommitment>[],
      (client) {
        return client.listCommitments();
      },
    );
    final suggestions = await _optionalTaskToolResult(
      server,
      'suggest_task_relationships',
      const <TaskRelationSuggestion>[],
      (client) {
        return client.suggestTaskRelationships();
      },
    );
    final metadataSuggestions = await _optionalTaskToolResult(
      server,
      'suggest_task_metadata',
      const <TaskMetadataSuggestion>[],
      (client) {
        return client.suggestTaskMetadata();
      },
    );
    final commitmentSuggestions = await _optionalTaskToolResult(
      server,
      'suggest_commitments',
      const <TaskCommitmentSuggestion>[],
      (client) {
        return client.suggestCommitments();
      },
    );
    return _TaskGraphCorrectionState(
      relations: relations,
      commitments: commitments,
      relationSuggestions: suggestions,
      metadataSuggestions: metadataSuggestions,
      commitmentSuggestions: commitmentSuggestions,
    );
  }

  /// Returns whether a memory graph endpoint advertises one optional task tool.
  Future<bool> _taskToolAvailable(
    McpServerRuntime server,
    String toolName,
  ) async {
    try {
      final names = await _withTasksClientForGraphServer(server, (client) {
        return client.listToolNames();
      });
      return names.contains(toolName);
    } catch (error) {
      await _log('task tool availability check failed: $error');
      return true;
    }
  }

  /// Loads optional task graph data when the endpoint advertises the tool.
  Future<T> _optionalTaskToolResult<T>(
    McpServerRuntime server,
    String toolName,
    T fallback,
    Future<T> Function(TasksClient client) action,
  ) async {
    if (!await _taskToolAvailable(server, toolName)) {
      return fallback;
    }
    try {
      return await _withTasksClientForGraphServer(server, action);
    } catch (error) {
      await _log('${server.label} optional task tool $toolName failed: $error');
      return fallback;
    }
  }

  /// Clears read-only task projection and graph correction state.
  void _clearTaskProjections() {
    taskProjectionGraph = const TaskProjectionGraph();
    taskInsightIndex = TaskInsightIndex.empty;
    taskInsightSummaries = const <TaskInsightQuerySummary>[];
    taskStreamProjection = const TaskStreamProjection();
    priorityTerrainProjection = const PriorityTerrainProjection();
    taskConstellationProjection = const TaskConstellationProjection();
    taskProjectionMessage = '';
    taskInsightMessage = '';
    taskRelations = const <TaskRelationRecord>[];
    taskCommitments = const <TaskCommitment>[];
    taskRelationSuggestions = const <TaskRelationSuggestion>[];
    taskMetadataSuggestions = const <TaskMetadataSuggestion>[];
    taskCommitmentSuggestions = const <TaskCommitmentSuggestion>[];
  }

  /// Reloads tasks and associates newly created tasks with the active chat.
  Future<void> _loadTasksAfterChatTaskWrite({
    required String sessionId,
    required bool associateCreatedTask,
  }) async {
    final previousTaskIds = workspace.tasks.map((task) => task.id).toSet();
    await _loadTasks();
    if (!associateCreatedTask || sessionId.isEmpty) {
      return;
    }
    final createdTaskIds = workspace.tasks
        .where((task) => !previousTaskIds.contains(task.id))
        .map((task) => task.id)
        .toSet();
    if (createdTaskIds.isEmpty) {
      return;
    }
    final existingTaskIds = _chatTaskIds[sessionId] ?? <String>{};
    _chatTaskIds[sessionId] = <String>{...existingTaskIds, ...createdTaskIds};
    await _log(
      'associated chat $sessionId with created tasks ${createdTaskIds.join(',')}',
    );
    notifyListeners();
  }

  RuntimeProfile _activeRuntimeProfile() {
    final profile = runtimeProfile;
    if (profile == null) {
      throw StateError('Runtime profile is not loaded');
    }
    return profile;
  }

  MemoryClient _memoryClientFor(McpServerRuntime _) {
    return memoryClient;
  }

  TasksClient _tasksClientFor(McpServerRuntime _) {
    return tasksClient;
  }

  String _contextBaseUrl(RuntimeProfile profile) {
    final gateway = profile.gateway;
    if (gateway != null && gateway.enabled) {
      final uri = Uri.parse(gateway.apiBaseUrl);
      return uri.replace(path: '/api/context', query: null).toString();
    }
    return profile.harness.contextApiBaseUrl;
  }

  Map<String, String> _gatewayHeadersForProfile(RuntimeProfile profile) {
    final gateway = profile.gateway;
    if (gateway == null || !gateway.enabled) {
      return const <String, String>{};
    }
    return config.gatewayAuthHeaders;
  }

  Map<String, String> _mcpHeadersFromEnv(
    RuntimeProfile profile,
    McpServerRuntime server,
  ) {
    final gateway = profile.gateway;
    if (gateway == null ||
        !gateway.enabled ||
        server.endpoint != gateway.mcpUrl) {
      return const <String, String>{};
    }
    return const <String, String>{
      'Authorization': 'AGENTAWESOME_GATEWAY_AUTHORIZATION',
    };
  }

  McpServerRuntime? _primaryGraphServer() {
    final servers = runtimeProfile?.memoryServers ?? const <McpServerRuntime>[];
    if (servers.isEmpty) {
      return null;
    }
    return servers.first;
  }

  String _primaryMemoryLabel() {
    final servers = _activeRuntimeProfile().memoryServers;
    if (servers.isEmpty) {
      return 'Memory';
    }
    return servers.first.label;
  }

  Future<void> _mutateTaskGraphFromUi({
    required McpServerRuntime? server,
    required String busyMessage,
    required String successMessage,
    required Future<void> Function(TasksClient client) action,
    String? selectedTaskAfter,
  }) async {
    if (server == null) {
      _setEndpoint(
        'Backlog',
        ConnectionStateKind.disconnected,
        'No graph memory server',
      );
      notifyListeners();
      return;
    }
    tasksBusy = true;
    tasksMessage = busyMessage;
    notifyListeners();
    try {
      await _withTasksClientForGraphServer(server, action);
      if (selectedTaskAfter != null && selectedTaskAfter.isNotEmpty) {
        selectedTaskId = selectedTaskAfter;
        taskSelectionKind = 'task';
      }
      await _loadTasks();
      _setEndpoint(server.label, ConnectionStateKind.connected, successMessage);
      tasksMessage = successMessage;
    } catch (error) {
      tasksMessage = error.toString();
      _setEndpoint(
        server.label,
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      tasksBusy = false;
      notifyListeners();
    }
  }

  String? _taskIdForSuggestion(String suggestionId) {
    for (final suggestion in taskRelationSuggestions) {
      if (suggestion.id == suggestionId) {
        return suggestion.fromTaskId;
      }
    }
    for (final suggestion in taskMetadataSuggestions) {
      if (suggestion.id == suggestionId) {
        return suggestion.taskId;
      }
    }
    for (final suggestion in taskCommitmentSuggestions) {
      if (suggestion.id == suggestionId) {
        return suggestion.taskId;
      }
    }
    return null;
  }

  Future<T> _withTasksClientForGraphServer<T>(
    McpServerRuntime server,
    Future<T> Function(TasksClient client) action,
  ) async {
    final client = _tasksClientFor(server);
    try {
      return await action(client);
    } finally {
      if (!identical(client, tasksClient)) {
        client.close();
      }
    }
  }

  List<TaskMemoryLinkDraft> _selectedMemoryLinkDrafts(String relationship) {
    final memory = selectedMemory;
    if (memory == null) {
      return const <TaskMemoryLinkDraft>[];
    }
    return <TaskMemoryLinkDraft>[
      TaskMemoryLinkDraft(
        memoryId: memory.id,
        memoryEvidenceId: memory.evidenceId,
        relationship: relationship,
        note: memory.title,
      ),
    ];
  }

  void _setEndpoint(String name, ConnectionStateKind state, String message) {
    var found = false;
    endpointStatuses = endpointStatuses.map((status) {
      if (status.name != name) {
        return status;
      }
      found = true;
      return EndpointStatus(
        name: status.name,
        url: status.url,
        state: state,
        message: message,
      );
    }).toList();
    if (!found) {
      endpointStatuses = <EndpointStatus>[
        ...endpointStatuses,
        EndpointStatus(name: name, url: '', state: state, message: message),
      ];
    }
    statusMessage = message;
  }

  void _refreshEndpointSkeleton(RuntimeProfile profile) {
    endpointStatuses = <EndpointStatus>[
      EndpointStatus(
        name: 'Agent API',
        url: profile.harness.apiBaseUrl,
        state: ConnectionStateKind.unknown,
        message: 'Profile updated',
      ),
      for (final server in profile.mcpServers.where((server) => server.enabled))
        EndpointStatus(
          name: server.label,
          url: server.endpoint,
          state: ConnectionStateKind.unknown,
          message: 'Profile updated',
        ),
    ];
  }

  Future<bool> _ensureLiveSession() async {
    final sessionId = selectedSessionId;
    if (sessionId != null && _hasLiveSession(sessionId)) {
      await _log('live session already selected $sessionId');
      return true;
    }
    if (sessionId != null) {
      await _log('selected session missing from live harness list $sessionId');
      await _log('preserving chat history entry for missing live session');
      selectedSessionId = null;
      messages = const <ChatMessage>[];
    }
    await _log('no selected session; creating chat');
    return createChat();
  }

  /// Starts required local services before creating or continuing a chat.
  Future<bool> _ensureChatRuntimeReady() async {
    await _ensureInitialized();
    if (_isClosing) {
      statusMessage = 'Agent Awesome runtime is shutting down';
      notifyListeners();
      return false;
    }
    final profile = runtimeProfile;
    if (profile == null) {
      return false;
    }
    try {
      _throwIfClosing();
      localProcessStatuses = await localServices.startRequiredServices(profile);
      _throwIfClosing();
      await _startConfiguredLocalModelRuntime();
      final failures = localProcessStatuses
          .where((status) => status.state == ConnectionStateKind.disconnected)
          .toList();
      if (failures.isNotEmpty) {
        statusMessage = failures
            .map((status) => '${status.name}: ${status.message}')
            .join(' | ');
        await _log('chat runtime unavailable: $statusMessage');
        notifyListeners();
        return false;
      }
      return true;
    } catch (error) {
      statusMessage = error.toString();
      await _log('chat runtime readiness failed: $error');
      notifyListeners();
      return false;
    }
  }

  String _agentUnavailableMessage() {
    final profile = runtimeProfile;
    if (profile == null) {
      return statusMessage;
    }
    for (final status in localProcessStatuses) {
      if (status.name == profile.harness.label && status.message.isNotEmpty) {
        return 'Agent Awesome could not start the managed harness: ${status.message}';
      }
    }
    for (final status in endpointStatuses) {
      if (status.name == 'Agent API' && status.message.isNotEmpty) {
        return 'Agent Awesome could not reach the managed Agent API: ${status.message}';
      }
    }
    return 'Agent Awesome is still preparing the managed Agent API.';
  }

  Future<void> _streamRun({
    required String sessionId,
    String text = '',
    ConfirmationReply? reply,
  }) async {
    try {
      await _log(
        'stream run start session=$sessionId textLength=${text.length} confirmation=${reply != null}',
      );
      var count = 0;
      ConfirmationRequest? autoConfirmation;
      await for (final event in assistantClient.sendMessage(
        sessionId: sessionId,
        text: text,
        confirmation: reply,
      )) {
        count++;
        await _log(
          'stream event #$count author=${event.author} textLength=${event.text.length} partial=${event.partial} tool=${event.toolActivity?.name ?? ''} error=${event.errorMessage.isNotEmpty}',
        );
        autoConfirmation ??= _applyEvent(event, sessionId: sessionId);
      }
      await _log('stream run complete session=$sessionId events=$count');
      if (count == 0) {
        messages = <ChatMessage>[
          ...messages,
          ChatMessage(
            id: 'runtime-${DateTime.now().microsecondsSinceEpoch}',
            role: ChatRole.tool,
            author: 'Runtime',
            text:
                'The Agent API completed the run without returning any stream events. Check ${config.serviceLogDirectory}/ui.log and harness.log for the request trace.',
            createdAt: DateTime.now(),
          ),
        ];
      }
      _setEndpoint('Agent API', ConnectionStateKind.connected, 'Run complete');
      if (autoConfirmation != null) {
        await _log(
          'auto-approving task confirmation for ${autoConfirmation.toolName}',
        );
        await _sendConfirmationReply(
          sessionId: sessionId,
          confirmation: autoConfirmation,
          option: _approvalOption(autoConfirmation),
        );
      }
      if (reply == null) {
        _scheduleChatTitleRefresh(
          profilePath: runtimeProfilePath,
          sessionId: sessionId,
          transcript: List<ChatMessage>.from(messages),
        );
      }
    } catch (error) {
      await _log('stream run failed session=$sessionId: $error');
      _setEndpoint(
        'Agent API',
        ConnectionStateKind.disconnected,
        error.toString(),
      );
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> _log(String message) async {
    await logger.write('ui', message);
  }

  ConfirmationRequest? _applyEvent(
    AssistantEvent event, {
    required String sessionId,
  }) {
    ConfirmationRequest? autoConfirmation;
    if (event.confirmation != null) {
      final confirmation = event.confirmation!;
      if (_shouldAutoApproveTaskConfirmation(confirmation)) {
        autoConfirmation = confirmation;
      } else {
        pendingConfirmation = confirmation;
      }
    }
    final toolActivity = event.toolActivity;
    final message = _messageFromEvent(event);
    if (message != null) {
      if (message.isPartial && messages.isNotEmpty && messages.last.isPartial) {
        messages = <ChatMessage>[
          ...messages.take(messages.length - 1),
          messages.last.copyWith(text: messages.last.text + message.text),
        ];
      } else {
        messages = <ChatMessage>[...messages, message];
      }
    }
    if (toolActivity != null &&
        toolActivity.status == 'completed' &&
        _taskWriteToolNames.contains(toolActivity.name)) {
      unawaited(
        _loadTasksAfterChatTaskWrite(
          sessionId: sessionId,
          associateCreatedTask: toolActivity.name == 'create_task',
        ),
      );
    }
    notifyListeners();
    return autoConfirmation;
  }

  ChatMessage? _messageFromEvent(AssistantEvent event) {
    if (event.errorMessage.isNotEmpty) {
      return ChatMessage(
        id: event.id,
        role: ChatRole.tool,
        author: 'Runtime',
        text: event.errorMessage,
        createdAt: DateTime.now(),
      );
    }
    if (event.toolActivity != null) {
      return null;
    }
    if (event.text.trim().isEmpty) {
      return null;
    }
    final role = event.author == 'user' ? ChatRole.user : ChatRole.assistant;
    final text = role == ChatRole.user
        ? displayTextFromUserPrompt(event.text)
        : event.text;
    if (text.trim().isEmpty) {
      return null;
    }
    return ChatMessage(
      id: event.id,
      role: role,
      author: role == ChatRole.user ? 'You' : 'Agent Awesome',
      text: text,
      createdAt: DateTime.now(),
      isPartial: event.partial,
    );
  }

  void _replaceMemoryRecord(MemoryRecord replacement) {
    final records = workspace.memoryRecords.map((record) {
      return record.id == replacement.id ? replacement : record;
    }).toList();
    workspace = ProjectWorkspace(
      title: workspace.title,
      subtitle: workspace.subtitle,
      tasks: workspace.tasks,
      sources: workspace.sources,
      memoryRecords: records,
    );
  }

  List<String> _sensitivitiesIncluding(String sensitivity) {
    if (memoryFilters.allowedSensitivities.contains(sensitivity)) {
      return memoryFilters.allowedSensitivities;
    }
    return <String>[...memoryFilters.allowedSensitivities, sensitivity];
  }
}

const Set<String> _taskScreenChangeFields = <String>{
  'title',
  'description',
  'status',
  'priority',
  'due_at',
  'scheduled_at',
  'follow_up_at',
  'clear_due_at',
  'clear_scheduled_at',
  'clear_follow_up_at',
  'topics',
  'estimate_minutes',
  'energy_required',
  'effort',
  'value',
  'urgency',
  'risk',
  'context',
  'view',
  'project',
  'location',
  'person',
  'source',
  'confidence',
};

const Set<String> _taskStatusValues = <String>{
  'open',
  'waiting',
  'blocked',
  'done',
  'canceled',
};

const Set<String> _taskPriorityValues = <String>{
  'low',
  'normal',
  'high',
  'urgent',
};

/// Reads an optional string field from a screen-change payload.
String? _optionalStringField(Map<String, dynamic> fields, String key) {
  if (!fields.containsKey(key)) {
    return null;
  }
  return _stringField(fields, key);
}

/// Reads a string field from a screen-change payload.
String _stringField(
  Map<String, dynamic> fields,
  String key, {
  String fallback = '',
}) {
  return stringValue(fields[key], fallback: fallback, trim: true);
}

/// Reads an integer field from a screen-change payload.
int _intField(Map<String, dynamic> fields, String key) {
  final value = fields[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return intValue(value);
}

/// Reads a floating-point field from a screen-change payload.
double _doubleField(Map<String, dynamic> fields, String key) {
  return doubleValue(fields[key]);
}

/// Reads a boolean field from a screen-change payload.
bool _boolField(Map<String, dynamic> fields, String key) {
  return boolValue(fields[key]);
}

/// Reads a string-list field from a screen-change payload.
List<String> _stringListField(Map<String, dynamic> fields, String key) {
  return stringList(fields[key], trim: true);
}

/// Reads an ISO date or timestamp field from a screen-change payload.
DateTime? _dateField(Map<String, dynamic> fields, String key) {
  return parseOptionalDateTime(fields[key], trim: true);
}

/// Compares tasks for the default work-queue order.
int _compareTasksForWorkQueue(WorkspaceTask left, WorkspaceTask right) {
  final terminalCompare = _terminalRank(left).compareTo(_terminalRank(right));
  if (terminalCompare != 0) {
    return terminalCompare;
  }
  final overdueCompare = (right.overdue ? 1 : 0).compareTo(
    left.overdue ? 1 : 0,
  );
  if (overdueCompare != 0) {
    return overdueCompare;
  }
  final leftDue = left.dueAt ?? left.scheduledAt ?? left.followUpAt;
  final rightDue = right.dueAt ?? right.scheduledAt ?? right.followUpAt;
  if (leftDue != null && rightDue != null) {
    final dueCompare = leftDue.compareTo(rightDue);
    if (dueCompare != 0) {
      return dueCompare;
    }
  } else if (leftDue != null) {
    return -1;
  } else if (rightDue != null) {
    return 1;
  }
  final priorityCompare = _priorityRank(
    left.priority,
  ).compareTo(_priorityRank(right.priority));
  if (priorityCompare != 0) {
    return priorityCompare;
  }
  return left.title.compareTo(right.title);
}

/// Reports whether WBS metadata has useful content for task views.
bool _taskWorkBreakdownHasContent(TaskWorkBreakdown workBreakdown) {
  return workBreakdown.code.isNotEmpty ||
      workBreakdown.deliverable.isNotEmpty ||
      workBreakdown.startCriteria.isNotEmpty ||
      workBreakdown.acceptanceCriteria.isNotEmpty ||
      workBreakdown.requirementRefs.isNotEmpty ||
      workBreakdown.rubricRefs.isNotEmpty ||
      workBreakdown.resources.isNotEmpty ||
      workBreakdown.estimatedCostCents > 0 ||
      workBreakdown.costCurrency.isNotEmpty;
}

/// Returns whether a task is terminal for queue ordering.
int _terminalRank(WorkspaceTask task) {
  return task.status == 'done' || task.status == 'canceled' ? 1 : 0;
}

/// Returns a numeric rank for task priorities.
int _priorityRank(String priority) {
  return switch (priority) {
    'urgent' => 0,
    'high' => 1,
    'normal' => 2,
    'low' => 3,
    _ => 4,
  };
}

/// Returns whether text contains a query case-insensitively.
bool _textContains(String text, String query) {
  return text.toLowerCase().contains(query.trim().toLowerCase());
}

/// Reports whether a task was created in the selected chat session.
bool _taskBelongsToChat(WorkspaceTask task, String sessionId) {
  final key = task.idempotencyKey.trim();
  return key.isNotEmpty && key.contains(sessionId);
}

/// Reports whether a task title is explicitly mentioned in the chat transcript.
bool _taskTitleAppearsInChat(WorkspaceTask task, String conversationText) {
  final title = task.title.trim().toLowerCase();
  if (title.length < 4) {
    return false;
  }
  return conversationText.toLowerCase().contains(title);
}

/// Builds the stable app-local key for a profile/session pair.
String _chatHistoryKey(String profilePath, String sessionId) {
  return '$profilePath::$sessionId';
}

/// Parses a chat history key into its profile path and session id.
({String profilePath, String sessionId})? _parseChatHistoryKey(String key) {
  final separator = key.lastIndexOf('::');
  if (separator <= 0 || separator + 2 >= key.length) {
    return null;
  }
  return (
    profilePath: key.substring(0, separator),
    sessionId: key.substring(separator + 2),
  );
}

/// Sorts chat history entries by most recently updated first.
List<ChatHistoryEntry> _sortedHistory(Iterable<ChatHistoryEntry> entries) {
  final sorted = entries.toList()
    ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return sorted;
}

/// Reports whether a title is still the generated session-id fallback.
bool _isFallbackChatTitle(String title, String sessionId) {
  final fallback = titleFromSession(sessionId);
  return title.trim().isEmpty || title.trim() == fallback;
}

/// Graph-backed task write tools that should refresh the backlog workspace.
const Set<String> _taskWriteToolNames = <String>{
  'create_task',
  'update_task',
  'complete_task',
  'cancel_task',
  'delete_task',
  'link_task_memory',
  'upsert_task_relation',
  'delete_task_relation',
};

/// Returns a non-conflicting profile copy path in the profile directory.
Future<String> _uniqueRuntimeProfilePath(
  String directory,
  String profileId,
) async {
  final base = profileId.trim().isEmpty ? 'profile' : profileId;
  var candidate = '$directory/$base-copy.json';
  var index = 2;
  while (await File(candidate).exists()) {
    candidate = '$directory/$base-copy-$index.json';
    index++;
  }
  return candidate;
}

Future<RuntimeProfileFileEntry> _profileEntryForPath(String path) async {
  try {
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is Map<String, dynamic>) {
      return RuntimeProfileFileEntry(
        path: path,
        id: _optionalString(decoded['id'], fallback: _profileIdFromPath(path)),
        label: _optionalString(
          decoded['label'],
          fallback: _profileIdFromPath(path),
        ),
        active: false,
      );
    }
  } catch (_) {
    // Invalid profile files remain visible by filename so they can be repaired.
  }
  return RuntimeProfileFileEntry(
    path: path,
    id: _profileIdFromPath(path),
    label: _profileIdFromPath(path),
    active: false,
  );
}

Future<String?> _copyConfigIntoAppDirectory({
  required String sourcePath,
  required String targetDirectory,
  required String targetName,
}) async {
  if (sourcePath.trim().isEmpty || sourcePath.startsWith(targetDirectory)) {
    return sourcePath;
  }
  final source = File(sourcePath);
  if (!await source.exists()) {
    return null;
  }
  final directory = Directory(targetDirectory);
  await directory.create(recursive: true);
  final target = File('${directory.path}/$targetName');
  if (!await target.exists()) {
    await target.writeAsString(await source.readAsString());
  }
  return target.path;
}

/// Returns the config path for one required server kind.
String _requiredServerConfigPath(RuntimeProfile profile, String kind) {
  return switch (kind) {
    'memory' => profile.memoryServerConfigPath,
    _ => '',
  };
}

/// Returns the first profile server for a required kind.
McpServerRuntime? _serverForKind(RuntimeProfile profile, String kind) {
  for (final server in profile.mcpServers) {
    if (server.kind == kind) {
      return server;
    }
  }
  return null;
}

/// Returns a stable filename stem for one required server config.
String _serverFileName(McpServerRuntime? server, String fallback) {
  final id = server?.id.trim() ?? '';
  if (id.isNotEmpty) {
    return _sanitizeConfigFileStem(id);
  }
  return fallback;
}

/// Returns a filesystem-safe config filename stem.
String _sanitizeConfigFileStem(String value) {
  final sanitized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return sanitized.isEmpty ? 'config' : sanitized;
}

/// Derives a stable profile id from a profile file path.
String _profileIdFromPath(String path) {
  final filename = path.replaceAll('\\', '/').split('/').last;
  final dot = filename.lastIndexOf('.');
  if (dot <= 0) {
    return filename;
  }
  return filename.substring(0, dot);
}

String _optionalString(dynamic value, {required String fallback}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}
