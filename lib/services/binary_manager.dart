import 'dart:io';
import 'dart:ffi';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import '../config/constants.dart';

enum BinaryType { bun }

class BinaryConfig {
  final String version;
  final String name;
  final String Function(String version, bool isArm) getDownloadUrl;
  final String archiveExtension;

  const BinaryConfig({
    required this.version,
    required this.name,
    required this.getDownloadUrl,
    required this.archiveExtension,
  });
}

class BinaryManager {
  static const String bunVersion = AppConstants.bunVersion;

  static final Map<BinaryType, String?> _cachedPaths = {
    BinaryType.bun: null,
  };

  static final Map<BinaryType, BinaryConfig> _configs = {
    BinaryType.bun: BinaryConfig(
      version: bunVersion,
      name: 'bun',
      archiveExtension: 'zip',
      getDownloadUrl: (version, isArm) {
        if (Platform.isWindows) {
          return isArm
              ? 'https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-windows-aarch64.zip'
              : 'https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-windows-x64.zip';
        } else if (Platform.isMacOS) {
          return isArm
              ? 'https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-darwin-aarch64.zip'
              : 'https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-darwin-x64.zip';
        } else {
          return isArm
              ? 'https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-linux-aarch64.zip'
              : 'https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-linux-x64.zip';
        }
      },
    ),
  };

  Future<String> _getBinariesDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final binDir = Directory(path.join(appDir.path, 'binaries'));
    if (!await binDir.exists()) {
      await binDir.create(recursive: true);
    }
    return binDir.path;
  }

  bool _isArm64() {
    final abi = Abi.current();
    return abi == Abi.macosArm64 || abi == Abi.linuxArm64 || abi == Abi.windowsArm64;
  }

  Future<String> _getBinaryPath(BinaryType type) async {
    final cachedPath = _cachedPaths[type];
    if (cachedPath != null && await File(cachedPath).exists()) {
      return cachedPath;
    }

    final config = _configs[type]!;
    final binDir = await _getBinariesDirectory();
    final binaryDir = path.join(binDir, '${config.name}-${config.version}');

    final executableName = Platform.isWindows ? '${config.name}.exe' : config.name;
    final executablePath = path.join(binaryDir, executableName);

    if (await File(executablePath).exists()) {
      _cachedPaths[type] = executablePath;
      return executablePath;
    }

    // Download binary
    await _downloadBinary(type, binaryDir);
    _cachedPaths[type] = executablePath;
    return executablePath;
  }

  Future<String> getBunPath() async {
    return _getBinaryPath(BinaryType.bun);
  }

  Future<void> _downloadBinary(BinaryType type, String targetDir) async {
    final config = _configs[type]!;
    final dir = Directory(targetDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final isArm = _isArm64();
    final downloadUrl = config.getDownloadUrl(config.version, isArm);
    final tempFile = path.join(targetDir, '${config.name}.${config.archiveExtension}');

    // Download
    final response = await http.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download ${config.name}: ${response.statusCode}');
    }

    await File(tempFile).writeAsBytes(response.bodyBytes);

    // Extract
    await _extractArchive(tempFile, targetDir, config);

    // Clean up
    await File(tempFile).delete();
  }

  Future<void> _extractArchive(String archivePath, String targetDir, BinaryConfig config) async {
    final executableName = Platform.isWindows ? '${config.name}.exe' : config.name;

    if (config.archiveExtension == 'zip') {
      final archive = ZipDecoder().decodeBytes(await File(archivePath).readAsBytes());
      await _extractBinaryFromArchive(archive.files, targetDir, executableName);
    } else if (config.archiveExtension == 'tar.gz') {
      final bytes = await File(archivePath).readAsBytes();
      final archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      await _extractBinaryFromArchive(archive.files, targetDir, executableName);
    }
  }

  Future<void> _extractBinaryFromArchive(List<ArchiveFile> files, String targetDir, String executableName) async {
    for (final file in files) {
      final filename = file.name;
      // Match the executable name at the end of the path (handles nested directories)
      if (filename.endsWith('/$executableName') || filename == executableName) {
        final outFile = File(path.join(targetDir, executableName));
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);

        // Make executable on Unix
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', outFile.path]);
        }
        break;
      }
    }
  }

  void clearCache() {
    _cachedPaths[BinaryType.bun] = null;
  }
}
