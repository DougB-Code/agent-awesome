/// Settings credential lookup and keyring editing widgets.
part of 'settings_panel.dart';

class _SettingsCredentialField extends StatefulWidget {
  const _SettingsCredentialField({
    required this.controller,
    required this.providerId,
    required this.reference,
    required this.onChanged,
  });

  final AgentAwesomeAppController controller;
  final String providerId;
  final String reference;
  final ValueChanged<String> onChanged;

  /// Creates state for an async masked credential lookup field.
  @override
  State<_SettingsCredentialField> createState() =>
      _SettingsCredentialFieldState();
}

class _SettingsCredentialFieldState extends State<_SettingsCredentialField> {
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
  void didUpdateWidget(covariant _SettingsCredentialField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) {
      _lookup = null;
      _loading = true;
      unawaited(_load());
    }
  }

  /// Builds a password-style API key field backed by the OS keyring.
  @override
  Widget build(BuildContext context) {
    final lookup = _lookup;
    final hasTypedSecret = _controller.text.isNotEmpty;
    final canReveal = hasTypedSecret || (lookup?.found ?? false);
    final copyableSecret = _copyableSecret(lookup, hasTypedSecret);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _controller,
        obscureText: hasTypedSecret && _obscureText,
        enabled: !_saving,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => unawaited(_saveSecret()),
        decoration: SettingsInputDecoration.field(
          context,
          label: 'API key',
          floatingLabelBehavior: lookup?.found ?? false
              ? FloatingLabelBehavior.always
              : FloatingLabelBehavior.auto,
          hintText: _hintText(lookup),
          suffixIcon: Wrap(
            spacing: 2,
            children: <Widget>[
              IconButton(
                onPressed: canReveal
                    ? () => setState(() => _obscureText = !_obscureText)
                    : null,
                tooltip: _obscureText ? 'Show API key' : 'Hide API key',
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              if (copyableSecret.isNotEmpty)
                IconButton(
                  onPressed: () => unawaited(_copySecret(copyableSecret)),
                  tooltip: 'Copy API key',
                  icon: const Icon(Icons.copy_outlined),
                ),
              IconButton(
                onPressed: hasTypedSecret && !_saving
                    ? () => unawaited(_saveSecret())
                    : null,
                tooltip: 'Save API key to OS keyring',
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
              ),
              IconButton(
                onPressed: widget.reference.trim().isNotEmpty && !_saving
                    ? () => unawaited(_deleteSecret())
                    : null,
                tooltip: 'Delete API key from OS keyring',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          suffixIconConstraints: BoxConstraints(
            minWidth: copyableSecret.isEmpty ? 144 : 192,
          ),
        ),
      ),
    );
  }

  /// Copies the revealed API key.
  Future<void> _copySecret(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
  }

  /// Saves the typed API key into the OS keyring.
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

  /// Deletes the configured API key from the OS keyring.
  Future<void> _deleteSecret() async {
    final reference = widget.reference.trim();
    if (reference.isEmpty) {
      return;
    }
    final confirmed = await _confirmSettingsDelete(
      context,
      label: 'API key credential',
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

  /// Returns the existing credential reference or generates a provider default.
  String _credentialReference() {
    final current = widget.reference.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return SettingsNameFactory.credentialNameFromProvider(widget.providerId);
  }

  /// Returns the field display text for missing, masked, or revealed secrets.
  String _hintText(CredentialLookup? lookup) {
    if (_loading) {
      return '';
    }
    if (lookup != null && lookup.found) {
      final value = _obscureText ? lookup.displayValue : lookup.secretValue;
      return '${lookup.source}: $value';
    }
    return 'Paste API key';
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
