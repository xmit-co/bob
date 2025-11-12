import 'package:path/path.dart' as p;

enum TaskStatus {
  idle,
  running,
  success,
  failed,
}

enum TaskType {
  script,
  create,
  install,
}

enum LaunchStepStatus {
  pending,
  running,
  paused,
  completed,
  failed,
}

class LaunchStep {
  final String title;
  final LaunchStepStatus status;
  final String? message;
  final List<String> logs;
  final DateTime? startTime;
  final DateTime? endTime;

  LaunchStep({
    required this.title,
    required this.status,
    this.message,
    this.logs = const [],
    DateTime? startTime,
    this.endTime,
  }) : startTime = startTime ?? DateTime.now();

  LaunchStep copyWith({
    String? title,
    LaunchStepStatus? status,
    String? message,
    List<String>? logs,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return LaunchStep(
      title: title ?? this.title,
      status: status ?? this.status,
      message: message ?? this.message,
      logs: logs ?? this.logs,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  LaunchStep addLog(String log) {
    return copyWith(logs: [...logs, log]);
  }

  /// Get title with duration if step is completed
  String get titleWithDuration {
    if (status == LaunchStepStatus.completed && startTime != null) {
      // Use endTime if available (fixed duration), otherwise use current time (for backward compatibility)
      final end = endTime ?? DateTime.now();
      final duration = end.difference(startTime!).inMilliseconds / 1000.0;
      return '$title (${duration.toStringAsFixed(1)}s)';
    }
    return title;
  }
}

class Site {
  final String name;
  final String domain;
  final String service;
  final TaskStatus status;
  final List<LaunchStep> steps;

  Site({
    required this.name,
    required this.domain,
    this.service = 'xmit.co',
    this.status = TaskStatus.idle,
    this.steps = const [],
  });

  Site copyWith({
    String? name,
    String? domain,
    String? service,
    TaskStatus? status,
    List<LaunchStep>? steps,
  }) {
    return Site(
      name: name ?? this.name,
      domain: domain ?? this.domain,
      service: service ?? this.service,
      status: status ?? this.status,
      steps: steps ?? this.steps,
    );
  }
}

class Project {
  final String name;
  final String path;
  final List<Task> tasks;
  final List<Site> sites;
  final String? launchDirectory;

  Project({
    required this.name,
    required String path,
    required this.tasks,
    this.sites = const [],
    this.launchDirectory,
  }) : path = _normalizePath(path);

  /// Normalize path and remove trailing separators
  static String _normalizePath(String path) {
    var normalized = p.normalize(path);
    // Remove trailing separator, but keep root paths like C:\ intact
    if (normalized.length > 1 &&
        (normalized.endsWith(p.separator) || normalized.endsWith('/'))) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  factory Project.fromPackageJson(String path, Map<String, dynamic> json) {
    final name = json['name'] as String? ?? 'Unnamed Project';
    final scripts = json['scripts'] as Map<String, dynamic>? ?? {};

    // Check if there are any dependencies to install
    final dependencies = json['dependencies'] as Map<String, dynamic>? ?? {};
    final devDependencies = json['devDependencies'] as Map<String, dynamic>? ?? {};
    final hasDependencies = dependencies.isNotEmpty || devDependencies.isNotEmpty;

    // Create install task only if there are dependencies
    final List<Task> tasks = [];

    if (hasDependencies) {
      tasks.add(Task(
        name: 'install',
        command: 'bun install',
        type: TaskType.install,
      ));
    }

    // Add script tasks
    tasks.addAll(
      scripts.entries.map((entry) => Task(
        name: entry.key,
        command: entry.value as String,
      )),
    );

    // Load launch configuration from bob
    final bob = json['bob'] as Map<String, dynamic>?;

    // Load sites from bob.sites
    final sm = bob?['sites'] as Map<String, dynamic>? ?? {};
    final sites = sm.entries
        .map((entry) {
          final siteConfig = entry.value as Map<String, dynamic>;
          var service = siteConfig['service'] as String? ?? 'xmit.co';
          // Remove protocol if present for backwards compatibility
          if (service.startsWith('https://')) {
            service = service.substring(8);
          } else if (service.startsWith('http://')) {
            service = service.substring(7);
          }
          return Site(
            name: entry.key,
            domain: siteConfig['domain'] as String? ?? '',
            service: service,
          );
        })
        .toList();

    // Load launch directory from bob.directory
    final launchDirectory = bob?['directory'] as String?;

    return Project(
      name: name,
      path: path,
      tasks: tasks,
      sites: sites,
      launchDirectory: launchDirectory,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      name: json['name'] as String,
      path: json['path'] as String,
      tasks: [], // Tasks will be loaded from package.json when needed
    );
  }
}

class Task {
  final String name;
  final String command;
  final TaskType type;
  final TaskStatus status;
  final int? lastExitCode;
  final String output;

  Task({
    required this.name,
    required this.command,
    this.type = TaskType.script,
    this.status = TaskStatus.idle,
    this.lastExitCode,
    this.output = '',
  });

  /// Create a copy of this task with updated fields
  Task copyWith({
    String? name,
    String? command,
    TaskType? type,
    TaskStatus? status,
    int? lastExitCode,
    String? output,
  }) {
    return Task(
      name: name ?? this.name,
      command: command ?? this.command,
      type: type ?? this.type,
      status: status ?? this.status,
      lastExitCode: lastExitCode ?? this.lastExitCode,
      output: output ?? this.output,
    );
  }
}
