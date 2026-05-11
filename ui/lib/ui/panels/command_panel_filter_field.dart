/// Command-panel local filter field widget.
part of 'panels.dart';

/// _CommandSubShellFilterField renders the local fuzzy-search input.
class _CommandSubShellFilterField extends StatelessWidget {
  const _CommandSubShellFilterField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  /// Builds the local command-area filter.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return SizedBox(
      height: 38,
      child: TextField(
        key: const ValueKey<String>('command-subshell-filter'),
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18, color: colors.muted),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          hintText: hintText,
          hintStyle: TextStyle(color: colors.muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          filled: true,
          fillColor: colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.searchBorder),
          ),
        ),
      ),
    );
  }
}
