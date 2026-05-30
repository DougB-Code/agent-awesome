/// First-run cloud API-key setup widgets.
part of 'getting_started_wizard.dart';

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
            decoration: _setupInputDecoration(context, 'API key').copyWith(
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
          const Divider(color: AgentAwesomeColors.border),
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
