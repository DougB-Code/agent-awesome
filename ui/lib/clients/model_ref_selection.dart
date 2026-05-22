/// Selects ADK model references from app-owned model config documents.
library;

import '../domain/model_config.dart';

/// ModelRefSelectionException reports missing model selection state.
class ModelRefSelectionException implements Exception {
  /// Creates a selection exception.
  const ModelRefSelectionException(this.message);

  /// Human-readable failure detail.
  final String message;

  @override
  String toString() => 'ModelRefSelectionException: $message';
}

/// Returns an explicit model ref or the config document's default ref.
String selectedModelRefFromConfig({
  required String modelConfigContent,
  required String modelRef,
  required String missingSelection,
  required String missingProviders,
  required String missingDefaultModel,
}) {
  final selected = modelRef.trim();
  if (selected.isNotEmpty) {
    return selected;
  }
  if (modelConfigContent.trim().isEmpty) {
    throw ModelRefSelectionException(missingSelection);
  }
  final document = ModelConfigDocument.parse(modelConfigContent);
  if (document.providers.isEmpty) {
    throw ModelRefSelectionException(missingProviders);
  }
  final defaultRef = document.defaultRef.trim();
  if (defaultRef.isEmpty) {
    throw ModelRefSelectionException(missingDefaultModel);
  }
  return defaultRef;
}
