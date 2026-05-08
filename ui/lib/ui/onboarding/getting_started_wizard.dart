/// Renders the first-run model setup flow for the Agent Awesome desktop app.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_controller.dart';
import '../../app/local_model_runtime.dart';
import '../../app/onboarding_model_setup.dart';
import '../../app/system_capabilities.dart';
import '../../app/theme.dart';

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
  final AuroraAppController controller;

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

class _SetupFrame extends StatelessWidget {
  const _SetupFrame({required this.child});

  final Widget child;

  /// Builds the bordered setup frame.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(36, 36, 36, 24),
      decoration: BoxDecoration(
        color: AuroraColors.surface,
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0a453421),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SetupStepper extends StatelessWidget {
  const _SetupStepper({required this.step});

  final _SetupStep step;

  /// Builds the four-step setup progress indicator.
  @override
  Widget build(BuildContext context) {
    final current = step.number;
    const labels = <String>[
      'Choose setup method',
      'Connect model',
      'Verify',
      'Start chat',
    ];
    return Row(
      children: <Widget>[
        for (var index = 0; index < labels.length; index++) ...<Widget>[
          Expanded(
            child: _StepperItem(
              number: index + 1,
              label: labels[index],
              active: current == index + 1,
              complete: current > index + 1,
            ),
          ),
          if (index < labels.length - 1)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.only(bottom: 28),
                color: current > index + 1
                    ? AuroraColors.green
                    : AuroraColors.border,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepperItem extends StatelessWidget {
  const _StepperItem({
    required this.number,
    required this.label,
    required this.active,
    required this.complete,
  });

  final int number;
  final String label;
  final bool active;
  final bool complete;

  /// Builds one step marker.
  @override
  Widget build(BuildContext context) {
    final color = active || complete ? AuroraColors.green : AuroraColors.muted;
    return Column(
      children: <Widget>[
        Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active || complete ? AuroraColors.green : Colors.transparent,
            border: Border.all(
              color: active || complete
                  ? AuroraColors.green
                  : AuroraColors.border,
            ),
          ),
          child: Center(
            child: complete
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    number.toString(),
                    style: TextStyle(
                      color: active ? Colors.white : AuroraColors.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ChooseSetupMethod extends StatelessWidget {
  const _ChooseSetupMethod({
    required this.onApiKey,
    required this.onLocalModel,
  });

  final VoidCallback onApiKey;
  final VoidCallback onLocalModel;

  /// Builds the first setup method choice screen.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 36,
          runSpacing: 20,
          children: <Widget>[
            _SetupChoiceCard(
              icon: Icons.cloud_outlined,
              title: 'Use API key',
              detail:
                  'Connect OpenAI, Anthropic, Google, or another supported provider.',
              buttonLabel: 'Connect provider',
              filled: true,
              onPressed: onApiKey,
            ),
            _SetupChoiceCard(
              icon: Icons.desktop_windows_outlined,
              title: 'Run local model',
              detail:
                  "Use a local model endpoint if you don't have an API key.",
              buttonLabel: 'Use local model',
              filled: false,
              onPressed: onLocalModel,
            ),
          ],
        ),
      ],
    );
  }
}

class _SetupChoiceCard extends StatelessWidget {
  const _SetupChoiceCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.buttonLabel,
    required this.filled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String buttonLabel;
  final bool filled;
  final VoidCallback onPressed;

  /// Builds one setup method card.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 430,
      height: 300,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AuroraColors.surface,
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _LargeCircleIcon(icon: icon),
          const SizedBox(width: 26),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AuroraColors.muted,
                    fontSize: 16,
                    height: 1.35,
                  ),
                ),
                const Spacer(),
                _SetupButton(
                  label: buttonLabel,
                  icon: Icons.arrow_forward,
                  filled: filled,
                  onPressed: onPressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiKeySetup extends StatelessWidget {
  const _ApiKeySetup({
    required this.providerId,
    required this.modelId,
    required this.apiKeyController,
    required this.revealApiKey,
    required this.busy,
    required this.statusMessage,
    required this.onProviderChanged,
    required this.onModelChanged,
    required this.onRevealChanged,
    required this.onPaste,
    required this.onBack,
    required this.onVerify,
    required this.onUseLocal,
  });

  final String providerId;
  final String modelId;
  final TextEditingController apiKeyController;
  final bool revealApiKey;
  final bool busy;
  final String statusMessage;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onModelChanged;
  final VoidCallback onRevealChanged;
  final Future<void> Function() onPaste;
  final VoidCallback onBack;
  final Future<void> Function() onVerify;
  final VoidCallback onUseLocal;

  /// Builds the API-key setup form.
  @override
  Widget build(BuildContext context) {
    final provider = onboardingCloudProviderById(providerId);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final providerField = _SetupDropdown<String>(
                label: 'Provider',
                value: provider.id,
                items: <DropdownMenuItem<String>>[
                  for (final option in onboardingCloudProviders)
                    DropdownMenuItem<String>(
                      value: option.id,
                      child: Text(option.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onProviderChanged(value);
                  }
                },
              );
              final modelField = _SetupDropdown<String>(
                label: 'Model',
                value: provider.modelForId(modelId).id,
                items: <DropdownMenuItem<String>>[
                  for (final model in provider.models)
                    DropdownMenuItem<String>(
                      value: model.id,
                      child: Text(model.model),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onModelChanged(value);
                  }
                },
              );
              if (constraints.maxWidth < 680) {
                return Column(
                  children: <Widget>[
                    providerField,
                    const SizedBox(height: 16),
                    modelField,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: providerField),
                  const SizedBox(width: 28),
                  Expanded(child: modelField),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey<String>('onboarding-api-key'),
            controller: apiKeyController,
            enabled: !busy,
            obscureText: !revealApiKey,
            decoration: _setupInputDecoration('API key').copyWith(
              suffixIcon: Wrap(
                spacing: 2,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: busy ? null : () => unawaited(onPaste()),
                    icon: const Icon(Icons.content_paste_outlined, size: 18),
                    label: const Text('Paste'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : onRevealChanged,
                    icon: Icon(
                      revealApiKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    label: Text(revealApiKey ? 'Hide' : 'Reveal'),
                  ),
                ],
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 190),
            ),
            onSubmitted: (_) => unawaited(onVerify()),
          ),
          const SizedBox(height: 10),
          const _InlineNote(
            icon: Icons.lock_outline,
            text:
                'Your API key is encrypted and stored securely on this device.',
          ),
          if (statusMessage.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            _StatusBanner(message: statusMessage),
          ],
          const SizedBox(height: 30),
          Row(
            children: <Widget>[
              _SetupButton(
                label: 'Back',
                icon: Icons.arrow_back,
                filled: false,
                onPressed: busy ? null : onBack,
                iconBefore: true,
              ),
              const Spacer(),
              SizedBox(
                width: 360,
                child: _SetupButton(
                  label: busy ? 'Saving connection' : 'Verify connection',
                  icon: busy ? Icons.sync : Icons.check_circle_outline,
                  filled: true,
                  onPressed: busy ? null : () => unawaited(onVerify()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: AuroraColors.border),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const _InlineNote(
                icon: Icons.help_outline,
                text: 'Need a key? Open provider docs.',
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: busy ? null : onUseLocal,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Use local model instead'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocalModelSetup extends StatelessWidget {
  const _LocalModelSetup({
    required this.selectedModelId,
    required this.systemCapabilities,
    required this.busy,
    required this.statusMessage,
    required this.onModelChanged,
    required this.onBack,
    required this.onUseApiKey,
    required this.onContinue,
  });

  final String selectedModelId;
  final SystemCapabilitySnapshot systemCapabilities;
  final bool busy;
  final String statusMessage;
  final ValueChanged<String> onModelChanged;
  final VoidCallback onBack;
  final VoidCallback onUseApiKey;
  final Future<void> Function() onContinue;

  /// Builds the local model setup screen.
  @override
  Widget build(BuildContext context) {
    final selectedModel = onboardingLocalModelById(selectedModelId);
    final selectedDescriptor = onboardingLocalModelDescriptor(selectedModel.id);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1040),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Align(
            alignment: Alignment.centerLeft,
            child: _SectionHeading(
              title: 'System check',
              subtitle: "Here's what we found on your machine.",
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 42) / 4;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: <Widget>[
                  _SystemCheckCard(
                    width: cardWidth,
                    icon: Icons.memory_outlined,
                    title: 'CPU',
                    value: '${systemCapabilities.cpuThreads} cores',
                    detail: 'Detected processor threads',
                  ),
                  _SystemCheckCard(
                    width: cardWidth,
                    icon: Icons.view_in_ar_outlined,
                    title: 'Memory',
                    value: _formatOptionalBytes(systemCapabilities.memoryBytes),
                    detail: _memoryRecommendation(
                      systemCapabilities.memoryBytes,
                    ),
                  ),
                  _SystemCheckCard(
                    width: cardWidth,
                    icon: Icons.storage_outlined,
                    title: 'Disk space',
                    value: _formatOptionalBytes(systemCapabilities.diskBytes),
                    detail: _diskRecommendation(systemCapabilities.diskBytes),
                  ),
                  _SystemCheckCard(
                    width: cardWidth,
                    icon: Icons.developer_board_outlined,
                    title: 'GPU',
                    value: 'None detected',
                    detail: 'CPU mode may be slower',
                    warning: true,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const _WarningBanner(
            message:
                'No GPU detected or selected. Local models may run slowly on CPU.',
          ),
          const SizedBox(height: 26),
          const _SectionHeading(
            title: 'Select a local model',
            subtitle:
                'Choose a model endpoint preset. You can change this later in Settings.',
          ),
          const SizedBox(height: 14),
          _LocalModelCard(
            model: selectedModel,
            descriptor: selectedDescriptor,
            selected: true,
            recommended: true,
            onSelected: () => onModelChanged(selectedModel.id),
          ),
          if (statusMessage.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            _StatusBanner(message: statusMessage),
          ],
          const SizedBox(height: 26),
          Row(
            children: <Widget>[
              _SetupButton(
                label: 'Back',
                icon: Icons.arrow_back,
                filled: false,
                onPressed: busy ? null : onBack,
                iconBefore: true,
              ),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : onUseApiKey,
                child: const Text('Use API key instead'),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 300,
                child: _SetupButton(
                  label: busy ? 'Saving local model' : 'Download and continue',
                  icon: Icons.download,
                  filled: true,
                  onPressed: busy ? null : () => unawaited(onContinue()),
                  iconBefore: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SystemCheckCard extends StatelessWidget {
  const _SystemCheckCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    this.warning = false,
  });

  final double width;
  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final bool warning;

  /// Builds one local capability card.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 196,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          _LargeCircleIcon(icon: icon, size: 52, warning: warning),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(value),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AuroraColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalModelCard extends StatelessWidget {
  const _LocalModelCard({
    required this.model,
    required this.descriptor,
    required this.selected,
    required this.recommended,
    required this.onSelected,
  });

  final OnboardingModelOption model;
  final LocalModelDescriptor descriptor;
  final bool selected;
  final bool recommended;
  final VoidCallback onSelected;

  /// Builds the selected local model and source disclosure card.
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onSelected,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? AuroraColors.green : AuroraColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AuroraColors.green : AuroraColors.muted,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                            model.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          if (recommended) const _SmallBadge('Recommended'),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    model.detail,
                    style: const TextStyle(
                      color: AuroraColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _ModelMetadataChip(
                        icon: Icons.file_download_outlined,
                        label:
                            '${descriptor.fileName} (${_formatBytes(descriptor.expectedBytes)})',
                      ),
                      _ModelMetadataChip(
                        icon: Icons.verified_outlined,
                        label: descriptor.license,
                      ),
                      _ModelMetadataChip(
                        icon: Icons.inventory_2_outlined,
                        label: descriptor.repository,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => unawaited(_openModelSite(context, descriptor)),
              icon: const Icon(Icons.open_in_new),
              label: const Text('View source'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelMetadataChip extends StatelessWidget {
  const _ModelMetadataChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  /// Builds one compact local model metadata label.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: AuroraColors.muted),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: AuroraColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _SetupDropdown<T> extends StatelessWidget {
  const _SetupDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  /// Builds a setup dropdown field.
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      isExpanded: true,
      onChanged: onChanged,
      decoration: _setupInputDecoration(label),
    );
  }
}

class _SetupButton extends StatelessWidget {
  const _SetupButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onPressed,
    this.iconBefore = false,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onPressed;
  final bool iconBefore;

  /// Builds a rounded setup action button.
  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (iconBefore) Icon(icon, size: 20),
      Text(label),
      if (!iconBefore) Icon(icon, size: 20),
    ];
    final style = filled
        ? FilledButton.styleFrom(
            backgroundColor: AuroraColors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: AuroraColors.green,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
            side: const BorderSide(color: AuroraColors.green),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          );
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (var index = 0; index < children.length; index++) ...<Widget>[
            children[index],
            if (index < children.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
    return filled
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

class _SetupFooter extends StatelessWidget {
  const _SetupFooter({required this.message});

  final String message;

  /// Builds the setup footer note.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Divider(color: AuroraColors.border),
        const SizedBox(height: 16),
        _InlineNote(icon: Icons.lock_outline, text: message),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  /// Builds a setup subsection heading.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: AuroraColors.muted)),
      ],
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  /// Builds a small icon note.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18, color: AuroraColors.muted),
        const SizedBox(width: 10),
        Flexible(
          child: Text(text, style: const TextStyle(color: AuroraColors.muted)),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});

  final String message;

  /// Builds a setup error/status banner.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xfffff2e8),
        border: Border.all(color: const Color(0xffffb66b)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_outlined, color: Color(0xffc85f0a)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xff9a4700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  /// Builds a local model warning banner.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xfffff7ed),
        border: Border.all(color: const Color(0xffffbd78)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_outlined, color: Color(0xffdb6b00)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xffbf5c00)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the selected model source page in the user's default browser.
Future<void> _openModelSite(
  BuildContext context,
  LocalModelDescriptor model,
) async {
  final url = Uri.parse('https://huggingface.co/${model.repository}');
  final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (opened || !context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Could not open ${url.toString()}')));
}

/// Formats byte counts for setup disclosure text.
String _formatBytes(int bytes) {
  const gib = 1024 * 1024 * 1024;
  const mib = 1024 * 1024;
  if (bytes >= gib) {
    return '${(bytes / gib).toStringAsFixed(1)} GB';
  }
  if (bytes >= mib) {
    return '${(bytes / mib).toStringAsFixed(0)} MB';
  }
  return '$bytes bytes';
}

/// Formats optional byte counts for system-check cards.
String _formatOptionalBytes(int? bytes) {
  if (bytes == null) {
    return 'Unknown';
  }
  return _formatBytes(bytes);
}

/// Returns a local model memory recommendation for the detected system.
String _memoryRecommendation(int? bytes) {
  if (bytes == null) {
    return 'Could not detect memory';
  }
  const eightGiB = 8 * 1024 * 1024 * 1024;
  const sixteenGiB = 16 * 1024 * 1024 * 1024;
  if (bytes < eightGiB) {
    return 'Use cloud or a smaller model';
  }
  if (bytes < sixteenGiB) {
    return 'Gemma 4 E2B should fit';
  }
  return 'Enough for local models';
}

/// Returns a model storage recommendation for the detected app data volume.
String _diskRecommendation(int? bytes) {
  if (bytes == null) {
    return 'Could not detect disk space';
  }
  final modelBytes = gemma4E2BLocalModel.expectedBytes;
  if (bytes < modelBytes * 2) {
    return 'Free space before download';
  }
  return 'Enough for Gemma 4 E2B';
}

class _LargeCircleIcon extends StatelessWidget {
  const _LargeCircleIcon({
    required this.icon,
    this.size = 72,
    this.warning = false,
  });

  final IconData icon;
  final double size;
  final bool warning;

  /// Builds a round icon marker.
  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: warning
            ? const Color(0xffffead6)
            : AuroraColors.greenSoft.withValues(alpha: 0.82),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: warning ? const Color(0xffb85d00) : AuroraColors.green,
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.label);

  final String label;

  /// Builds a small recommendation badge.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AuroraColors.greenSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AuroraColors.green,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SetupEyebrow extends StatelessWidget {
  const _SetupEyebrow(this.text);

  final String text;

  /// Builds the setup eyebrow label.
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AuroraColors.coral,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 6,
      ),
    );
  }
}

/// Returns the shared first-run setup input decoration.
InputDecoration _setupInputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AuroraColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AuroraColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AuroraColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AuroraColors.green),
    ),
  );
}
