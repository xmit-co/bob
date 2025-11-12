import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/constants.dart';
import '../models/project.dart';
import '../utils/process_utils.dart';
import '../utils/task_utils.dart';
import './binary_manager.dart';

class TaskService {
  final Map<String, Process> _runningProcesses = {};
  final Map<String, StreamController<String>> _outputControllers = {};
  final Set<String> _explicitlyStopped = {};
  final BinaryManager _binaryManager = BinaryManager();

  Future<void> startTask(Project project, Task task, Function(String) onOutput, Function(int) onExit) async {
    final taskKey = TaskUtils.getTaskKey(project, task);

    // Clear explicitly stopped flag when starting
    _explicitlyStopped.remove(taskKey);

    // Stop existing process if running
    if (_runningProcesses.containsKey(taskKey)) {
      await stopTask(project, task);
    }

    try {
      // Get managed binaries
      final bunPath = await _binaryManager.getBunPath();

      // Build environment with bun in PATH
      final environment = ProcessUtils.buildEnvironmentWithBinaries([bunPath]);

      // Determine arguments based on task type
      final List<String> args;
      if (task.type == TaskType.install) {
        // For install tasks, run 'bun install' directly
        args = ['install'];
      } else {
        // For script tasks, run 'bun run <task-name>'
        // This executes the script from package.json
        args = ['run', task.name];
      }

      final process = await Process.start(
        bunPath,
        args,
        workingDirectory: project.path,
        runInShell: Platform.isWindows, // Use shell on Windows to ensure child processes are killed
        environment: environment,
      );

      _runningProcesses[taskKey] = process;
      final outputController = StreamController<String>();
      _outputControllers[taskKey] = outputController;

      // Listen to stdout
      process.stdout.transform(utf8.decoder).listen(
        (data) {
          onOutput(data);
          if (!outputController.isClosed) {
            outputController.add(data);
          }
        },
        onError: (error) {
          // Ignore errors
        },
        cancelOnError: false,
      );

      // Listen to stderr
      process.stderr.transform(utf8.decoder).listen(
        (data) {
          onOutput(data);
          if (!outputController.isClosed) {
            outputController.add(data);
          }
        },
        onError: (error) {
          // Ignore errors
        },
        cancelOnError: false,
      );

      // Listen to exit
      process.exitCode.then((exitCode) {
        onExit(exitCode);
        _runningProcesses.remove(taskKey);
        if (!outputController.isClosed) {
          outputController.close();
        }
        _outputControllers.remove(taskKey);
      });
    } catch (e) {
      onOutput('Error starting task: $e\n');
      onExit(-1);
    }
  }

  Future<void> stopTask(Project project, Task task) async {
    final taskKey = TaskUtils.getTaskKey(project, task);
    final process = _runningProcesses[taskKey];

    if (process != null) {
      // Mark as explicitly stopped before killing
      _explicitlyStopped.add(taskKey);

      await _killProcess(process);
      _runningProcesses.remove(taskKey);
      _outputControllers[taskKey]?.close();
      _outputControllers.remove(taskKey);
    }
  }

  Future<void> _killProcess(Process process) async {
    try {
      final pid = process.pid;

      // On Windows, kill the entire process tree to ensure child processes are terminated
      if (Platform.isWindows) {
        try {
          // Use taskkill to kill the process tree
          // /F = force, /T = terminate tree, /PID = process ID
          await Process.run('taskkill', ['/F', '/T', '/PID', pid.toString()]);

          // Wait for process to actually exit
          await process.exitCode.timeout(
            AppConstants.processKillGracePeriod,
            onTimeout: () => -1,
          );
          return;
        } catch (e) {
          // If taskkill fails, fall back to normal kill
        }
      }

      // Unix/fallback: Try graceful termination first (SIGTERM)
      final killed = process.kill(ProcessSignal.sigterm);

      if (killed) {
        // Wait for graceful shutdown
        await process.exitCode.timeout(
          AppConstants.processKillGracePeriod,
          onTimeout: () {
            // Force kill if timeout (SIGKILL)
            process.kill(ProcessSignal.sigkill);
            return process.exitCode;
          },
        );
        return;
      }

      // If SIGTERM didn't work, force kill immediately
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    } catch (e) {
      // If all else fails, try default kill
      try {
        process.kill();
      } catch (_) {
        // Ignore errors - process might already be dead
      }
    }
  }

  bool isTaskRunning(Project project, Task task) {
    final taskKey = TaskUtils.getTaskKey(project, task);
    return _runningProcesses.containsKey(taskKey);
  }

  /// Check if task was explicitly stopped by user and consume the flag
  bool wasTaskExplicitlyStopped(Project project, Task task) {
    final taskKey = TaskUtils.getTaskKey(project, task);
    final wasStopped = _explicitlyStopped.contains(taskKey);
    if (wasStopped) {
      _explicitlyStopped.remove(taskKey);
    }
    return wasStopped;
  }

  Stream<String>? getTaskOutput(Project project, Task task) {
    final taskKey = TaskUtils.getTaskKey(project, task);
    return _outputControllers[taskKey]?.stream;
  }

  Future<void> dispose() async {
    // Kill all running processes
    final killFutures = <Future<void>>[];
    for (final process in _runningProcesses.values) {
      killFutures.add(_killProcess(process));
    }

    // Wait for all processes to terminate (with timeout)
    await Future.wait(killFutures).timeout(
      AppConstants.processKillTotalTimeout,
      onTimeout: () {
        // Force kill any remaining processes
        for (final process in _runningProcesses.values) {
          try {
            process.kill(ProcessSignal.sigkill);
          } catch (_) {
            // Ignore errors
          }
        }
        return <void>[];
      },
    );

    _runningProcesses.clear();

    // Close all output controllers
    for (final controller in _outputControllers.values) {
      await controller.close();
    }
    _outputControllers.clear();
  }
}
