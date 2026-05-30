/// Shared form fields for command-panel detail editors.
part of 'panels.dart';

/// PanelFormDecoration centralizes command-panel form field chrome.
abstract final class PanelFormDecoration {
  /// Creates the standard command-panel input decoration.
  static InputDecoration field(
    BuildContext context, {
    required String label,
    String? hintText,
    Widget? suffixIcon,
    FloatingLabelBehavior floatingLabelBehavior = FloatingLabelBehavior.auto,
    bool multiline = false,
  }) {
    final colors = context.agentAwesomeColors;
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: colors.muted),
      floatingLabelBehavior: floatingLabelBehavior,
      filled: true,
      fillColor: colors.field,
      suffixIcon: suffixIcon,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: multiline ? 12 : 8,
      ),
      border: _border(colors.border),
      enabledBorder: _border(colors.border),
      disabledBorder: _border(colors.border),
      focusedBorder: _border(colors.searchBorder),
    );
  }

  /// Builds one shared outlined border.
  static OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: color,
        width: AgentAwesomeStrokeTokens.borderWidth,
      ),
    );
  }
}

/// PanelFormMetrics defines shared command-panel form spacing.
abstract final class PanelFormMetrics {
  /// Outer padding for scrollable command-panel forms.
  static const EdgeInsets panelPadding = EdgeInsets.all(24);

  /// Padding inside bordered form sections.
  static const EdgeInsets sectionPadding = EdgeInsets.all(18);

  /// Gap between peer form sections.
  static const double sectionGap = 36;

  /// Gap between fields in rows and grids.
  static const double fieldGap = 22;

  /// Compact gap between related form controls.
  static const double compactGap = 14;

  /// Gap between an external field label and its control.
  static const double labelGap = 6;

  /// Width where two-column field layout becomes comfortable.
  static const double twoColumnMinWidth = 760;

  /// Standard single-line form input font size.
  static const double fieldFontSize = 16;

  /// Standard single-line form input line height.
  static const double fieldLineHeight = 1.25;
}

/// PanelFormView renders a scrollable command-panel form body.
class PanelFormView extends StatelessWidget {
  /// Creates a shared panel form body.
  const PanelFormView({super.key, required this.children});

  /// Form sections and content blocks.
  final List<Widget> children;

  /// Builds the shared form viewport.
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: PanelFormMetrics.panelPadding,
      itemBuilder: (context, index) => children[index],
      separatorBuilder: (context, index) =>
          const SizedBox(height: PanelFormMetrics.sectionGap),
      itemCount: children.length,
    );
  }
}

/// PanelFormSection renders one unframed command-panel form group.
class PanelFormSection extends StatelessWidget {
  /// Creates a titled panel form section.
  const PanelFormSection({
    super.key,
    this.title = '',
    this.icon,
    required this.children,
  });

  /// Optional section title.
  final String title;

  /// Optional icon shown with the section title.
  final IconData? icon;

  /// Section content.
  final List<Widget> children;

  /// Builds a section that relies on the right pane background.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title.isNotEmpty) ...<Widget>[
          PanelFormSectionHeader(title: title, icon: icon),
          const SizedBox(height: 26),
        ],
        ...children,
      ],
    );
  }
}

/// PanelFormSectionHeader renders concept-aligned form group headings.
class PanelFormSectionHeader extends StatelessWidget {
  /// Creates a shared form section header.
  const PanelFormSectionHeader({super.key, required this.title, this.icon});

  /// Header title.
  final String title;

  /// Optional leading icon.
  final IconData? icon;

  /// Builds an uppercase form section heading with an icon.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final effectiveIcon = icon ?? _panelFormSectionIconFor(title);
    return Row(
      children: <Widget>[
        Icon(effectiveIcon, size: 22, color: colors.ink),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

/// PanelFormFieldLabel renders labels outside shared form controls.
class PanelFormFieldLabel extends StatelessWidget {
  /// Creates a shared external field label.
  const PanelFormFieldLabel({super.key, required this.label});

  /// Field label text.
  final String label;

  /// Builds the label above a form field.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.ink.withValues(alpha: 0.84),
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.35,
      ),
    );
  }
}

