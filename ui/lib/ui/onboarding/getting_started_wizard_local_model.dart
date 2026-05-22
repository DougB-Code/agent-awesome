/// First-run local-model setup widgets.
part of 'getting_started_wizard.dart';

class _LocalModelSetup extends StatelessWidget {
  const _LocalModelSetup({
    required this.selectedModelId,
    required this.systemCapabilities,
    required this.busy,
    required this.installed,
    required this.statusMessage,
    required this.onModelChanged,
    required this.onBack,
    required this.onUseApiKey,
    required this.onContinue,
  });

  final String selectedModelId;
  final SystemCapabilitySnapshot systemCapabilities;
  final bool busy;
  final bool installed;
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
                    value: _formatCpuThreads(systemCapabilities.cpuThreads),
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
          ...onboardingLocalModels.map((model) {
            final descriptor = onboardingLocalModelDescriptor(model.id);
            return Padding(
              padding: EdgeInsets.only(
                bottom: model.id == onboardingLocalModels.last.id ? 0 : 12,
              ),
              child: _LocalModelCard(
                model: model,
                descriptor: descriptor,
                selected: model.id == selectedModel.id,
                recommended: model.id == onboardingLocalModels.first.id,
                onSelected: () => onModelChanged(model.id),
              ),
            );
          }),
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
                  label: _continueLabel(selectedDescriptor),
                  icon: installed || !selectedDescriptor.usesManagedDownload
                      ? Icons.arrow_forward
                      : Icons.download,
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

  /// Returns primary action copy for fresh and already-installed local models.
  String _continueLabel(LocalModelDescriptor descriptor) {
    if (busy) {
      if (installed) {
        return 'Saving local model';
      }
      return descriptor.usesManagedDownload
          ? 'Downloading local model'
          : 'Preparing local model';
    }
    if (installed) {
      return 'Continue';
    }
    return descriptor.usesManagedDownload
        ? 'Download and continue'
        : 'Use llama.cpp';
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
        border: Border.all(color: AgentAwesomeColors.border),
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
                    color: AgentAwesomeColors.muted,
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
            color: selected
                ? AgentAwesomeColors.green
                : AgentAwesomeColors.border,
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
              color: selected
                  ? AgentAwesomeColors.green
                  : AgentAwesomeColors.muted,
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
                      color: AgentAwesomeColors.muted,
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
                        icon: descriptor.usesManagedDownload
                            ? Icons.file_download_outlined
                            : Icons.link,
                        label: _localModelSourceLabel(descriptor),
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
