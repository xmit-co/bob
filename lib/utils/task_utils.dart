import 'package:path/path.dart' as path;
import '../models/project.dart';

/// Utilities for task-related operations
class TaskUtils {
  /// Generates a unique key for a task based on its project path and task name
  static String getTaskKey(Project project, Task task) {
    // Normalize path to ensure consistent keys across platforms
    return '${path.normalize(project.path)}:${task.name}';
  }

  TaskUtils._();
}
