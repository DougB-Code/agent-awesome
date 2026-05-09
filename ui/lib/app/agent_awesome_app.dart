/// Builds the top-level Agent Awesome Flutter application.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import '../ui/agent_awesome_shell.dart';
import '../ui/onboarding/setup_wizard_shell.dart';
import 'app_config.dart';
import 'app_controller.dart';
import 'theme.dart';

/// AgentAwesomeApp owns app lifetime, theme, and controller creation.
class AgentAwesomeApp extends StatefulWidget {
  /// Creates the Agent Awesome app.
  const AgentAwesomeApp({super.key, required this.config});

  /// Runtime service configuration.
  final AppConfig config;

  @override
  State<AgentAwesomeApp> createState() => _AgentAwesomeAppState();
}

class _AgentAwesomeAppState extends State<AgentAwesomeApp> {
  late final AgentAwesomeAppController controller;
  late final _ExitObserver _exitObserver;
  ConfirmationRequest? _shownConfirmation;
  StreamSubscription<ProcessSignal>? _sigIntSubscription;
  StreamSubscription<ProcessSignal>? _sigTermSubscription;
  Future<void>? _closeFuture;
  bool _shutdownVisible = false;
  String _shutdownMessage = 'Preparing to shut down';
  ThemeMode _themeMode = ThemeMode.light;

  /// Initializes the app controller.
  @override
  void initState() {
    super.initState();
    controller = AgentAwesomeAppController(config: widget.config);
    controller.addListener(_watchConfirmation);
    _exitObserver = _ExitObserver(onExitRequested: _requestAppExit);
    WidgetsBinding.instance.addObserver(_exitObserver);
    _sigIntSubscription = _watchSignal(ProcessSignal.sigint);
    if (!Platform.isWindows) {
      _sigTermSubscription = _watchSignal(ProcessSignal.sigterm);
    }
    unawaited(controller.initialize());
  }

  /// Cleans up UI-owned listeners and managed service processes.
  @override
  void dispose() {
    unawaited(_sigIntSubscription?.cancel());
    unawaited(_sigTermSubscription?.cancel());
    WidgetsBinding.instance.removeObserver(_exitObserver);
    unawaited(_closeForExit(requestPlatformExit: false));
    super.dispose();
  }

  /// Builds the Material application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agent Awesome',
      theme: buildAgentAwesomeTheme(),
      darkTheme: buildAgentAwesomeTheme(brightness: Brightness.dark),
      themeMode: _themeMode,
      builder: (context, child) {
        return AgentAwesomeThemeScope(
          themeMode: _themeMode,
          onToggleTheme: _toggleThemeMode,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (!controller.shellDecisionReady) {
                return const _StartupShell();
              }
              if (!controller.gettingStartedCompleted) {
                return SetupWizardShell(controller: controller);
              }
              return AgentAwesomeShell(controller: controller);
            },
          ),
          if (_shutdownVisible) _ShutdownOverlay(message: _shutdownMessage),
        ],
      ),
    );
  }

  /// Toggles the explicit light or dark app theme.
  void _toggleThemeMode() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  /// Shows a tool-call approval dialog for newly pending confirmations.
  void _watchConfirmation() {
    final confirmation = controller.pendingConfirmation;
    if (confirmation == null || identical(confirmation, _shownConfirmation)) {
      return;
    }
    _shownConfirmation = confirmation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Approve Tool Call'),
            content: Text(confirmation.hint),
            actions: confirmation.options.map((option) {
              return TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(controller.answerConfirmation(option));
                },
                child: Text(option.label),
              );
            }).toList(),
          );
        },
      ).then((_) {
        _shownConfirmation = null;
      });
    });
  }

  /// Registers one process-signal cleanup handler.
  StreamSubscription<ProcessSignal>? _watchSignal(ProcessSignal signal) {
    try {
      return signal.watch().listen((_) {
        unawaited(_handleProcessSignal(signal));
      });
    } on UnsupportedError {
      return null;
    }
  }

  /// Cancels the first close request so shutdown progress can be shown.
  Future<AppExitResponse> _requestAppExit() async {
    unawaited(_closeForExit(requestPlatformExit: true));
    return AppExitResponse.cancel;
  }

  /// Stops local resources before exiting from a terminal signal.
  Future<void> _handleProcessSignal(ProcessSignal signal) async {
    try {
      await _closeForExit(requestPlatformExit: false);
    } finally {
      exit(signal == ProcessSignal.sigint ? 130 : 143);
    }
  }

  /// Closes UI-owned clients and stops managed service state once.
  Future<void> _closeForExit({required bool requestPlatformExit}) {
    return _closeFuture ??= () async {
      _setShutdownMessage('Preparing to shut down');
      controller.removeListener(_watchConfirmation);
      await controller.close(onStatus: _setShutdownMessage);
      _setShutdownMessage('Shutdown complete');
      if (requestPlatformExit) {
        await ServicesBinding.instance.exitApplication(AppExitType.required);
      }
    }();
  }

  /// Updates the shutdown overlay while teardown is running.
  void _setShutdownMessage(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _shutdownVisible = true;
      _shutdownMessage = message;
    });
  }
}

/// StartupShell keeps first paint neutral until the app chooses a real shell.
class _StartupShell extends StatelessWidget {
  /// Creates the neutral startup surface.
  const _StartupShell();

  /// Builds a non-setup loading state while persisted settings are read.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

/// ShutdownOverlay blocks duplicate close requests and reports teardown progress.
class _ShutdownOverlay extends StatelessWidget {
  /// Creates a modal shutdown progress surface.
  const _ShutdownOverlay({required this.message});

  /// Latest shutdown status line.
  final String message;

  /// Builds the modal shutdown progress surface.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 24,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 340, maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Shutting down',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          message,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ExitObserver waits for async UI cleanup before window close exits.
class _ExitObserver extends WidgetsBindingObserver {
  /// Creates an app-exit observer.
  _ExitObserver({required this.onExitRequested});

  /// Callback invoked when the platform asks whether the app may exit.
  final Future<AppExitResponse> Function() onExitRequested;

  /// Handles desktop app-exit requests.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    return onExitRequested();
  }
}
