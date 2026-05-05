/// Formats task work-breakdown metadata for task UI surfaces.
library;

import '../domain/models.dart';

/// Reports whether WBS metadata has any visible data.
bool taskWbsHasContent(TaskWorkBreakdown workBreakdown) {
  return workBreakdown.code.isNotEmpty ||
      workBreakdown.deliverable.isNotEmpty ||
      workBreakdown.startCriteria.isNotEmpty ||
      workBreakdown.acceptanceCriteria.isNotEmpty ||
      workBreakdown.requirementRefs.isNotEmpty ||
      workBreakdown.rubricRefs.isNotEmpty ||
      workBreakdown.resources.isNotEmpty ||
      workBreakdown.estimatedCostCents > 0 ||
      workBreakdown.costCurrency.isNotEmpty;
}

/// Formats task-level WBS spend.
String formatTaskWbsSpend(TaskWorkBreakdown workBreakdown) {
  return formatMinorUnitSpend(
    workBreakdown.estimatedCostCents,
    workBreakdown.costCurrency,
  );
}

/// Formats resource-level WBS spend.
String formatTaskResourceSpend(TaskResourceRequirement resource) {
  return formatMinorUnitSpend(
    resource.estimatedCostCents,
    resource.costCurrency,
  );
}

/// Formats minor-unit spend values for task display.
String formatMinorUnitSpend(int cents, String currency) {
  if (cents <= 0) {
    return '';
  }
  final amount = cents / 100;
  final formatted = amount.toStringAsFixed(2);
  return currency.trim().isEmpty ? formatted : '$formatted ${currency.trim()}';
}

/// Formats resource quantity without unnecessary decimals.
String formatTaskQuantity(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(2);
}

/// Splits newline-delimited WBS values.
List<String> splitWbsLines(String value) {
  return value
      .split('\n')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// Encodes one resource requirement into an editable line.
String taskResourceRequirementLine(TaskResourceRequirement resource) {
  return <String>[
    resource.name,
    resource.type,
    resource.quantity <= 0 ? '' : formatTaskQuantity(resource.quantity),
    resource.unit,
    resource.estimatedCostCents <= 0
        ? ''
        : resource.estimatedCostCents.toString(),
    resource.costCurrency,
    resource.notes,
  ].join(' | ');
}

/// Parses resource requirement lines from the WBS dialog.
List<TaskResourceRequirement>? parseTaskResourceRequirementLines(String value) {
  final resources = <TaskResourceRequirement>[];
  for (final line in splitWbsLines(value)) {
    final parts = line.split('|').map((item) => item.trim()).toList();
    final name = parts.isEmpty ? '' : parts[0];
    if (name.isEmpty) {
      continue;
    }
    final quantityText = parts.length > 2 ? parts[2] : '';
    final costText = parts.length > 4 ? parts[4] : '';
    final quantity = quantityText.isEmpty ? 0.0 : double.tryParse(quantityText);
    final cost = costText.isEmpty ? 0 : int.tryParse(costText);
    if (quantity == null || quantity < 0 || cost == null || cost < 0) {
      return null;
    }
    resources.add(
      TaskResourceRequirement(
        name: name,
        type: parts.length > 1 ? parts[1] : '',
        quantity: quantity,
        unit: parts.length > 3 ? parts[3] : '',
        estimatedCostCents: cost,
        costCurrency: parts.length > 5 ? parts[5] : '',
        notes: parts.length > 6 ? parts.sublist(6).join(' | ') : '',
      ),
    );
  }
  return resources;
}
