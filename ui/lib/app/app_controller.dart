/// Owns Agent Awesome UI state and coordinates service clients.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

import '../clients/assistant_client.dart';
import '../clients/automations_client.dart';
import '../clients/chat_title_client.dart';
import '../clients/executive_summary_client.dart';
import '../clients/mcp_client.dart';
import '../clients/screen_command_client.dart';
import '../domain/agent_config.dart';
import '../domain/agent_validation_result.dart';
import '../domain/automation_contracts.dart';
import '../domain/config_yaml.dart';
import '../domain/credentials.dart';
import '../domain/executive_summary.dart';
import '../domain/json_value.dart';
import '../domain/library_validation_result.dart';
import '../domain/local_models.dart';
import '../domain/model_config.dart';
import '../domain/models.dart';
import '../domain/models_automation.dart';
import '../domain/onboarding_model_setup.dart';
import '../domain/remote_runtime_bundle.dart';
import '../domain/screen_command.dart';
import '../domain/system_capabilities.dart';
import '../domain/task_insight_index.dart';
import '../domain/task_insight_query.dart';
import '../domain/task_projection_adapters.dart';
import '../domain/tool_config.dart';
import '../domain/tool_validation_result.dart';
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
part 'app_controller_automations.dart';

const List<String> _requiredTaskProjectionTools = <String>[
  'task_graph_projection',
];

/// Provider ids owned by the app-managed local model setup flow.
const Set<String> _managedLocalModelProviderIds = <String>{
  'litert-lm',
  'llama-cpp',
};

/// Interval for quietly refreshing user-deployable runbook files.
const Duration _automationFileRefreshInterval = Duration(seconds: 5);

/// Interval for following active runbook runs after a user starts one.
const Duration _automationRunRefreshInterval = Duration(seconds: 2);

/// Reports whether a provider id belongs to an app-managed local runtime.
bool _isManagedLocalModelProviderId(String providerId) {
  return _managedLocalModelProviderIds.contains(providerId.trim());
}

