/// Chat composer input widget.
part of 'agent_awesome_shell.dart';

class _ChatComposer extends StatefulWidget {
  const _ChatComposer({
    required this.controller,
    required this.sending,
    required this.modelChoices,
    required this.selectedModelRef,
    required this.onModelSelected,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool sending;
  final List<ModelConfigChoice> modelChoices;
  final String selectedModelRef;
  final ValueChanged<String> onModelSelected;
  final VoidCallback onSubmit;

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

/// _ChatComposerState owns field focus so the prompt can clear on focus.
class _ChatComposerState extends State<_ChatComposer> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  /// Starts listening for focus changes on the chat composer.
  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  /// Releases the field focus resource.
  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  /// Updates placeholder visibility when the composer focus changes.
  void _handleFocusChanged() {
    if (_focused == _focusNode.hasFocus) {
      return;
    }
    setState(() {
      _focused = _focusNode.hasFocus;
    });
  }

  /// Builds the sticky same-thread composer for the chat timeline.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            return Container(
              key: const ValueKey<String>('chat-thread-composer-frame'),
              constraints: const BoxConstraints(minHeight: 58),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 16,
                vertical: compact ? 10 : 0,
              ),
              decoration: BoxDecoration(
                color: colors.field,
                border: Border.all(
                  color: colors.border,
                  width: AgentAwesomeStrokeTokens.borderWidth,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: compact
                  ? _buildCompactComposer(context)
                  : _buildWideComposer(context),
            );
          },
        ),
      ),
    );
  }

  /// Builds the standard single-row composer for roomy chat panes.
  Widget _buildWideComposer(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Icon(Icons.chat_bubble_outline, color: colors.muted),
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildTextField(context)),
        const SizedBox(width: 12),
        if (widget.modelChoices.length > 1) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _buildModelMenu(),
          ),
          const SizedBox(width: 8),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildSendButton(context),
        ),
      ],
    );
  }

  /// Builds a two-row composer for narrow auxiliary chat panes.
  Widget _buildCompactComposer(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Icon(Icons.chat_bubble_outline, color: colors.muted),
            ),
            const SizedBox(width: 10),
            Expanded(child: _buildTextField(context)),
          ],
        ),
        if (widget.modelChoices.length > 1) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const SizedBox(width: 34),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildModelMenu(),
                ),
              ),
              const SizedBox(width: 8),
              _buildSendButton(context),
            ],
          ),
        ] else ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _buildSendButton(context),
          ),
        ],
      ],
    );
  }

  /// Builds the shared chat text field.
  Widget _buildTextField(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return TextField(
      key: const ValueKey<String>('chat-thread-composer'),
      controller: widget.controller,
      enabled: !widget.sending,
      focusNode: _focusNode,
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.send,
      style: TextStyle(color: colors.ink),
      decoration: InputDecoration(
        filled: false,
        fillColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        hintText: _focused ? null : 'Message Agent Awesome in this chat...',
        hintStyle: TextStyle(color: colors.muted),
      ),
      onSubmitted: (_) {
        if (!widget.sending) {
          widget.onSubmit();
        }
      },
    );
  }

  /// Builds the shared chat model picker.
  Widget _buildModelMenu() {
    return _ChatModelMenuButton(
      choices: widget.modelChoices,
      selectedRef: widget.selectedModelRef,
      sending: widget.sending,
      onSelected: widget.onModelSelected,
    );
  }

  /// Builds the shared send button.
  Widget _buildSendButton(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return IconButton.filled(
      key: const ValueKey<String>('chat-thread-send-button'),
      style: IconButton.styleFrom(
        backgroundColor: colors.green,
        foregroundColor: Colors.white,
        fixedSize: const Size(42, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: widget.sending ? null : widget.onSubmit,
      icon: Icon(widget.sending ? Icons.hourglass_top : Icons.arrow_upward),
      tooltip: 'Send message',
    );
  }
}

/// _ChatModelMenuButton lets a chat turn choose one configured runtime model.
class _ChatModelMenuButton extends StatelessWidget {
  /// Creates the per-message chat model selector.
  const _ChatModelMenuButton({
    required this.choices,
    required this.selectedRef,
    required this.sending,
    required this.onSelected,
  });

  /// Model choices available through the active agent runtime topology.
  final List<ModelConfigChoice> choices;

  /// Provider:model ref selected for the next message.
  final String selectedRef;

  /// Whether chat input is currently locked by an active run.
  final bool sending;

  /// Called when the user chooses a different model for future messages.
  final ValueChanged<String> onSelected;

  /// Builds the compact model picker beside the send button.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final selected = _selectedChoice();
    return PopupMenuButton<String>(
      key: const ValueKey<String>('chat-thread-model-picker'),
      enabled: !sending,
      tooltip: 'Chat model',
      color: colors.surface,
      onSelected: onSelected,
      itemBuilder: (context) {
        return <PopupMenuEntry<String>>[
          for (final choice in choices)
            PopupMenuItem<String>(
              value: choice.ref,
              child: SizedBox(
                width: 260,
                child: Row(
                  children: <Widget>[
                    Icon(
                      choice.ref == selectedRef
                          ? Icons.check
                          : Icons.psychology_alt_outlined,
                      size: 18,
                      color: choice.ref == selectedRef
                          ? colors.green
                          : colors.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            choice.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (_choiceModelName(choice).isNotEmpty)
                            Text(
                              _choiceModelName(choice),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ];
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 164),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.psychology_alt_outlined, size: 18, color: colors.muted),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                selected?.modelId ?? 'Model',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 18, color: colors.muted),
          ],
        ),
      ),
    );
  }

  /// Returns the currently selected model choice.
  ModelConfigChoice? _selectedChoice() {
    for (final choice in choices) {
      if (choice.ref == selectedRef) {
        return choice;
      }
    }
    return choices.isEmpty ? null : choices.first;
  }

  /// Returns a secondary provider-native model label when useful.
  String _choiceModelName(ModelConfigChoice choice) {
    final modelName = choice.modelName.trim();
    if (modelName.isEmpty || modelName == choice.modelId) {
      return '';
    }
    return modelName;
  }
}
