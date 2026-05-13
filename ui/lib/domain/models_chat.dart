/// Chat session, message, tool activity, and confirmation data models.
part of 'models.dart';

/// ChatRole identifies the speaker or event class in a chat timeline.
enum ChatRole {
  /// User-authored message.
  user,

  /// Assistant-authored message.
  assistant,

  /// Tool or function activity.
  tool,
}

/// ChatSession represents the runtime session backing one user-visible chat.
class ChatSession {
  /// Creates a user-visible chat summary backed by a runtime session.
  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  /// Runtime session identifier.
  final String id;

  /// Human-readable title.
  final String title;

  /// Last update timestamp.
  final DateTime updatedAt;
}

/// ChatHistoryEntry stores app-owned chat metadata across profiles.
class ChatHistoryEntry {
  /// Creates a local chat history entry.
  const ChatHistoryEntry({
    required this.profilePath,
    required this.profileId,
    required this.profileLabel,
    required this.sessionId,
    required this.title,
    required this.updatedAt,
    this.createdAt,
    this.titleStatus = 'session',
    this.titleError = '',
  });

  /// Runtime profile path that owns the chat session.
  final String profilePath;

  /// Runtime profile id captured when the chat was saved.
  final String profileId;

  /// Runtime profile label captured when the chat was saved.
  final String profileLabel;

  /// Chat session id inside the owning profile.
  final String sessionId;

  /// App-visible chat title.
  final String title;

  /// Chat creation timestamp when known.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime updatedAt;

  /// Title generation state such as session, manual, pending, generated, or failed.
  final String titleStatus;

  /// Last title generation error.
  final String titleError;

  /// Stable app-local key for profile/session lookup.
  String get key {
    return '$profilePath::$sessionId';
  }

  /// Returns a copy with selected metadata changed.
  ChatHistoryEntry copyWith({
    String? profilePath,
    String? profileId,
    String? profileLabel,
    String? sessionId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? titleStatus,
    String? titleError,
  }) {
    return ChatHistoryEntry(
      profilePath: profilePath ?? this.profilePath,
      profileId: profileId ?? this.profileId,
      profileLabel: profileLabel ?? this.profileLabel,
      sessionId: sessionId ?? this.sessionId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      titleStatus: titleStatus ?? this.titleStatus,
      titleError: titleError ?? this.titleError,
    );
  }

  /// Encodes this history entry to JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'profile_path': profilePath,
      'profile_id': profileId,
      'profile_label': profileLabel,
      'session_id': sessionId,
      'title': title,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'title_status': titleStatus,
      'title_error': titleError,
    };
  }

  /// Parses a history entry from decoded JSON.
  factory ChatHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ChatHistoryEntry(
      profilePath: stringValue(json['profile_path']),
      profileId: stringValue(json['profile_id']),
      profileLabel: stringValue(json['profile_label']),
      sessionId: stringValue(json['session_id']),
      title: stringValue(json['title'], fallback: 'Untitled chat'),
      createdAt: parseOptionalDateTime(json['created_at']),
      updatedAt: parseOptionalDateTime(json['updated_at']) ?? DateTime.now(),
      titleStatus: stringValue(json['title_status'], fallback: 'session'),
      titleError: stringValue(json['title_error']),
    );
  }
}

/// ChatMessage represents one normalized message or activity row.
class ChatMessage {
  /// Creates a normalized chat message.
  const ChatMessage({
    required this.id,
    required this.role,
    required this.author,
    required this.text,
    required this.createdAt,
    this.toolActivity,
    this.isPartial = false,
  });

  /// Stable UI id.
  final String id;

  /// Speaker or event type.
  final ChatRole role;

  /// Display author.
  final String author;

  /// Display text.
  final String text;

  /// Timestamp for ordering and display.
  final DateTime createdAt;

  /// Optional tool activity metadata.
  final ToolActivity? toolActivity;

  /// Whether the message is a streaming partial.
  final bool isPartial;

  /// Returns a copy with changed display text.
  ChatMessage copyWith({String? text, bool? isPartial}) {
    return ChatMessage(
      id: id,
      role: role,
      author: author,
      text: text ?? this.text,
      createdAt: createdAt,
      toolActivity: toolActivity,
      isPartial: isPartial ?? this.isPartial,
    );
  }
}

/// ToolActivity summarizes one function call or result.
class ToolActivity {
  /// Creates a tool activity row.
  const ToolActivity({
    required this.name,
    required this.status,
    required this.summary,
  });

  /// Tool or function name.
  final String name;

  /// Short status such as requested, completed, or denied.
  final String status;

  /// Human-readable summary.
  final String summary;
}

/// ConfirmationRequest stores a runtime confirmation prompt awaiting user choice.
class ConfirmationRequest {
  /// Creates a confirmation request.
  const ConfirmationRequest({
    required this.callId,
    required this.hint,
    required this.options,
    this.toolName = '',
  });

  /// Runtime function-call id to echo in the response.
  final String callId;

  /// Human-readable prompt text.
  final String hint;

  /// Available confirmation options.
  final List<ConfirmationOption> options;

  /// Original tool name that requested confirmation, when supplied by the runtime.
  final String toolName;
}

/// ConfirmationOption describes one selectable confirmation action.
class ConfirmationOption {
  /// Creates a confirmation option.
  const ConfirmationOption({required this.action, required this.label});

  /// Machine action sent back to the runtime.
  final String action;

  /// User-facing label.
  final String label;
}

/// ConfirmationReply is the user's response to a runtime confirmation request.
class ConfirmationReply {
  /// Creates a confirmation reply.
  const ConfirmationReply({
    required this.callId,
    required this.confirmed,
    this.action,
  });

  /// Runtime function-call id.
  final String callId;

  /// Whether the action is approved.
  final bool confirmed;

  /// Optional selected action.
  final String? action;
}
