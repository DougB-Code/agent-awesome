/// Settings secret lookup and password-vault editing widgets.
part of 'settings_panel.dart';

class SettingsSecretStorageField extends StatefulWidget {
  /// Creates a reusable password-style field backed by credentials.
  const SettingsSecretStorageField({
    required this.controller,
    required this.defaultReference,
    required this.reference,
    required this.onChanged,
    this.label = 'Secret',
    this.secretLabel = 'secret',
    this.pasteHint = 'Paste secret',
  });

  /// Shared app controller used for credential lookup and mutation.
  final AgentAwesomeAppController controller;

  /// Reference generated when a secret is saved without an existing reference.
  final String defaultReference;

  /// Current credential reference, env var, or password-vault name.
  final String reference;

  /// Called when saving creates or reuses a credential reference.
  final ValueChanged<String> onChanged;

  /// Field label shown beside the editable secret input.
  final String label;

  /// Human label used in copy/save/delete tooltips.
  final String secretLabel;

  /// Hint shown before a secret has been typed or resolved.
  final String pasteHint;

  /// Creates state for an async masked credential lookup field.
  @override
  State<SettingsSecretStorageField> createState() =>
      _SettingsSecretStorageFieldState();
}

class _SettingsSecretStorageFieldState
    extends State<SettingsSecretStorageField> {
  final TextEditingController _controller = TextEditingController();
  bool _obscureText = true;
  CredentialLookup? _lookup;
  bool _loading = true;
  bool _saving = false;

  /// Loads the initial credential display state.
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Cleans up secret input state.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Reloads when the configured credential reference changes.
  @override
  void didUpdateWidget(covariant SettingsSecretStorageField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) {
      _lookup = null;
      _loading = true;
      unawaited(_load());
    }
  }

  /// Builds a password-style field backed by the OS Password Vault.
  @override
  Widget build(BuildContext context) {
    final lookup = _lookup;
    final hasTypedSecret = _controller.text.isNotEmpty;
    final canReveal = hasTypedSecret || (lookup?.found ?? false);
    final copyableSecret = _copyableSecret(lookup, hasTypedSecret);
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.fieldGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_credentialSourceLabel(lookup).isNotEmpty) ...<Widget>[
            PanelBadge(label: _credentialSourceLabel(lookup)),
            const SizedBox(height: SettingsFormMetrics.compactGap),
          ],
          PanelLabeledFormControl(
            label: widget.label,
            child: TextField(
              controller: _controller,
              obscureText: hasTypedSecret && _obscureText,
              enabled: !_saving,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => unawaited(_saveSecret()),
              decoration: SettingsInputDecoration.field(
                context,
                label: widget.label,
                floatingLabelBehavior: lookup?.found ?? false
                    ? FloatingLabelBehavior.always
                    : FloatingLabelBehavior.auto,
                hintText: _hintText(lookup),
                suffixIcon: Wrap(
                  spacing: 2,
                  children: <Widget>[
                    PanelInlineIconButton(
                      icon: _obscureText
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      tooltip: _obscureText
                          ? 'Show ${widget.secretLabel}'
                          : 'Hide ${widget.secretLabel}',
                      onPressed: canReveal
                          ? () => setState(() => _obscureText = !_obscureText)
                          : null,
                    ),
                    if (copyableSecret.isNotEmpty)
                      PanelInlineIconButton(
                        icon: Icons.copy_outlined,
                        tooltip: 'Copy ${widget.secretLabel}',
                        onPressed: () => unawaited(_copySecret(copyableSecret)),
                      ),
                    PanelInlineIconButton(
                      icon: Icons.save_outlined,
                      tooltip:
                          'Save ${widget.secretLabel} to OS Password Vault',
                      loading: _saving,
                      onPressed: hasTypedSecret && !_saving
                          ? () => unawaited(_saveSecret())
                          : null,
                    ),
                    PanelInlineIconButton(
                      icon: Icons.delete_outline,
                      tooltip:
                          'Delete ${widget.secretLabel} from OS Password Vault',
                      onPressed: widget.reference.trim().isNotEmpty && !_saving
                          ? () => unawaited(_deleteSecret())
                          : null,
                    ),
                  ],
                ),
                suffixIconConstraints: BoxConstraints(
                  minWidth: copyableSecret.isEmpty ? 144 : 192,
                ),
              ),
            ),
          ),
          if (lookup?.source == 'env')
            const SettingsFormNote(
              icon: Icons.lock_outline,
              text:
                  'Environment variables are less private than the OS Password Vault on shared machines. Save the key to the OS Password Vault when available.',
            ),
        ],
      ),
    );
  }

  /// Copies the revealed secret.
  Future<void> _copySecret(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
  }

  /// Saves the typed secret into the OS Password Vault.
  Future<void> _saveSecret() async {
    final secret = _controller.text.trim();
    if (secret.isEmpty) {
      return;
    }
    final reference = _credentialReference();
    setState(() {
      _saving = true;
    });
    final result = await widget.controller.storeCredential(
      reference: reference,
      secret: secret,
    );
    if (!mounted) {
      return;
    }
    if (!result.success) {
      setState(() {
        _saving = false;
      });
      return;
    }
    _controller.clear();
    widget.onChanged(reference);
    final lookup = await widget.controller.lookupCredential(reference);
    if (!mounted) {
      return;
    }
    setState(() {
      _lookup = lookup;
      _loading = false;
      _saving = false;
      _obscureText = true;
    });
  }

  /// Deletes the configured secret from the OS Password Vault.
  Future<void> _deleteSecret() async {
    final reference = widget.reference.trim();
    if (reference.isEmpty) {
      return;
    }
    final confirmed = await _confirmSettingsDelete(
      context,
      label: '${widget.secretLabel} credential',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _saving = true;
    });
    await widget.controller.deleteCredential(reference);
    final lookup = await widget.controller.lookupCredential(reference);
    if (!mounted) {
      return;
    }
    setState(() {
      _lookup = lookup;
      _loading = false;
      _saving = false;
    });
  }

  /// Returns the existing credential reference or the configured default.
  String _credentialReference() {
    final current = widget.reference.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return widget.defaultReference.trim();
  }

  /// Returns the field display text for missing, masked, or revealed secrets.
  String _hintText(CredentialLookup? lookup) {
    if (_loading) {
      return '';
    }
    if (lookup != null && lookup.found) {
      return _obscureText ? lookup.displayValue : lookup.secretValue;
    }
    return widget.pasteHint;
  }

  /// Returns the credential source badge label.
  String _credentialSourceLabel(CredentialLookup? lookup) {
    if (lookup == null || !lookup.found) {
      return '';
    }
    return switch (lookup.source) {
      'keyring' => _platformPasswordVaultLabel(),
      'env' => 'Environment variable',
      _ => lookup.source,
    };
  }

  /// Returns an intuitive platform-specific password vault label.
  String _platformPasswordVaultLabel() {
    return switch (Platform.operatingSystem) {
      'linux' => 'Linux Password Vault',
      'macos' => 'Mac Password Vault',
      'windows' => 'Windows Password Vault',
      _ => 'OS Password Vault',
    };
  }

  /// Returns the current secret when an API key is present.
  String _copyableSecret(CredentialLookup? lookup, bool hasTypedSecret) {
    if (hasTypedSecret) {
      return _controller.text;
    }
    if (lookup != null && lookup.found) {
      return lookup.secretValue;
    }
    return '';
  }

  Future<void> _load() async {
    final lookup = await widget.controller.lookupCredential(widget.reference);
    if (!mounted) {
      return;
    }
    setState(() {
      _lookup = lookup;
      _loading = false;
    });
  }
}
