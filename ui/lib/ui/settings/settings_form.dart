/// Provides shared settings form layout primitives.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../panels/panels.dart';

/// SettingsFormMetrics defines spacing and sizing used by settings forms.
abstract final class SettingsFormMetrics {
  /// Outer padding for scrollable settings content.
  static const EdgeInsets panelPadding = EdgeInsets.all(24);

  /// Padding inside each settings form section.
  static const EdgeInsets sectionPadding = EdgeInsets.all(18);

  /// Gap between form sections.
  static const double sectionGap = 18;

  /// Gap between fields inside a grid.
  static const double fieldGap = 10;

  /// Compact vertical gap inside a section.
  static const double compactGap = 10;

  /// Minimum width that allows two fields to sit side by side.
  static const double twoColumnMinWidth = 760;
}

/// SettingsInputDecoration builds the shared form field chrome.
abstract final class SettingsInputDecoration {
  /// Creates a consistent settings input decoration.
  static InputDecoration field(
    BuildContext context, {
    required String label,
    String? hintText,
    bool isDense = false,
    bool? alignLabelWithHint,
    FloatingLabelBehavior? floatingLabelBehavior,
    Widget? prefixIcon,
    BoxConstraints? prefixIconConstraints,
    Widget? suffixIcon,
    BoxConstraints? suffixIconConstraints,
  }) {
    final activeFeedback = SettingsSaveFeedback.isActiveOf(context);
    final border = _border(SettingsSaveFeedback.borderColorOf(context));
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      isDense: isDense,
      alignLabelWithHint: alignLabelWithHint,
      floatingLabelBehavior: floatingLabelBehavior,
      prefixIcon: prefixIcon,
      prefixIconConstraints: prefixIconConstraints,
      suffixIcon: suffixIcon,
      suffixIconConstraints: suffixIconConstraints,
      filled: true,
      fillColor: AuroraColors.surface,
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: activeFeedback ? border : null,
    );
  }

  /// Builds one outline border with the provided color.
  static OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color),
    );
  }
}

/// SettingsSaveFeedbackState describes current visual save feedback.
enum SettingsSaveFeedbackState {
  /// No save feedback is currently displayed.
  idle,

  /// A save attempt is currently running.
  saving,

  /// The latest save completed successfully.
  success,

  /// The latest save failed after bounded retries.
  failure,
}

/// SettingsSaveFeedbackController runs saves and exposes visual state.
class SettingsSaveFeedbackController extends ChangeNotifier {
  /// Creates a reusable save feedback controller.
  SettingsSaveFeedbackController({
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 180),
    this.successDuration = const Duration(milliseconds: 850),
  });

  /// Maximum save attempts before a failure state is held.
  final int maxAttempts;

  /// Delay between retry attempts.
  final Duration retryDelay;

  /// How long a success state remains before fading back to idle.
  final Duration successDuration;

  SettingsSaveFeedbackState _state = SettingsSaveFeedbackState.idle;
  Timer? _resetTimer;
  int _runId = 0;

  /// Current feedback state.
  SettingsSaveFeedbackState get state => _state;

  /// Runs one save operation with bounded retries and feedback.
  Future<bool> run(Future<void> Function() save) async {
    final runId = ++_runId;
    _resetTimer?.cancel();
    _setState(SettingsSaveFeedbackState.saving);
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        await save();
        if (runId != _runId) {
          return false;
        }
        _setState(SettingsSaveFeedbackState.success);
        _resetTimer = Timer(successDuration, () {
          if (runId == _runId) {
            _setState(SettingsSaveFeedbackState.idle);
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
      _setState(SettingsSaveFeedbackState.failure);
    }
    return false;
  }

  /// Releases the delayed reset timer.
  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  /// Updates the current state and notifies listeners when it changes.
  void _setState(SettingsSaveFeedbackState state) {
    if (_state == state) {
      return;
    }
    _state = state;
    notifyListeners();
  }
}

/// SettingsSaveFeedback provides animated save state to descendant fields.
class SettingsSaveFeedback extends StatelessWidget {
  /// Creates a reusable save feedback scope.
  const SettingsSaveFeedback({
    super.key,
    required SettingsSaveFeedbackController controller,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
  }) : _controller = controller;

  /// Controller that owns retry behavior and feedback state.
  final SettingsSaveFeedbackController _controller;

  /// Form field subtree that receives save feedback state.
  final Widget child;

  /// Duration used to fade field borders between feedback states.
  final Duration duration;

  /// Builds an inherited animated border feedback scope.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: child,
      builder: (context, child) {
        final state = _controller.state;
        return TweenAnimationBuilder<Color?>(
          duration: duration,
          tween: ColorTween(end: _targetBorderColor(state)),
          child: child,
          builder: (context, color, child) {
            final borderColor = color ?? AuroraColors.border;
            return _SettingsSaveFeedbackScope(
              borderColor: borderColor,
              active:
                  state == SettingsSaveFeedbackState.success ||
                  state == SettingsSaveFeedbackState.failure ||
                  borderColor != AuroraColors.border,
              child: child!,
            );
          },
        );
      },
    );
  }

  /// Returns the inherited animated border color for a form field.
  static Color borderColorOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_SettingsSaveFeedbackScope>()
            ?.borderColor ??
        AuroraColors.border;
  }

  /// Returns whether feedback should temporarily own focused borders.
  static bool isActiveOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_SettingsSaveFeedbackScope>()
            ?.active ??
        false;
  }

  /// Maps feedback state to the target outline color.
  static Color _targetBorderColor(SettingsSaveFeedbackState state) {
    return switch (state) {
      SettingsSaveFeedbackState.success => AuroraColors.green,
      SettingsSaveFeedbackState.failure => Colors.red.shade700,
      SettingsSaveFeedbackState.saving => AuroraColors.border,
      SettingsSaveFeedbackState.idle => AuroraColors.border,
    };
  }
}