/// PanelLabeledFormControl positions a label above one shared form control.
class PanelLabeledFormControl extends StatelessWidget {
  /// Creates a labeled form control wrapper.
  const PanelLabeledFormControl({
    super.key,
    required this.label,
    required this.child,
  });

  /// Field label.
  final String label;

  /// Field widget.
  final Widget child;

  /// Builds a label/control pair with concept spacing.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelFormFieldLabel(label: label),
        const SizedBox(height: PanelFormMetrics.labelGap),
        child,
      ],
    );
  }
}

/// PanelFieldGrid lays out fields with consistent row and column gaps.
class PanelFieldGrid extends StatelessWidget {
  /// Creates a responsive shared field grid.
  const PanelFieldGrid({super.key, required this.children});

  /// Field widgets to arrange.
  final List<Widget> children;

  /// Builds a one- or two-column field grid with stable row spacing.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns =
            constraints.maxWidth >= PanelFormMetrics.twoColumnMinWidth;
        final itemWidth = useTwoColumns
            ? (constraints.maxWidth - PanelFormMetrics.fieldGap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: PanelFormMetrics.fieldGap,
          runSpacing: PanelFormMetrics.fieldGap,
          children: <Widget>[
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// PanelSaveFeedbackState describes transient autosave feedback.
enum PanelSaveFeedbackState {
  /// No save feedback is visible.
  idle,

  /// A save attempt is running.
  saving,

  /// The latest save completed successfully.
  success,

  /// The latest save failed after bounded retries.
  failure,
}

/// PanelSaveFeedbackController owns retry and transient form feedback state.
class PanelSaveFeedbackController extends ChangeNotifier {
  /// Creates a shared panel save-feedback controller.
  PanelSaveFeedbackController({
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 180),
    this.successDuration = const Duration(milliseconds: 850),
  });

  /// Maximum save attempts before failure feedback is shown.
  final int maxAttempts;

  /// Delay between retry attempts.
  final Duration retryDelay;

  /// How long success feedback remains visible.
  final Duration successDuration;

  PanelSaveFeedbackState _state = PanelSaveFeedbackState.idle;
  Timer? _resetTimer;
  int _runId = 0;

  /// Current feedback state.
  PanelSaveFeedbackState get state => _state;

  /// Runs one save with bounded retries and field feedback.
  Future<bool> run(Future<void> Function() save) async {
    final runId = ++_runId;
    _resetTimer?.cancel();
    _setState(PanelSaveFeedbackState.saving);
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        await save();
        if (runId != _runId) {
          return false;
        }
        _setState(PanelSaveFeedbackState.success);
        _resetTimer = Timer(successDuration, () {
          if (runId == _runId) {
            _setState(PanelSaveFeedbackState.idle);
          }
        });
        return true;
      } catch (_) {
        if (attempt < attempts - 1) {
          await Future<void>.delayed(retryDelay * (attempt + 1));
        }
      }
    }
    if (runId == _runId) {
      _setState(PanelSaveFeedbackState.failure);
    }
    return false;
  }

  /// Releases delayed feedback timers.
  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  /// Updates feedback state and notifies listeners.
  void _setState(PanelSaveFeedbackState state) {
    if (_state == state) {
      return;
    }
    _state = state;
    notifyListeners();
  }
}

/// PanelSaveFeedback exposes transient save colors to descendant fields.
class PanelSaveFeedback extends StatelessWidget {
  /// Creates a shared save-feedback scope.
  const PanelSaveFeedback({
    super.key,
    required PanelSaveFeedbackController controller,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
  }) : _controller = controller;

  /// Feedback controller for this scope.
  final PanelSaveFeedbackController _controller;

  /// Descendant form content.
  final Widget child;

  /// Animation duration for feedback color changes.
  final Duration duration;