/// Returns the gateway MCP route for one policy-checked memory domain.
@visibleForTesting
String gatewayMemoryMcpEndpointFor(
  RuntimeProfile profile,
  McpServerRuntime server,
) {
  final domainId = server.id.trim();
  final uri = Uri.parse(profile.gateway.mcpUrl);
  if (domainId.isEmpty) {
    return uri.toString();
  }
  final basePath = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return uri.replace(path: '$basePath/$domainId').toString();
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
    AutomationsClient? automationsClient,
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
            baseUrl: config.agentGatewayBaseUrl,
            appName: config.agentAppName,
            userId: config.agentUserId,
            headers: config.gatewayAuthHeaders,
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
      automationsClient:
          automationsClient ??
          AutomationsClient(
            baseUrl: _runbookBaseUrl(config.agentGatewayBaseUrl),
            headers: config.gatewayAuthHeaders,
            logger: effectiveLogger,
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
            baseUrl: config.agentGatewayBaseUrl,
            appName: config.agentAppName,
            userId: config.agentUserId,
            headers: config.gatewayAuthHeaders,
            logger: effectiveLogger,
          ),
      screenCommandPlanner:
          screenCommandPlanner ??
          ScreenCommandClient(
            baseUrl: config.agentGatewayBaseUrl,
            appName: config.agentAppName,
            userId: config.agentUserId,
            headers: config.gatewayAuthHeaders,
            logger: effectiveLogger,
          ),
      fileImporter: fileImporter ?? const FileSelectorAgentFileImporter(),
      assistantClientInjected: assistantClient != null,
      memoryClientInjected: memoryClient != null,
      tasksClientInjected: tasksClient != null,
      executiveSummaryClientInjected: executiveSummaryClient != null,
      automationsClientInjected: automationsClient != null,
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
    required this.automationsClient,
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
    required bool automationsClientInjected,
    required bool screenCommandPlannerInjected,
  }) : _assistantClientInjected = assistantClientInjected,
       _memoryClientInjected = memoryClientInjected,
       _tasksClientInjected = tasksClientInjected,
       _executiveSummaryClientInjected = executiveSummaryClientInjected,
       _automationsClientInjected = automationsClientInjected,
       _screenCommandPlannerInjected = screenCommandPlannerInjected;

  /// Runtime service configuration.
  final AppConfig config;

  /// File logger for UI and client diagnostics.
  final AppLogger logger;

  /// Shared owner for all app-started subprocesses.
  final ProcessSupervisor processSupervisor;

  /// Assistant runtime client.
  AssistantClient assistantClient;

  /// Memory MCP client.
  MemoryClient memoryClient;

  /// Client for graph-backed task tools exposed by the memory service.
  TasksClient tasksClient;

  /// Client for the canonical Today projection tools.
  ExecutiveSummaryClient executiveSummaryClient;

  /// Gateway-routed client for runbook automation APIs.
  AutomationsClient automationsClient;

  /// Local process supervisor for the managed service stack.
  final LocalServiceSupervisor localServices;

  /// Local model installer and runtime supervisor.
  final LocalModelRuntime localModels;

  /// File store for editable model and agent configurations.
  final ConfigFileStore configFiles;

  /// Store for app-owned settings.
  final AgentAwesomeAppSettingsStore appSettingsStore;

  /// Store for local chat metadata across selected agents.
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
  final bool _automationsClientInjected;
  final bool _screenCommandPlannerInjected;

  /// Active agent runtime topology for harness configs and MCP topology.
  RuntimeProfile? runtimeProfile;

  /// Filesystem path for the loaded agent runtime topology.
  String runtimeProfilePath = '';

  /// Model config files available in the app config directory.
  List<ConfigFileEntry> availableModelConfigs = const <ConfigFileEntry>[];

  /// Agent config files available in the app config directory.
  List<ConfigFileEntry> availableAgentConfigs = const <ConfigFileEntry>[];

  /// Tool config files available in the app config directory.
  List<ConfigFileEntry> availableToolConfigs = const <ConfigFileEntry>[];

  /// MCP config packages available in the app config directory.
  List<ConfigFileEntry> availableMcpConfigs = const <ConfigFileEntry>[];

  /// App-specific settings outside agent runtime topology ownership.
  AgentAwesomeAppSettings appSettings = const AgentAwesomeAppSettings();

  Future<void>? _initialization;
  bool _initialized = false;
  bool _shellDecisionReady = false;
  bool _clientsClosed = false;
  Future<void>? _localServicesCloseFuture;
  Future<void>? _localModelsCloseFuture;
  Future<void>? _runtimeStartup;
  Future<void>? _closeFuture;
  Future<void>? _automationFileRefresh;
  Timer? _automationFileRefreshTimer;
  Timer? _automationRunRefreshTimer;
  bool _runtimeServicesNeedRestart = false;
  bool _automationRunRefreshInFlight = false;
  int _automationRunRefreshTicks = 0;
  Map<String, String> _runtimeGatewayHeaders = const <String, String>{};
  bool _closing = false;

  /// Reports whether UI listeners are attached to this controller.
  bool get _hasControllerListeners => hasListeners;

  /// All known chat sessions.
  List<ChatSession> sessions = const <ChatSession>[];

  /// App-owned chat metadata across profiles.
  List<ChatHistoryEntry> chatHistory = const <ChatHistoryEntry>[];

  /// Currently selected chat session id.
  String? selectedSessionId;

  /// Stable history key for the currently selected chat card.
  String selectedChatHistoryKey = '';

  /// Provider:model ref selected for the next chat turn.
  String chatModelRef = '';

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

  /// Latest canonical projection graph shared by task views.
  TaskProjectionGraph taskProjectionGraph = const TaskProjectionGraph();

  /// Latest task insight read model shared by task views.
  TaskInsightIndex taskInsightIndex = TaskInsightIndex.empty;

  /// Latest named insight summaries.
  List<TaskInsightQuerySummary> taskInsightSummaries =
      const <TaskInsightQuerySummary>[];

  /// Latest task stream projection.
  TaskStreamProjection taskStreamProjection = const TaskStreamProjection();

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

  /// Currently selected graph backlog item id.
  String? selectedTaskId;

  /// Currently selected task constellation relation edge.
  TaskConstellationEdge? selectedTaskConstellationEdge;

  /// Current graph backlog selection kind.
  String taskSelectionKind = 'task';

  /// Whether a backlog launch is currently running.
  bool tasksBusy = false;

  /// Last backlog-specific launch message.
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

  /// Whether Automations is showing the auxiliary chat pane.
  bool automationsChatPanelOpen = false;

  /// Whether the current workspace is showing the auxiliary AI chat pane.
  bool assistantChatPanelOpen = false;

  /// Whether an Automations launch is currently running.
  bool automationsBusy = false;

  /// Last actionable Automations error or runtime message.
  String automationsMessage = '';

  /// Runbook action types loaded for authoring.
  List<AutomationActionType> automationActionTypes =
      const <AutomationActionType>[];

  /// Installed runbook definitions.
  List<AutomationDefinition> automationDefinitions =
      const <AutomationDefinition>[];

  /// Definition ids currently backed by local runbook authoring files.
  Set<String> _localAutomationDefinitionIds = const <String>{};

  /// Editable runbook drafts.
  List<AutomationDraft> automationDrafts = const <AutomationDraft>[];

  /// Recent runbook runs.
  List<AutomationRun> automationRuns = const <AutomationRun>[];

  /// Saved Launchpad.
  List<AutomationRunSetup> automationRunSetups = const <AutomationRunSetup>[];

  /// Codebase catalog records available to Launchpad.
  List<AutomationCodebase> automationCodebases = const <AutomationCodebase>[];

  /// Harness capabilities available to Capability Lab.
  List<AutomationCapability> automationCapabilities =
      const <AutomationCapability>[];

  /// Computer or Server targets available to Launchpad.
  List<AutomationRuntimeTarget> automationRuntimeTargets =
      const <AutomationRuntimeTarget>[];

  /// Pending runbook inbox items.
  List<AutomationPendingItem> automationInbox = const <AutomationPendingItem>[];

  /// Installed automation packages.
  List<AutomationPackage> automationPackages = const <AutomationPackage>[];

  /// Events for the selected automation run.
  List<AutomationEvent> selectedAutomationEvents = const <AutomationEvent>[];

  /// Latest preview for the selected saved Launch.
  AutomationLaunchPreview? selectedAutomationLaunchPreview;

  /// Immutable audit snapshot for the selected Launch run.
  AutomationLaunchRunSnapshot? selectedAutomationLaunchRunSnapshot;

  /// Health metadata for the selected Computer or Server target.
  AutomationTargetHealth? selectedAutomationTargetHealth;

  /// Recent logs for the selected Computer or Server target.
  List<AutomationTargetLogEntry> selectedAutomationTargetLogs =
      const <AutomationTargetLogEntry>[];

  /// Secret reference metadata for the selected Computer or Server target.
  AutomationTargetSecretMetadata? selectedAutomationTargetSecrets;

  /// Selected automation draft id.
  String selectedAutomationDraftId = '';

  /// Selected automation run id.
  String selectedAutomationRunId = '';

  /// Selected Launch id.
  String selectedAutomationRunSetupId = '';

  /// Selected codebase catalog id.
  String selectedAutomationCodebaseId = '';

  /// Selected capability registry id.
  String selectedAutomationCapabilityId = '';

  /// Selected Computer or Server target id.
  String selectedAutomationRuntimeTargetId = '';

  /// Selected pending automation inbox item id.
  String selectedAutomationPendingItemId = '';

  /// Selected published automation definition id.
  String selectedAutomationDefinitionId = '';

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

  /// Whether a memory launch is currently running.
  bool memoryBusy = false;

  /// Last memory-specific launch message.
  String memoryMessage = 'Memory is ready for review';

  /// Recent memory domain safety decisions.
  List<MemorySafetyEvent> memorySafetyEvents = const <MemorySafetyEvent>[];

  /// Endpoint statuses displayed in settings.
  List<EndpointStatus> endpointStatuses = const <EndpointStatus>[];

  /// Local service process statuses displayed in settings.
  List<ServiceProcessStatus> localProcessStatuses =
      const <ServiceProcessStatus>[];

  /// Tool names advertised by the active primary memory MCP endpoint.
  Set<String> primaryMemoryToolNames = const <String>{};

  /// Tool names advertised by the harness context API for automation steps.
  Set<String> automationToolNames = const <String>{};

  /// Pending runtime confirmation request.
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
      chatHistory = await chatHistoryStore.load();
      _restoreSelectedChatFromHistory();
      await _log(
        'loaded chat history ${chatHistory.length} from ${chatHistoryPath()}',
      );
      final loader = RuntimeProfileLoader(config);
      final profileFile = await _resolveInitialProfileFile(loader);
      await _log('resolved agent runtime topology ${profileFile.path}');
      runtimeProfilePath = profileFile.path;
      runtimeProfile = await _loadInitialRuntimeProfile(loader, profileFile);
      runtimeProfile = await _migrateDefaultProfileConfigs(runtimeProfile!);
      runtimeProfile = await _withAppRuntimeSelections(runtimeProfile!);
      if (config.autoStartLocalServices) {
        await _saveMemoryFirewallPolicyForActiveProfile();
      }
      await _refreshConfigCollections();
      await _configureClientsForRuntimeProfile(runtimeProfile!);
      await _completeSetupFromExternalGatewayIfConfigured();
      final restoredLocalModel = await _restoreLocalModelIfAvailable(
        allowDefaultModel:
            !appSettings.gettingStartedCompleted || !hasConfiguredModel,
      );
      if (restoredLocalModel && !appSettings.gettingStartedCompleted) {
        appSettings = appSettings.copyWith(gettingStartedCompleted: true);
        await appSettingsStore.save(appSettings);
        await _log('completed setup from verified local model');
      }
      await _log('loaded agent runtime ${runtimeProfile!.id}');
    } catch (error) {
      await _log('agent runtime load failed: $error');
      _shellDecisionReady = true;
      runtimeProfile = null;
      runtimeProfilePath = config.runtimeProfilePath;
      endpointStatuses = <EndpointStatus>[
        EndpointStatus(
          name: 'Agent runtime',
          url: config.runtimeProfilePath,
          state: ConnectionStateKind.disconnected,
          message: error.toString(),
        ),
      ];
      localProcessStatuses = const <ServiceProcessStatus>[];
      statusMessage = 'Agent runtime failed to load: $error';
      _initialized = true;
      notifyListeners();
      return;
    }
    endpointStatuses = <EndpointStatus>[
      EndpointStatus(
        name: 'Agent API',
        url: runtimeProfile!.gateway.apiBaseUrl,
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
    _shellDecisionReady = true;
    notifyListeners();
    if (!appSettings.gettingStartedCompleted) {
      statusMessage = 'Model setup required';
      _initialized = true;
      await _log('initialize paused for first-run model setup');
      notifyListeners();
      return;
    }
    await _startRuntimeServicesAndLoadData();
    _initialized = true;
    await _log('initialize complete');
  }

  /// Completes first-run setup when a cloud gateway owns model configuration.
  Future<void> _completeSetupFromExternalGatewayIfConfigured() async {
    final profile = runtimeProfile;
    if (profile == null ||
        appSettings.gettingStartedCompleted ||
        !_externalGatewayModelConfigured(profile)) {
      return;
    }
    appSettings = appSettings.copyWith(gettingStartedCompleted: true);
    await appSettingsStore.save(appSettings);
    await _log('completed setup from external gateway model metadata');
  }

  /// Starts model-backed services and loads data after setup is complete.
  Future<void> _startRuntimeServicesAndLoadData() {
    _runtimeStartup ??= _startRuntimeServicesAndLoadDataOnce();
    return _runtimeStartup!;
  }

  /// Performs one runtime service startup and initial data load.
  Future<void> _startRuntimeServicesAndLoadDataOnce() async {
    try {
      _throwIfClosing();
      await _log('starting required local services');
      localProcessStatuses = await _startRequiredRuntimeServices(
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
      await _recordUnavailableLocalModelStatus();
    } catch (error) {
      if (_isClosing) {
        statusMessage = 'Agent Awesome runtime is shutting down';
        notifyListeners();
        return;
      }
      await _log('local model startup failed: $error');
      await _recordUnavailableLocalModelStatus();
    }
    notifyListeners();
    if (_requiredLocalServiceStartupFailed()) {
      statusMessage = 'Local services are not ready';
      await _log(
        'initial data load skipped because local services are not ready',
      );
      notifyListeners();
      return;
    }
    await _loadToolCapabilities();
    await _log('loading sessions, memory, and tasks');
    await Future.wait(<Future<void>>[
      _loadSessions(),
      _loadMemory(),
      _loadTasks(),
      _loadAutomations(),
    ]);
    startAutomationFileRefreshFromUi();
  }

  /// Reports whether a required non-model service failed before data loading.
  bool _requiredLocalServiceStartupFailed() {
    for (final status in localProcessStatuses) {
      if (_isLocalModelProcessStatus(status)) {
        continue;
      }
      if (status.state == ConnectionStateKind.disconnected) {
        return true;
      }
    }
    return false;
  }

  /// Resolves the startup service topology from env override or template.
  Future<File> _resolveInitialProfileFile(RuntimeProfileLoader loader) async {
    if (config.runtimeProfilePath.trim().isNotEmpty) {
      return loader.resolveProfileFile();
    }
    return loader.resolveProfileFile();
  }

  /// Loads the startup topology and repairs only the app-owned default topology.
  Future<RuntimeProfile> _loadInitialRuntimeProfile(
    RuntimeProfileLoader loader,
    File profileFile,
  ) async {
    try {
      return await loader.loadFile(profileFile);
    } catch (error) {
      if (!_isAppOwnedDefaultRuntimeProfile(loader, profileFile)) {
        rethrow;
      }
      await _log('rewriting invalid default agent runtime topology: $error');
      final resetFile = await loader.writeDefaultRuntimeProfileFile();
      runtimeProfilePath = resetFile.path;
      return loader.loadFile(resetFile);
    }
  }

  /// Reports whether a topology path is the managed default topology file.
  bool _isAppOwnedDefaultRuntimeProfile(
    RuntimeProfileLoader loader,
    File profileFile,
  ) {
    if (config.runtimeProfilePath.trim().isNotEmpty) {
      return false;
    }
    return profileFile.absolute.path ==
        File(loader.defaultRuntimeProfilePath()).absolute.path;
  }

  /// Starts an already installed local model when the active config selects it.
  Future<void> _startConfiguredLocalModelRuntime() async {
    _throwIfClosing();
    final provider = await _activeLocalProviderConfig();
    if (provider == null) {
      return;
    }
    final descriptor = _localModelDescriptorForProvider(provider);
    if (!await localModels.isInstalled(descriptor)) {
      final status = ServiceProcessStatus(
        name: descriptor.providerName,
        url: _localRuntimeHealthUrlFor(descriptor),
        state: ConnectionStateKind.disconnected,
        message: '${descriptor.displayName} is not installed',
      );
      localProcessStatuses = <ServiceProcessStatus>[
        ...localProcessStatuses.where(
          (item) => !_isLocalModelProcessStatus(item),
        ),
        status,
      ];
      await _log('local model not installed: ${descriptor.id}');
      return;
    }
    final status = await localModels.start(descriptor);
    localProcessStatuses = <ServiceProcessStatus>[
      ...localProcessStatuses.where(
        (item) => !_isLocalModelProcessStatus(item),
      ),
      status,
    ];
    await _log('local model status ${status.state.name}: ${status.message}');
  }

  /// Restores local model config from a verified app-managed artifact.
  Future<bool> _restoreLocalModelIfAvailable({
    required bool allowDefaultModel,
  }) async {
    final provider = await _activeLocalProviderConfig();
    if (provider == null && !allowDefaultModel) {
      return false;
    }
    final descriptor = provider == null
        ? onboardingLocalModelDescriptor(onboardingLocalModels.first.id)
        : _localModelDescriptorForProvider(provider);
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
    final executable = await _localModelExecutableForConfig(descriptor);
    if (executable == null) {
      return false;
    }
    if (configuredModelPath == install.modelPath &&
        provider?.executable == executable &&
        provider != null &&
        _usesDescriptorLocalModelProviderShape(provider, descriptor)) {
      return true;
    }
    final result = await _saveOnboardingProviderConfig(
      onboardingLocalProviderConfig(
        modelId: descriptor.id,
        executable: executable,
        modelPath: install.modelPath,
        url: _localRuntimeChatCompletionsUrlFor(descriptor),
      ),
    );
    if (result.success) {
      runtimeProfile = await RuntimeProfileLoader(
        config,
      ).loadFile(File(runtimeProfilePath));
      await _configureClientsForRuntimeProfile(runtimeProfile!);
      await _log('local model restored: ${descriptor.id}');
      return true;
    } else {
      await _log('local model restore failed: ${result.message}');
      return false;
    }
  }

  /// Returns the executable path to persist for local model provider config.
  Future<String?> _localModelExecutableForConfig(
    LocalModelDescriptor descriptor,
  ) async {
    final configured = switch (descriptor.runtimeKind) {
      LocalModelRuntimeKind.litertLm => config.litertLmExecutable.trim(),
      LocalModelRuntimeKind.llamaCpp => config.llamaCppExecutable.trim(),
    };
    final aliases = switch (descriptor.runtimeKind) {
      LocalModelRuntimeKind.litertLm => const <String>[
        'litert_lm',
        'litert-lm',
      ],
      LocalModelRuntimeKind.llamaCpp => const <String>['llama-server'],
    };
    try {
      return await LocalModelExecutableResolver(
        commandRunner: ProcessSupervisorCommandRunner(processSupervisor),
        aliases: aliases,
        displayName: descriptor.providerName,
      ).resolve(
        configuredExecutable: configured,
        dataDirectory: agentAwesomeDataDirectoryPath(),
      );
    } catch (error) {
      await _log('local model executable unresolved: $error');
      return null;
    }
  }

  /// Records local runtime startup problems without reopening first-run setup.
  Future<void> _recordUnavailableLocalModelStatus() async {
    final provider = await _activeLocalProviderConfig();
    if (provider == null) {
      return;
    }
    for (final status in localProcessStatuses) {
      if (_isLocalModelProcessStatus(status) &&
          status.state == ConnectionStateKind.disconnected) {
        final detail = status.message.trim();
        statusMessage = detail.isEmpty
            ? 'Local model unavailable'
            : 'Local model unavailable: $detail';
        await _log('local model unavailable: ${status.message}');
        return;
      }
    }
  }

  /// Returns the active configured local model artifact path.
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
    if (!_isManagedLocalModelProviderId(defaultProvider)) {
      return null;
    }
    for (final provider in document.providers) {
      if (_isLocalModelProviderCandidate(provider, defaultProvider)) {
        return provider;
      }
    }
    return null;
  }

  /// Reports whether a provider points to the app-managed local model.
  bool _isLocalModelProviderCandidate(
    ModelProviderConfig provider,
    String defaultProvider,
  ) {
    if (provider.id != defaultProvider ||
        !_isManagedLocalModelProviderId(provider.id)) {
      return false;
    }
    return _usesCurrentLocalModelProviderShape(provider);
  }

  /// Reports whether a provider already uses the current loopback HTTP shape.
  bool _usesCurrentLocalModelProviderShape(ModelProviderConfig provider) {
    final auth = stringValue(provider.extra['auth'], trim: true);
    final descriptor = onboardingLocalModelDescriptor(provider.defaultModel);
    final runtime = stringValue(provider.extra['runtime'], trim: true);
    if (provider.id != descriptor.providerId) {
      return false;
    }
    return provider.adapter.trim() == 'openai' &&
        auth == 'optional' &&
        runtime == _localRuntimeConfigValue(descriptor.runtimeKind) &&
        provider.url.trim() ==
            _localRuntimeChatCompletionsUrlForKind(descriptor.runtimeKind);
  }

  /// Reports whether a provider already matches the persisted descriptor shape.
  bool _usesDescriptorLocalModelProviderShape(
    ModelProviderConfig provider,
    LocalModelDescriptor descriptor,
  ) {
    final runtime = stringValue(provider.extra['runtime'], trim: true);
    return provider.id == descriptor.providerId &&
        _usesCurrentLocalModelProviderShape(provider) &&
        runtime == _localRuntimeConfigValue(descriptor.runtimeKind);
  }

  /// Reports whether a process status belongs to a managed local model runtime.
  bool _isLocalModelProcessStatus(ServiceProcessStatus status) {
    return status.name == gemma4E2BLocalModel.providerName ||
        status.name == llamaGemma4E2BLocalModel.providerName;
  }

  /// Returns local model metadata for a persisted provider config.
  LocalModelDescriptor _localModelDescriptorForProvider(
    ModelProviderConfig provider,
  ) {
    return onboardingLocalModelDescriptor(provider.defaultModel);
  }

  /// Returns the chat endpoint URL for one local model descriptor.
  String _localRuntimeChatCompletionsUrlFor(LocalModelDescriptor descriptor) {
    return _localRuntimeChatCompletionsUrlForKind(descriptor.runtimeKind);
  }

  /// Returns the chat endpoint URL for one local runtime kind.
  String _localRuntimeChatCompletionsUrlForKind(LocalModelRuntimeKind kind) {
    return switch (kind) {
      LocalModelRuntimeKind.litertLm => config.localModelChatCompletionsUrl,
      LocalModelRuntimeKind.llamaCpp => config.llamaCppChatCompletionsUrl,
    };
  }

  /// Returns the model config runtime value for one local runtime kind.
  String _localRuntimeConfigValue(LocalModelRuntimeKind kind) {
    return switch (kind) {
      LocalModelRuntimeKind.litertLm => 'litert-lm',
      LocalModelRuntimeKind.llamaCpp => 'llama-cpp',
    };
  }

  /// Returns the health endpoint URL for one local model descriptor.
  String _localRuntimeHealthUrlFor(LocalModelDescriptor descriptor) {
    return switch (descriptor.runtimeKind) {
      LocalModelRuntimeKind.litertLm => config.localModelHealthUrl,
      LocalModelRuntimeKind.llamaCpp => config.llamaCppHealthUrl,
    };
  }

  /// Reloads model, agent, and tool file collection metadata.
  Future<void> _refreshConfigCollections() async {
    final profile = runtimeProfile;
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
    availableMcpConfigs = await configFiles.list(kind: ConfigFileKind.mcp);
  }

  /// Refreshes file-backed profile, model, and agent collections.
  Future<void> refreshConfigurationCollections() async {
    await _refreshConfigCollections();
    notifyListeners();
  }

  /// Returns the agent config selected for new chat and command traffic.
  String get defaultAgentConfigPath {
    final configured = appSettings.defaultAgentConfigPath.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    return runtimeProfile?.harness.agentConfigPath.trim() ?? '';
  }

  /// Returns the selected agent's current display label.
  String get activeAgentLabel {
    final path = defaultAgentConfigPath;
    for (final entry in availableAgentConfigs) {
      if (entry.path == path) {
        return entry.label;
      }
    }
    if (path.trim().isEmpty) {
      return 'Agent';
    }
    return ConfigFileEntry(
      path: path,
      kind: ConfigFileKind.agent,
      assigned: true,
    ).label;
  }

  /// Returns the memory domain selected for automatic memory launchpad.
  String get selectedMemoryDomainId {
    final configured = appSettings.selectedMemoryDomainId.trim();
    final profile = runtimeProfile;
    if (configured.isNotEmpty &&
        profile != null &&
        profile.memoryDomains.any((domain) => domain.id == configured)) {
      return configured;
    }
    return profile?.agentMemory.defaultWriteDomain.trim() ?? '';
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

  /// Returns whether the active agent runtime has at least one selectable model.
  bool get hasConfiguredModel {
    final profile = runtimeProfile;
    if (profile == null) {
      return false;
    }
    if (_externalGatewayModelConfigured(profile)) {
      return true;
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

  /// Reports whether an external gateway owns the active model selection.
  bool _externalGatewayModelConfigured(RuntimeProfile profile) {
    final gateway = profile.gateway;
    return gateway.enabled &&
        !gateway.autoStart &&
        gateway.modelProviderId.trim().isNotEmpty &&
        gateway.modelId.trim().isNotEmpty;
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
    if (selectedChatHistoryKey.isNotEmpty) {
      return selectedChatHistoryKey;
    }
    final sessionId = selectedSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return '';
    }
    return _chatHistoryKey(sessionId);
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
    await appSettingsStore.save(
      settings,
      extraPolicyActors: _activeMemoryPolicyActors(),
    );
    statusMessage = 'App settings saved';
    notifyListeners();
  }

  /// Saves memory firewall policy with active runtime actor grants.
  Future<void> _saveMemoryFirewallPolicyForActiveProfile() async {
    await appSettingsStore.saveMemoryFirewallPolicy(
      appSettings,
      extraPolicyActors: _activeMemoryPolicyActors(),
    );
  }

  /// Returns active agent principals that local memory services must trust.
  List<String> _activeMemoryPolicyActors() {
    final actor = runtimeProfile?.agentMemory.actor.trim() ?? '';
    if (actor.isEmpty) {
      return const <String>[];
    }
    return <String>[actor];
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
    final wasCompleted = appSettings.gettingStartedCompleted;
    await saveAppSettings(
      appSettings.copyWith(gettingStartedCompleted: completed),
    );
    if (completed && !wasCompleted && _initialized && runtimeProfile != null) {
      statusMessage = 'Starting Agent Awesome services';
      notifyListeners();
      await _startRuntimeServicesAndLoadData();
    }
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

  /// Makes a local model runtime provider the active default.
  Future<OnboardingModelSetupResult> configureOnboardingLocalModel({
    required String modelId,
    void Function(LocalModelInstallProgress progress)? onProgress,
  }) async {
    final model = onboardingLocalModelById(modelId);
    final descriptor = onboardingLocalModelDescriptor(model.id);
    if (_isClosing) {
      return OnboardingModelSetupResult(
        success: false,
        message: 'Agent Awesome runtime is shutting down',
        providerName: descriptor.providerName,
        modelId: model.id,
      );
    }
    final targetCheck = _onboardingModelConfigTargetCheck(
      providerName: descriptor.providerName,
      modelId: model.id,
    );
    if (targetCheck != null) {
      return targetCheck;
    }
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
        model: descriptor,
        onProgress: onProgress,
      );
    } catch (error) {
      return OnboardingModelSetupResult(
        success: false,
        message: error.toString(),
        providerName: descriptor.providerName,
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
        url: _localRuntimeChatCompletionsUrlFor(descriptor),
      ),
    );
    if (!result.success) {
      return result;
    }
    return OnboardingModelSetupResult(
      success: true,
      message: '${descriptor.providerName} model saved',
      providerName: descriptor.providerName,
      modelId: model.id,
    );
  }

  /// Reports whether the selected onboarding local model is already installed.
  Future<bool> isOnboardingLocalModelInstalled(String modelId) async {
    final model = onboardingLocalModelById(modelId);
    final descriptor = onboardingLocalModelDescriptor(model.id);
    return localModels.isInstalled(descriptor);
  }

  /// Writes the active model provider into the current model config file.
  Future<OnboardingModelSetupResult> _saveOnboardingProviderConfig(
    ModelProviderConfig provider,
  ) async {
    final targetCheck = _onboardingModelConfigTargetCheck(
      providerName: provider.displayName,
      modelId: provider.defaultModel,
    );
    if (targetCheck != null) {
      return targetCheck;
    }
    final profile = runtimeProfile!;
    final path = profile.harness.modelConfigPath.trim();
    final file = File(path);
    final content = await file.exists() ? await file.readAsString() : '';
    final document = ModelConfigDocument.parse(content);
    final next = modelConfigDocumentForProvider(
      provider,
      validations: document.validations,
      extra: document.extra,
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

  /// Validates that onboarding can write the active model config file.
  OnboardingModelSetupResult? _onboardingModelConfigTargetCheck({
    required String providerName,
    required String modelId,
  }) {
    final profile = runtimeProfile;
    if (profile == null) {
      return OnboardingModelSetupResult(
        success: false,
        message: 'Agent runtime is not loaded',
        providerName: providerName,
        modelId: modelId,
      );
    }
    final path = profile.harness.modelConfigPath.trim();
    if (path.isEmpty) {
      return OnboardingModelSetupResult(
        success: false,
        message: 'Model config path is not configured',
        providerName: providerName,
        modelId: modelId,
      );
    }
    return null;
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
    automationsClient.close();
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
      _automationFileRefreshTimer?.cancel();
      _automationFileRefreshTimer = null;
      _automationRunRefreshTimer?.cancel();
      _automationRunRefreshTimer = null;

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

  /// Notifies listeners for controller part-file runbooks.
  void _notifyControllerListeners() {
    notifyListeners();
  }

  /// Selects the home workspace without fabricating local data.
  void openHome() {
    unawaited(_loadToday(quiet: true));
    notifyListeners();
  }

  /// Toggles the global auxiliary AI chat pane.
  void toggleAssistantChatPanel() {
    assistantChatPanelOpen = !assistantChatPanelOpen;
    notifyListeners();
  }

  /// Opens the global auxiliary AI chat pane.
  void openAssistantChatPanel() {
    assistantChatPanelOpen = true;
    notifyListeners();
  }

  /// Closes the global auxiliary AI chat pane.
  void closeAssistantChatPanel() {
    assistantChatPanelOpen = false;
    backlogChatPanelOpen = false;
    automationsChatPanelOpen = false;
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
    final server = _primaryGraphServer();
    if (server == null) {
      todayState = todayState.copyWith(
        busy: false,
        error: 'No graph memory server is configured',
        selectedExplanationItemId: trimmed,
      );
      notifyListeners();
      return;
    }
    todayState = todayState.copyWith(
      busy: true,
      error: '',
      selectedExplanationItemId: trimmed,
    );
    notifyListeners();
    try {
      final explanation = await _withExecutiveSummaryClientForServer(server, (
        client,
      ) {
        return client.explainExecutiveSummaryItem(trimmed);
      });
      todayState = todayState.copyWith(
        busy: false,
        error: '',
        explanation: explanation,
      );
    } catch (error) {
      todayState = todayState.copyWith(
        busy: false,
        error: _todayProjectionErrorMessage(error, server),
      );
      await _log('explain Today item failed: $error');
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

  /// Selects the runbook workspace without fabricating local data.
  void openWorkspace() {
    notifyListeners();
  }

  /// Loads the memory-owned Today executive summary projection.
  Future<void> _loadToday({bool quiet = false}) async {
    final profile = runtimeProfile;
    final server = _primaryGraphServer();
    if (profile == null || server == null) {
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
        projection: await _withExecutiveSummaryClientForServer(server, (
          client,
        ) {
          return client.projectExecutiveSummary();
        }),
        index: taskInsightIndex,
      );
      todayState = TodayState(projection: projection);
      _setEndpoint(server.label, ConnectionStateKind.connected, 'Today loaded');
    } catch (error) {
      final message = _todayProjectionErrorMessage(error, server);
      todayState = todayState.copyWith(busy: false, error: message);
      _setEndpoint(server.label, ConnectionStateKind.disconnected, message);
      await _log('load Today failed: $error');
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
      throw StateError('Agent runtime is not loaded');
    }
    return profile;
  }

  /// Creates a memory client routed through the active control plane domain.
  MemoryClient _memoryClientFor(McpServerRuntime server) {
    if (_memoryClientInjected) {
      return memoryClient;
    }
    final profile = _activeRuntimeProfile();
    return MemoryClient(
      rpc: GatewayContextClient(
        baseUrl: _contextBaseUrl(profile),
        domainId: server.id,
        headers: _runtimeGatewayHeaders,
        logger: logger,
      ),
    );
  }

  /// Runs one memory launch and closes transient control-plane clients.
  Future<T> _withMemoryClientForServer<T>(
    McpServerRuntime server,
    Future<T> Function(MemoryClient client) action,
  ) async {
    final client = _memoryClientFor(server);
    try {
      return await action(client);
    } finally {
      if (!identical(client, memoryClient)) {
        client.close();
      }
    }
  }

  /// Runs one harness-enforced memory policy launch.
  Future<T> _withMemoryControlClient<T>(
    Future<T> Function(MemoryClient client) action,
  ) async {
    final client = _memoryControlClient();
    try {
      return await action(client);
    } finally {
      if (!identical(client, memoryClient)) {
        client.close();
      }
    }
  }

  /// Creates a memory client without a preselected domain.
  MemoryClient _memoryControlClient() {
    if (_memoryClientInjected) {
      return memoryClient;
    }
    final profile = _activeRuntimeProfile();
    return MemoryClient(
      rpc: GatewayContextClient(
        baseUrl: _contextBaseUrl(profile),
        headers: _runtimeGatewayHeaders,
        logger: logger,
      ),
    );
  }

  /// Finds the memory server that owns a returned memory record.
  McpServerRuntime _memoryServerForRecord(MemoryRecord record) {
    final domainId = record.domainId.trim();
    if (domainId.isNotEmpty) {
      for (final server in _activeRuntimeProfile().memoryServers) {
        if (server.id == domainId) {
          return server;
        }
      }
      throw StateError('Memory domain "$domainId" is not available');
    }
    final server = _primaryGraphServer();
    if (server == null) {
      throw StateError('No memory domain is available');
    }
    return server;
  }

  /// Returns the configured default write memory domain server.
  McpServerRuntime _defaultWriteMemoryServer() {
    final profile = _activeRuntimeProfile();
    final defaultDomain = profile.agentMemory.defaultWriteDomain;
    for (final server in profile.memoryServers) {
      if (server.id == defaultDomain) {
        return server;
      }
    }
    throw StateError(
      'Default write memory domain "$defaultDomain" is not available',
    );
  }

  /// Builds a stable selection key that includes domain provenance.
  String _memorySelectionKey(MemoryRecord record) {
    final domainId = record.domainId.trim();
    return domainId.isEmpty ? record.id : '$domainId:${record.id}';
  }

  /// Annotates a memory record with the domain that returned it.
  MemoryRecord _withRecordDomain(MemoryRecord record, McpServerRuntime server) {
    return record.copyWith(domainId: server.id);
  }

  /// Annotates a compiled memory page with the domain that returned it.
  CompiledMemoryPage _withPageDomain(
    CompiledMemoryPage page,
    McpServerRuntime server,
  ) {
    return page.copyWith(domainId: server.id);
  }

  /// Returns the profile-scoped memory actor for auditable writes.
  String _memoryActor() {
    return _activeRuntimeProfile().agentMemory.actor;
  }

  /// Creates a task client routed through the active control plane domain.
  TasksClient _tasksClientFor(McpServerRuntime server) {
    if (_tasksClientInjected) {
      return tasksClient;
    }
    final profile = _activeRuntimeProfile();
    return TasksClient(
      rpc: GatewayContextClient(
        baseUrl: _contextBaseUrl(profile),
        domainId: server.id,
        headers: _runtimeGatewayHeaders,
        logger: logger,
      ),
    );
  }

  /// Creates a Today projection client routed through one memory domain.
  ExecutiveSummaryClient _executiveSummaryClientFor(McpServerRuntime server) {
    if (_executiveSummaryClientInjected) {
      return executiveSummaryClient;
    }
    final profile = _activeRuntimeProfile();
    return ExecutiveSummaryClient(
      rpc: McpJsonRpcClient(
        endpoint: gatewayMemoryMcpEndpointFor(profile, server),
        headers: _runtimeGatewayHeaders,
        logger: logger,
      ),
    );
  }

  /// Runs one Today projection launch and closes transient clients.
  Future<T> _withExecutiveSummaryClientForServer<T>(
    McpServerRuntime server,
    Future<T> Function(ExecutiveSummaryClient client) action,
  ) async {
    final client = _executiveSummaryClientFor(server);
    try {
      return await action(client);
    } finally {
      if (!identical(client, executiveSummaryClient)) {
        client.close();
      }
    }
  }

  /// Returns the graph server that owns a task mutation target.
  McpServerRuntime? _graphServerForTaskId(String taskId) {
    final id = taskId.trim();
    if (id.isEmpty) {
      return _primaryGraphServer();
    }
    for (final task in workspace.tasks) {
      if (task.id == id && task.sourceId.trim().isNotEmpty) {
        return _memoryServerForDomainId(task.sourceId);
      }
    }
    return _primaryGraphServer();
  }

  /// Returns an enabled memory server by configured domain id.
  McpServerRuntime? _memoryServerForDomainId(String domainId) {
    final id = domainId.trim();
    if (id.isEmpty) {
      return null;
    }
    for (final server in _activeRuntimeProfile().memoryServers) {
      if (server.id == id) {
        return server;
      }
    }
    return null;
  }

  McpServerRuntime? _primaryGraphServer() {
    final profile = runtimeProfile;
    final servers = profile?.memoryServers ?? const <McpServerRuntime>[];
    if (servers.isEmpty) {
      return null;
    }
    final defaultWriteDomain = profile?.agentMemory.defaultWriteDomain ?? '';
    for (final server in servers) {
      if (server.id == defaultWriteDomain) {
        return server;
      }
    }
    return servers.first;
  }

  String _primaryMemoryLabel() {
    return _primaryGraphServer()?.label ?? 'Memory';
  }

  /// Returns display-safe Today loading errors for memory service outages.
  String _todayProjectionErrorMessage(Object error, McpServerRuntime server) {
    final text = error.toString();
    if (_isTodayMemoryUnavailable(text)) {
      return 'Today is unavailable because ${server.label} is not reachable. '
          'Start or restart local services, then open Today again.';
    }
    return text;
  }

  /// Detects Today memory failures that should not expose raw transport text.
  bool _isTodayMemoryUnavailable(String message) {
    final text = message.toLowerCase();
    final usesTodayMemoryRoute =
        text.contains('/api/context/tools/call') ||
        text.contains('context/tools/call') ||
        text.contains('/mcp');
    if (!usesTodayMemoryRoute) {
      return false;
    }
    return text.contains('http 503') ||
        text.contains('memory domain dependency not ready') ||
        text.contains('connection refused') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable');
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
        url: profile.gateway.apiBaseUrl,
        state: ConnectionStateKind.unknown,
        message: 'Agent runtime updated',
      ),
      for (final server in profile.mcpServers.where((server) => server.enabled))
        EndpointStatus(
          name: server.label,
          url: server.endpoint,
          state: ConnectionStateKind.unknown,
          message: 'Agent runtime updated',
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
      final toolActivity = event.toolActivity!;
      if (toolActivity.status == 'completed' &&
          _taskWriteToolNames.contains(toolActivity.name)) {
        return ChatMessage(
          id: event.id,
          role: ChatRole.tool,
          author: 'Runtime',
          text: toolActivity.summary,
          createdAt: DateTime.now(),
          toolActivity: toolActivity,
        );
      }
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
      modelRef: role == ChatRole.assistant ? event.modelRef : '',
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

/// Builds the stable app-local key for a chat session.
String _chatHistoryKey(String sessionId) {
  return sessionId;
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

/// Builds a readable chat title without calling a model.
String _fallbackChatTitleFromTranscript(
  List<ChatMessage> transcript,
  String sessionId,
) {
  for (final role in const <ChatRole>[ChatRole.user, ChatRole.assistant]) {
    for (final message in transcript) {
      if (message.role != role) {
        continue;
      }
      final title = _compactFallbackTitle(message.text);
      if (title.isNotEmpty) {
        return title;
      }
    }
  }
  return titleFromSession(sessionId);
}

/// Trims one chat message into a stable local title.
String _compactFallbackTitle(String text) {
  var title = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  title = title.replaceAll(RegExp(r'''^["']+|["']+$'''), '').trim();
  if (title.length < 4) {
    return '';
  }
  if (title.length <= 64) {
    return title;
  }
  final truncated = title.substring(0, 64).trimRight();
  final wordBoundary = truncated.lastIndexOf(' ');
  if (wordBoundary >= 32) {
    return truncated.substring(0, wordBoundary).trimRight();
  }
  return truncated;
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
