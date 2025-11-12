import 'package:flutter/material.dart';
import '../models/project.dart';

/// Extension methods for TaskStatus enum to provide UI-related functionality
extension TaskStatusExtension on TaskStatus {
  /// Get the appropriate icon for this task status
  IconData getIcon() {
    switch (this) {
      case TaskStatus.idle:
        return Icons.play_circle_outline;
      case TaskStatus.running:
        return Icons.stop_circle_outlined;
      case TaskStatus.success:
        return Icons.play_circle_outline; // Allow rerunning successful tasks
      case TaskStatus.failed:
        return Icons.play_circle_outline; // Show play icon to indicate it can be restarted
    }
  }

  /// Get the appropriate color for this task status
  Color getColor(BuildContext context) {
    switch (this) {
      case TaskStatus.idle:
        return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
      case TaskStatus.running:
        return Theme.of(context).colorScheme.primary;
      case TaskStatus.success:
        return Colors.green;
      case TaskStatus.failed:
        return Theme.of(context).colorScheme.error;
    }
  }

  /// Get the background color for task containers
  Color? getBackgroundColor(BuildContext context, {required bool isSelected}) {
    if (isSelected) {
      return Theme.of(context).colorScheme.primaryContainer;
    }

    if (this == TaskStatus.failed) {
      return Theme.of(context).colorScheme.errorContainer;
    }

    return null;
  }

  /// Get the text color for tasks
  Color? getTextColor(BuildContext context, {required bool isSelected}) {
    if (isSelected) {
      return Theme.of(context).colorScheme.onPrimaryContainer;
    }

    if (this == TaskStatus.failed) {
      return Theme.of(context).colorScheme.onErrorContainer;
    }

    return null;
  }
}
