/// Provides shared labels, icons, and severity for Today attention lanes.
library;

import 'package:flutter/material.dart';

/// todayLaneIcon maps Today lanes to familiar Material icons.
IconData todayLaneIcon(String lane) {
  switch (lane) {
    case 'protect':
      return Icons.shield_outlined;
    case 'decide':
      return Icons.balance_outlined;
    case 'do':
      return Icons.check_box_outlined;
    case 'delegate':
      return Icons.group_outlined;
    case 'follow_up':
      return Icons.favorite_border;
    case 'monitor':
      return Icons.visibility_outlined;
    default:
      return Icons.radio_button_unchecked;
  }
}

/// todayLaneLabel maps Today lanes to row labels.
String todayLaneLabel(String lane) {
  switch (lane) {
    case 'protect':
      return 'Protect';
    case 'decide':
      return 'Decide';
    case 'do':
      return 'Do';
    case 'delegate':
      return 'Delegate';
    case 'follow_up':
      return 'Follow-up';
    case 'monitor':
      return 'Monitor';
    default:
      return 'Watch';
  }
}

/// todayLaneSeverity maps Today lanes to semantic colors.
String todayLaneSeverity(String lane) {
  switch (lane) {
    case 'decide':
    case 'follow_up':
      return 'attention';
    case 'delegate':
    case 'do':
      return 'good';
    case 'protect':
      return 'warning';
    default:
      return 'normal';
  }
}
