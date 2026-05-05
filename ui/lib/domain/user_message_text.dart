/// Normalizes internal user-message wrappers before chat display.
library;

const _screenCommandPromptPrefix =
    'Treat this as a command for the current UI screen: ';
const _screenCommandUserLinePrefix = 'User command: ';
const _screenCommandRelevantLinePrefix = 'Relevant ids: ';

/// Builds the hidden prompt sent for a screen-scoped user command.
String buildScreenCommandPrompt({
  required String scopeLabel,
  required String userText,
  String relevantIds = '',
}) {
  final selected = relevantIds.trim();
  final suffix = selected.isEmpty
      ? ''
      : '\n$_screenCommandRelevantLinePrefix$selected';
  return '$_screenCommandPromptPrefix$scopeLabel.\n'
      '$_screenCommandUserLinePrefix${userText.trim()}$suffix';
}

/// Returns the display-safe user text for a possibly wrapped user prompt.
String displayTextFromUserPrompt(String text) {
  if (!text.startsWith(_screenCommandPromptPrefix)) {
    return text;
  }
  final userLineStart = text.indexOf('\n$_screenCommandUserLinePrefix');
  if (userLineStart == -1) {
    return text;
  }
  final commandStart = userLineStart + 1 + _screenCommandUserLinePrefix.length;
  var displayText = text.substring(commandStart);
  final relevantStart = displayText.indexOf(
    '\n$_screenCommandRelevantLinePrefix',
  );
  if (relevantStart != -1) {
    displayText = displayText.substring(0, relevantStart);
  }
  return displayText.trim();
}
