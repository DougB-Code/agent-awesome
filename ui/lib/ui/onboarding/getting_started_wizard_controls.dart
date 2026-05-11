/// First-run setup shared controls and status widgets.
part of 'getting_started_wizard.dart';

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
        Icon(icon, size: 15, color: AgentAwesomeColors.muted),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: AgentAwesomeColors.muted, fontSize: 12),
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
            backgroundColor: AgentAwesomeColors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: AgentAwesomeColors.green,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
            side: const BorderSide(color: AgentAwesomeColors.green),
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
        const Divider(color: AgentAwesomeColors.border),
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
        Text(subtitle, style: const TextStyle(color: AgentAwesomeColors.muted)),
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
        Icon(icon, size: 18, color: AgentAwesomeColors.muted),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(color: AgentAwesomeColors.muted),
          ),
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