  /// Builds an inherited animated feedback scope.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return AnimatedBuilder(
      animation: _controller,
      child: child,
      builder: (context, child) {
        final state = _controller.state;
        return TweenAnimationBuilder<Color?>(
          duration: duration,
          tween: ColorTween(end: _targetBorderColor(state, colors)),
          child: child,
          builder: (context, color, child) {
            final borderColor = color ?? colors.border;
            return _PanelSaveFeedbackScope(
              borderColor: borderColor,
              active:
                  state == PanelSaveFeedbackState.success ||
                  state == PanelSaveFeedbackState.failure ||
                  borderColor != colors.border,
              child: child!,
            );
          },
        );
      },
    );
  }

  /// Returns the feedback border color inherited by a form field.
  static Color borderColorOf(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return context
            .dependOnInheritedWidgetOfExactType<_PanelSaveFeedbackScope>()
            ?.borderColor ??
        colors.border;
  }

  /// Returns whether save feedback should override focused borders.
  static bool isActiveOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_PanelSaveFeedbackScope>()
            ?.active ??
        false;
  }

  /// Maps feedback state to a border color.
  static Color _targetBorderColor(
    PanelSaveFeedbackState state,
    AgentAwesomePalette colors,
  ) {
    return switch (state) {
      PanelSaveFeedbackState.success => colors.green,
      PanelSaveFeedbackState.failure => Colors.red.shade700,
      PanelSaveFeedbackState.saving => colors.border,
      PanelSaveFeedbackState.idle => colors.border,
    };
  }
}

/// _PanelSaveFeedbackScope stores transient feedback values.
class _PanelSaveFeedbackScope extends InheritedWidget {
  /// Creates an inherited panel save-feedback scope.
  const _PanelSaveFeedbackScope({
    required this.borderColor,
    required this.active,
    required super.child,
  });

  /// Current animated border color.
  final Color borderColor;

  /// Whether feedback is actively controlling field borders.
  final bool active;

  /// Notifies descendants when feedback values change.
  @override
  bool updateShouldNotify(_PanelSaveFeedbackScope oldWidget) {
    return oldWidget.borderColor != borderColor || oldWidget.active != active;
  }
}

/// PanelFormFieldBase is the parent class for command-panel form fields.
abstract class PanelFormFieldBase extends StatelessWidget {
  /// Creates a shared command-panel form field base.
  const PanelFormFieldBase({super.key, required this.label});

  /// Field label.
  final String label;

  /// Creates standard field decoration for subclasses.
  @protected
  InputDecoration decoration(
    BuildContext context, {
    Widget? suffixIcon,
    FloatingLabelBehavior floatingLabelBehavior = FloatingLabelBehavior.auto,
    bool multiline = false,
  }) {
    final feedbackActive = PanelSaveFeedback.isActiveOf(context);
    final feedbackColor = PanelSaveFeedback.borderColorOf(context);
    final decoration = PanelFormDecoration.field(
      context,
      label: label,
      suffixIcon: suffixIcon,
      floatingLabelBehavior: floatingLabelBehavior,
      multiline: multiline,
    );
    if (!feedbackActive) {
      return decoration;
    }
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: feedbackColor,
        width: AgentAwesomeStrokeTokens.borderWidth,
      ),
    );
    return decoration.copyWith(
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border,
    );
  }
}

/// PanelTextFormField renders autosaved command-panel text inputs.
class PanelTextFormField extends PanelFormFieldBase {
  /// Creates a shared text form field.
  const PanelTextFormField({
    super.key,
    required super.label,
    this.minLines,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
    this.monospace = false,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
  });

  /// Text controller owned by the parent editor.
  final TextEditingController controller;

  /// Minimum field lines.
  final int? minLines;

  /// Maximum field lines.
  final int maxLines;

  /// Optional keyboard override.
  final TextInputType? keyboardType;

  /// Whether to render text in a monospace font.
  final bool monospace;

  /// Optional callback for committing single-line edits.
  final ValueChanged<String>? onSubmitted;

  /// Optional callback for text changes.
  final ValueChanged<String>? onChanged;

  /// Whether the field accepts edits.
  final bool enabled;