/// _SettingsSaveFeedbackScope stores animated field feedback values.
class _SettingsSaveFeedbackScope extends InheritedWidget {
  /// Creates an inherited save feedback scope.
  const _SettingsSaveFeedbackScope({
    required this.borderColor,
    required this.active,
    required super.child,
  });

  /// Animated border color exposed to descendant fields.
  final Color borderColor;

  /// Whether feedback should override focused field borders.
  final bool active;

  /// Notifies fields when any feedback display value changes.
  @override
  bool updateShouldNotify(_SettingsSaveFeedbackScope oldWidget) {
    return oldWidget.borderColor != borderColor || oldWidget.active != active;
  }
}

/// FormPanel renders grouped form content with standard padding.
class FormPanel extends StatelessWidget {
  /// Creates a reusable settings form panel.
  const FormPanel({super.key, required this.children});

  /// Form sections and content blocks.
  final List<Widget> children;

  /// Builds a scrollable settings form body.
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: SettingsFormMetrics.panelPadding,
      itemBuilder: (context, index) => children[index],
      separatorBuilder: (context, index) =>
          const SizedBox(height: SettingsFormMetrics.sectionGap),
      itemCount: children.length,
    );
  }
}

/// FormSectionCard renders one bordered group inside a settings form.
class FormSectionCard extends StatelessWidget {
  /// Creates a reusable form section card.
  const FormSectionCard({super.key, this.title = '', required this.children});

  /// Optional section title.
  final String title;

  /// Section content.
  final List<Widget> children;

  /// Builds one settings-style form group.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: SettingsFormMetrics.sectionPadding,
      decoration: BoxDecoration(
        color: const Color(0xfffffcf8),
        border: Border.all(color: AuroraColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title.isNotEmpty) ...<Widget>[
            PanelSectionLabel(title),
            const SizedBox(height: 14),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// SettingsFormSubsection renders a titled block inside one form section.
class SettingsFormSubsection extends StatelessWidget {
  /// Creates a reusable inner form subsection.
  const SettingsFormSubsection({
    super.key,
    required this.title,
    required this.children,
  });

  /// Inner subsection title.
  final String title;

  /// Subsection content.
  final List<Widget> children;

  /// Builds a titled subsection with consistent vertical spacing.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PanelSectionLabel(title),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

/// SettingsFieldGrid lays out fields in one or two responsive columns.
class SettingsFieldGrid extends StatelessWidget {
  /// Creates a reusable responsive settings field grid.
  const SettingsFieldGrid({super.key, required this.children});

  /// Field widgets to arrange.
  final List<Widget> children;

  /// Builds a stable responsive field grid.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns =
            constraints.maxWidth >= SettingsFormMetrics.twoColumnMinWidth;
        final itemWidth = useTwoColumns
            ? (constraints.maxWidth - SettingsFormMetrics.fieldGap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: SettingsFormMetrics.fieldGap,
          children: <Widget>[
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// SettingsFieldRow aligns leading, main, and trailing field controls.
class SettingsFieldRow extends StatelessWidget {
  /// Creates one aligned settings row.
  const SettingsFieldRow({
    super.key,
    required this.child,
    this.leading,
    this.trailing,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  /// Optional leading control such as a switch.
  final Widget? leading;

  /// Main row content.
  final Widget child;

  /// Optional trailing control or status badge.
  final Widget? trailing;

  /// Row cross-axis alignment.
  final CrossAxisAlignment crossAxisAlignment;

  /// Builds the aligned field row.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: <Widget>[
        if (leading != null) ...<Widget>[
          leading!,
          const SizedBox(width: SettingsFormMetrics.fieldGap),
        ],
        Expanded(child: child),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: SettingsFormMetrics.fieldGap),
          trailing!,
        ],
      ],
    );
  }
}

/// SettingsToggleField renders a consistent settings switch row.
class SettingsToggleField extends StatelessWidget {
  /// Creates a reusable labeled switch field.
  const SettingsToggleField({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle = '',
  });

  /// Toggle title.
  final String title;

  /// Optional toggle detail text.
  final String subtitle;

  /// Current switch value.
  final bool value;

  /// Switch change callback.
  final ValueChanged<bool> onChanged;

  /// Builds a settings toggle with consistent spacing and alignment.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsFormMetrics.compactGap),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AuroraColors.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: SettingsFormMetrics.fieldGap),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
