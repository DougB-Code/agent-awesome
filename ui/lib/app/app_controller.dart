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
import '../domain/credentials.dart';
import '../domain/json_value.dart';
import '../domain/local_models.dart';
import '../domain/model_config.dart';
import '../domain/models.dart';
import '../domain/onboarding_model_setup.dart';
import '../domain/screen_command.dart';
import '../domain/system_capabilities.dart';
import '../domain/task_insight_index.dart';
import '../domain/task_insight_query.dart';
import '../domain/task_projection_adapters.dart';
import '../domain/tool_config.dart';
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
import 'process_supervisor.dart';
import 'runtime_profile.dart';
import 'system_capabilities.dart';

part 'app_controller_screen_commands.dart';
part 'app_controller_runtime_profile.dart';
part 'app_controller_chat.dart';
part 'app_controller_memory.dart';
part 'app_controller_tasks.dart';

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
            environment: Platform.environment,
            localModelChatCompletionsUrl: config.localModelChatCompletionsUrl,
            logger: effectiveLogger,
          ),
      screenCommandPlanner:
          screenCommandPlanner ??
          ScreenCommandClient(
            environment: Platform.environment,
            logger: effectiveLogger,
          ),
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
      memoryFilters = _memoryFiltersForConfiguredFirewalls(memoryFilters);
      if (config.autoStartLocalServices) {
        await appSettingsStore.saveMemoryFirewallPolicy(appSettings);
      }
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
      final restoredLocalModel = await _restoreLocalModelIfAvailable(
        allowDefaultModel:
            !appSettings.gettingStartedCompleted || !hasConfiguredModel,
      );
      if (restoredLocalModel && !appSettings.gettingStartedCompleted) {
        appSettings = appSettings.copyWith(gettingStartedCompleted: true);
        await appSettingsStore.save(appSettings);
        await _log('completed setup from verified local model');
      }
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
      await _markSetupIncompleteForUnavailableLocalModel();
    } catch (error) {
      if (_isClosing) {
        statusMessage = 'Agent Awesome runtime is shutting down';
        _initialized = true;
        notifyListeners();
        return;
      }
      await _log('local model startup failed: $error');
      await _markSetupIncompleteForUnavailableLocalModel();
    }
    _shellDecisionReady = true;
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

  /// Restores local LiteRT config from a verified app-managed model artifact.
  Future<bool> _restoreLocalModelIfAvailable({
    required bool allowDefaultModel,
  }) async {
    final provider = await _activeLocalProviderConfig();
    if (provider == null && !allowDefaultModel) {
      return false;
    }
    final modelId = provider?.defaultModel ?? onboardingLocalModels.first.id;
    final descriptor = onboardingLocalModelDescriptor(modelId);
    final configuredModelPath = provider == null
        ? ''
        : _configuredLocalModelPath(provider);
    final install = await localModels.recoverInstalled(
      descriptor,
      candidatePaths: <String>[
        if (configuredModelPath.isNotEmpty) configuredModelPath,
      ],
    );
    if (install == null) {
      await _log('local model restore skipped: ${descriptor.id} not found');
      return false;
    }
    final executable = await _localModelExecutableForConfig();
    if (executable == null) {
      return false;
    }
    if (configuredModelPath == install.modelPath &&
        provider?.executable == executable) {
      return true;
    }
    final result = await _saveOnboardingProviderConfig(
      onboardingLocalProviderConfig(
        modelId: descriptor.id,
        executable: executable,
        modelPath: install.modelPath,
      ),
    );
    if (result.success) {
      runtimeProfile = await RuntimeProfileLoader(
        config,
      ).loadFile(File(runtimeProfilePath));
      _configureClientsForRuntimeProfile(runtimeProfile!);
      await _log('local model restored: ${descriptor.id}');
      return true;
    } else {
      await _log('local model restore failed: ${result.message}');
      return false;
    }
  }

  /// Returns the executable path to persist for local model provider config.
  Future<String?> _localModelExecutableForConfig() async {
    final configured = config.litertLmExecutable.trim();
    try {
      return await LocalModelExecutableResolver(
        commandRunner: ProcessSupervisorCommandRunner(processSupervisor),
      ).resolve(
        configuredExecutable: configured,
        dataDirectory: agentAwesomeDataDirectoryPath(),
      );
    } catch (error) {
      await _log('local model executable unresolved: $error');
      return null;
    }
  }

  /// Reopens setup when the configured local runtime cannot start.
  Future<void> _markSetupIncompleteForUnavailableLocalModel() async {
    if (!appSettings.gettingStartedCompleted) {
      return;
    }
    final provider = await _activeLocalProviderConfig();
    if (provider == null) {
      return;
    }
    for (final status in localProcessStatuses) {
      if (status.name == 'Local model' &&
          status.state == ConnectionStateKind.disconnected) {
        appSettings = appSettings.copyWith(gettingStartedCompleted: false);
        await appSettingsStore.save(appSettings);
        await _log('setup marked incomplete: ${status.message}');
        return;
      }
    }
  }

  /// Returns the active configured LiteRT artifact path.
  String _configuredLocalModelPath(ModelProviderConfig provider) {
    for (final model in provider.models) {
      if (model.id == provider.defaultModel) {
        return model.path.trim();
      }
    }
    return '';
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

  /// Returns configured memory firewall choices.
  List<MemoryFirewall> get memoryFirewalls {
    return appSettings.effectiveMemoryFirewalls;
  }

  /// Returns configured memory firewall ids.
  List<String> get memoryFirewallIds {
    return memoryFirewalls.map((firewall) => firewall.id).toList();
  }

  /// Returns the fallback memory firewall id.
  String get defaultMemoryFirewallId {
    final firewalls = memoryFirewalls;
    for (final firewall in firewalls) {
      if (firewall.id == 'user') {
        return firewall.id;
      }
    }
    return firewalls.first.id;
  }

  /// Returns a readable label for one memory firewall id.
  String memoryFirewallLabel(String id) {
    for (final firewall in memoryFirewalls) {
      if (firewall.id == id) {
        return firewall.label;
      }
    }
    return id;
  }

  /// Returns the configured sharing audience for one memory firewall id.
  List<String> memoryFirewallSharedWith(String id) {
    for (final firewall in memoryFirewalls) {
      if (firewall.id == id) {
        return firewall.sharedWith;
      }
    }
    return const <String>[];
  }

  /// Returns a readable sharing audience label for one memory firewall id.
  String memoryFirewallAudienceLabel(String id) {
    return memoryFirewallSharedWith(id).join(', ');
  }

  /// Returns a compact dropdown label for one memory firewall id.
  String memoryFirewallPickerLabel(String id) {
    final audience = memoryFirewallAudienceLabel(id);
    final label = memoryFirewallLabel(id);
    return audience.isEmpty ? label : '$label / $audience';
  }

  /// Returns memory filters aligned to configured firewall choices.
  MemoryFilterState _memoryFiltersForConfiguredFirewalls(
    MemoryFilterState filters,
  ) {
    final ids = memoryFirewallIds;
    final includeGlobal =
        ids.contains('global') &&
        filters.firewall != 'global' &&
        filters.includeGlobal;
    return ids.contains(filters.firewall)
        ? filters.copyWith(includeGlobal: includeGlobal)
        : filters.copyWith(
            firewall: defaultMemoryFirewallId,
            includeGlobal: includeGlobal,
          );
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

  /// Saves user-configured memory firewalls.
  Future<void> setMemoryFirewalls(List<MemoryFirewall> firewalls) async {
    final normalized = normalizeMemoryFirewalls(firewalls);
    final selected =
        normalized.any((firewall) => firewall.id == memoryFilters.firewall)
        ? memoryFilters.firewall
        : normalized.first.id;
    await saveAppSettings(appSettings.copyWith(memoryFirewalls: normalized));
    await _restartMemoryServicesForFirewallPolicy();
    var reloaded = false;
    if (selected != memoryFilters.firewall) {
      await applyMemoryFilters(
        memoryFilters.copyWith(
          firewall: selected,
          includeGlobal: selected == 'global'
              ? false
              : memoryFilters.includeGlobal,
        ),
      );
      reloaded = true;
    } else if (!normalized.any((firewall) => firewall.id == 'global') &&
        memoryFilters.includeGlobal) {
      await applyMemoryFilters(memoryFilters.copyWith(includeGlobal: false));
      reloaded = true;
    }
    if (!reloaded) {
      await _loadMemory();
    }
  }

  /// Restarts managed memory services after the firewall policy file changes.
  Future<void> _restartMemoryServicesForFirewallPolicy() async {
    final profile = runtimeProfile;
    if (profile == null || !config.autoStartLocalServices || _isClosing) {
      return;
    }
    statusMessage = 'Memory firewall policy saved; restarting memory service';
    notifyListeners();
    localProcessStatuses = await localServices.restartMemoryServices(profile);
    for (final status in localProcessStatuses) {
      await _log(
        'memory service restart ${status.name} ${status.state.name}: ${status.message}',
      );
    }
    notifyListeners();
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
      install =
          await localModels.recoverInstalled(
            descriptor,
            onProgress: onProgress,
          ) ??
          await localModels.ensureInstalled(descriptor, onProgress: onProgress);
      _throwIfClosing();
      executable = await localModels.ensureRuntimeInstalled(
        onProgress: onProgress,
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

  /// Notifies listeners for controller part-file workflows.
  void _notifyControllerListeners() {
    notifyListeners();
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