  /// Builds the shared command-panel text field.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final multiline = maxLines > 1 || (minLines ?? 1) > 1;
    return PanelLabeledFormControl(
      label: label,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType:
            keyboardType ??
            (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
        textInputAction: maxLines == 1
            ? TextInputAction.done
            : TextInputAction.newline,
        minLines:
            minLines ?? (maxLines == 1 ? 1 : (maxLines < 3 ? maxLines : 3)),
        maxLines: maxLines,
        onEditingComplete: onSubmitted == null
            ? null
            : () => onSubmitted!(controller.text),
        onChanged: onChanged,
        style: TextStyle(
          color: colors.ink,
          fontSize: PanelFormMetrics.fieldFontSize,
          height: PanelFormMetrics.fieldLineHeight,
          fontFamily: monospace ? 'monospace' : null,
        ),
        decoration: decoration(context, multiline: multiline),
      ),
    );
  }
}

/// PanelReadOnlyFormField renders selectable read-only form metadata.
class PanelReadOnlyFormField extends PanelFormFieldBase {
  /// Creates a read-only shared panel field.
  const PanelReadOnlyFormField({
    super.key,
    required super.label,
    required this.value,
  });

  /// Display value.
  final String value;

  /// Builds a read-only command-panel field.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return PanelLabeledFormControl(
      label: label,
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        style: TextStyle(
          color: colors.ink,
          fontSize: PanelFormMetrics.fieldFontSize,
          height: PanelFormMetrics.fieldLineHeight,
        ),
        decoration: decoration(context),
      ),
    );
  }
}

/// PanelDropdownFormField renders shared command-panel dropdown inputs.
class PanelDropdownFormField<T> extends PanelFormFieldBase {
  /// Creates a shared dropdown form field.
  const PanelDropdownFormField({
    super.key,
    required super.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
    this.tooltip,
    this.showLabel = true,
  });

  /// Selected value.
  final T value;

  /// Available values.
  final List<T> values;

  /// Converts values to visible labels.
  final String Function(T value) labelFor;

  /// Handles a selected value.
  final ValueChanged<T> onChanged;

  /// Optional tooltip.
  final String? tooltip;

  /// Whether the field label should be visible.
  final bool showLabel;

  /// Builds the shared command-panel dropdown.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final options = values.isEmpty ? <T>[value] : values;
    final selected = options.contains(value) ? value : options.first;
    final dropdown = DropdownButtonFormField<T>(
      initialValue: selected,
      isDense: true,
      isExpanded: true,
      dropdownColor: colors.surface,
      icon: Icon(Icons.expand_more, size: 18, color: colors.ink),
      style: TextStyle(
        color: colors.ink,
        fontSize: PanelFormMetrics.fieldFontSize,
        height: PanelFormMetrics.fieldLineHeight,
      ),
      decoration: decoration(context),
      items: <DropdownMenuItem<T>>[
        for (final option in options)
          DropdownMenuItem<T>(
            value: option,
            child: Text(
              labelFor(option),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: PanelFormMetrics.fieldFontSize,
                height: PanelFormMetrics.fieldLineHeight,
              ),
            ),
          ),
      ],
      onChanged: (next) {
        if (next != null) {
          onChanged(next);
        }
      },
    );
    final field = showLabel
        ? PanelLabeledFormControl(label: label, child: dropdown)
        : dropdown;
    if (tooltip == null || tooltip!.trim().isEmpty) {
      return field;
    }
    return Tooltip(message: tooltip!, child: field);
  }
}

IconData _panelFormSectionIconFor(String title) {
  final normalized = title.trim().toLowerCase();
  if (normalized.contains('chat')) {
    return Icons.chat_bubble_outline;
  }
  if (normalized.contains('model')) {
    return Icons.view_in_ar_outlined;
  }
  if (normalized.contains('memory')) {
    return Icons.account_tree_outlined;
  }
  if (normalized.contains('server')) {
    return Icons.dns_outlined;
  }
  if (normalized.contains('command') || normalized.contains('exec')) {
    return Icons.terminal_outlined;
  }
  if (normalized.contains('validation')) {
    return Icons.fact_check_outlined;
  }
  if (normalized.contains('credential')) {
    return Icons.key_outlined;
  }
  if (normalized.contains('file')) {
    return Icons.folder_outlined;
  }
  if (normalized.contains('detail')) {
    return Icons.info_outline;
  }
  return Icons.tune_outlined;
}
