/// First-run setup wizard shell and state coordination.
part of 'getting_started_wizard.dart';

enum _SetupStep {
  choose,
  apiKey,
  localModel;

  int get number {
    return switch (this) {
      _SetupStep.choose => 1,
      _SetupStep.apiKey || _SetupStep.localModel => 2,
    };
  }
}

/// GettingStartedWizard owns the interactive first-run setup workflow.
class GettingStartedWizard extends StatefulWidget {
  /// Creates the first-run setup flow.
  const GettingStartedWizard({
    super.key,
    required this.controller,
    required this.onComplete,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Marks onboarding completed.
  final Future<void> Function() onComplete;

  @override
  State<GettingStartedWizard> createState() => _GettingStartedWizardState();
}

class _GettingStartedWizardState extends State<GettingStartedWizard> {
  final TextEditingController _apiKeyController = TextEditingController();
  _SetupStep _step = _SetupStep.choose;
  String _providerId = onboardingCloudProviders.first.id;
  String _modelId = onboardingCloudProviders.first.models.first.id;
  String _localModelId = onboardingLocalModels.first.id;
  String _statusMessage = '';
  SystemCapabilitySnapshot _systemCapabilities =
      SystemCapabilitySnapshot.unknown();
  bool _revealApiKey = false;
  bool _busy = false;

  /// Starts asynchronous system checks used by local model setup.
  @override
  void initState() {
    super.initState();
    unawaited(_loadSystemCapabilities());
  }

  /// Cleans up setup form controllers.
  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  /// Loads memory and disk facts without blocking initial rendering.
  Future<void> _loadSystemCapabilities() async {
    final snapshot = await widget.controller.readSystemCapabilities();
    if (!mounted) {
      return;
    }
    setState(() => _systemCapabilities = snapshot);
  }

  /// Builds the full first-run setup page.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey<String>('getting-started-wizard'),
      padding: const EdgeInsets.fromLTRB(36, 34, 36, 34),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _SetupEyebrow('FIRST SETUP'),
              const SizedBox(height: 20),
              Text(_title, style: Theme.of(context).textTheme.displayLarge),
              const SizedBox(height: 44),
              _SetupFrame(
                child: Column(
                  children: <Widget>[
                    _SetupStepper(step: _step),
                    const SizedBox(height: 36),
                    _buildBody(),
                    const SizedBox(height: 28),
                    _SetupFooter(message: _footerMessage),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the body for the active setup step.
  Widget _buildBody() {
    return switch (_step) {
      _SetupStep.choose => _ChooseSetupMethod(
        onApiKey: () => setState(() => _step = _SetupStep.apiKey),
        onLocalModel: () => setState(() => _step = _SetupStep.localModel),
      ),
      _SetupStep.apiKey => _ApiKeySetup(
        providerId: _providerId,
        modelId: _modelId,
        apiKeyController: _apiKeyController,
        revealApiKey: _revealApiKey,
        busy: _busy,
        statusMessage: _statusMessage,
        onProviderChanged: _selectProvider,
        onModelChanged: (modelId) => setState(() => _modelId = modelId),
        onRevealChanged: () => setState(() => _revealApiKey = !_revealApiKey),
        onPaste: _pasteApiKey,
        onBack: () => setState(() => _step = _SetupStep.choose),
        onVerify: _verifyApiKey,
        onUseLocal: () => setState(() => _step = _SetupStep.localModel),
      ),
      _SetupStep.localModel => _LocalModelSetup(
        selectedModelId: _localModelId,
        systemCapabilities: _systemCapabilities,
        busy: _busy,
        statusMessage: _statusMessage,
        onModelChanged: (modelId) => setState(() => _localModelId = modelId),
        onBack: () => setState(() => _step = _SetupStep.choose),
        onUseApiKey: () => setState(() => _step = _SetupStep.apiKey),
        onContinue: _configureLocalModel,
      ),
    };
  }

  String get _title {
    return switch (_step) {
      _SetupStep.choose => 'Connect your model',
      _SetupStep.apiKey => 'Add your API key',
      _SetupStep.localModel => 'Run a local model',
    };
  }

  String get _footerMessage {
    return switch (_step) {
      _SetupStep.choose => 'You can switch later in Settings.',
      _SetupStep.apiKey =>
        'Your API key is encrypted and stored securely on this device.',
      _SetupStep.localModel =>
        'Local model traffic stays on this machine when your endpoint is local.',
    };
  }

  /// Selects a provider and resets the model to that provider's default.
  void _selectProvider(String providerId) {
    final provider = onboardingCloudProviderById(providerId);
    setState(() {
      _providerId = provider.id;
      _modelId = provider.models.first.id;
      _statusMessage = '';
    });
  }

  /// Pastes an API key from the clipboard into the setup field.
  Future<void> _pasteApiKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _apiKeyController.text = text;
      _statusMessage = '';
    });
  }

  /// Stores and activates the selected cloud model.
  Future<void> _verifyApiKey() async {
    setState(() {
      _busy = true;
      _statusMessage = '';
    });
    final result = await widget.controller.configureOnboardingCloudModel(
      providerId: _providerId,
      modelId: _modelId,
      apiKey: _apiKeyController.text,
    );
    if (!mounted) {
      return;
    }
    if (!result.success) {
      setState(() {
        _busy = false;
        _statusMessage = result.message;
      });
      return;
    }
    _apiKeyController.clear();
    setState(() {
      _busy = false;
      _statusMessage = '';
    });
    await widget.onComplete();
  }

  /// Activates the selected local model endpoint.
  Future<void> _configureLocalModel() async {
    setState(() {
      _busy = true;
      _statusMessage = '';
    });
    final result = await widget.controller.configureOnboardingLocalModel(
      modelId: _localModelId,
      onProgress: (progress) {
        if (!mounted) {
          return;
        }
        setState(() {
          _statusMessage = progress.fraction == null
              ? progress.message
              : '${progress.message} (${(progress.fraction! * 100).toStringAsFixed(0)}%)';
        });
      },
    );
    if (!mounted) {
      return;
    }
    if (!result.success) {
      setState(() {
        _busy = false;
        _statusMessage = result.message;
      });
      return;
    }
    setState(() {
      _busy = false;
      _statusMessage = '';
    });
    await widget.onComplete();
  }
}
