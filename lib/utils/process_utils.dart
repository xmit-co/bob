import 'dart:io';
import 'package:path/path.dart' as path;

/// Utility functions for process management across platforms
class ProcessUtils {
  /// Open a directory in the system's file explorer
  /// - Windows: explorer
  /// - macOS: open
  /// - Linux: xdg-open
  static Future<void> openInFileExplorer(String directoryPath) async {
    final String executable;
    final List<String> args;

    if (Platform.isWindows) {
      executable = 'explorer';
      args = [directoryPath];
    } else if (Platform.isMacOS) {
      executable = 'open';
      args = [directoryPath];
    } else {
      // Linux
      executable = 'xdg-open';
      args = [directoryPath];
    }

    await Process.start(executable, args, runInShell: false);
  }

  /// Get the path separator for the current platform
  static String get pathSeparator => Platform.isWindows ? ';' : ':';

  /// Build environment with managed binary paths prepended to PATH
  ///
  /// This creates a copy of the current environment and prepends the
  /// directories of the provided binary paths to the PATH variable.
  ///
  /// Example:
  /// ```dart
  /// final env = ProcessUtils.buildEnvironmentWithBinaries([
  ///   '/path/to/hugo/hugo',
  ///   '/path/to/bun/bun'
  /// ]);
  /// ```
  static Map<String, String> buildEnvironmentWithBinaries(List<String> binaryPaths) {
    final environment = Map<String, String>.from(Platform.environment);
    final currentPath = environment['PATH'] ?? '';

    // Extract directories from binary paths and join with path separator
    final directories = binaryPaths
        .map((binaryPath) => path.dirname(binaryPath))
        .join(pathSeparator);

    // Prepend managed binary directories to PATH
    environment['PATH'] = '$directories$pathSeparator$currentPath';

    return environment;
  }

  /// Check if the current platform is ARM64
  static bool isArm64() {
    // Note: This is a simplified check. For production, you might want
    // to use dart:ffi Abi.current() or check environment variables
    return false; // Placeholder - actual implementation in BinaryManager
  }

  ProcessUtils._();
}
