import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../models/project.dart';
import '../models/project_template.dart';
import '../models/result.dart';
import '../utils/json_utils.dart';
import '../utils/process_utils.dart';
import './binary_manager.dart';

class ProjectService {
  final BinaryManager _binaryManager = BinaryManager();



  /// Detect project type and return appropriate default launch directory
  String? _detectDefaultLaunchDirectory(Map<String, dynamic> packageJson) {
    final dependencies = packageJson['dependencies'] as Map<String, dynamic>? ?? {};
    final devDependencies = packageJson['devDependencies'] as Map<String, dynamic>? ?? {};
    final allDeps = {...dependencies, ...devDependencies};

    // Check for Hugo
    if (allDeps.containsKey('hugo-extended')) {
      return 'public';
    }

    // Check for 11ty (Eleventy)
    if (allDeps.containsKey('@11ty/eleventy')) {
      return '_site';
    }

    return null; // Use whole project by default
  }

  /// Initialize bob.directory and devDependencies if not present
  Future<void> _initializeLaunchDirectory(String projectPath, Map<String, dynamic> packageJson) async {
    final bob = packageJson['bob'] as Map<String, dynamic>?;
    bool needsWrite = false;

    // Check if this is a Hugo project
    // First check devDependencies, then fall back to file detection
    final devDeps = packageJson['devDependencies'] as Map<String, dynamic>? ?? {};
    bool isHugo = devDeps.containsKey('hugo-extended');

    if (!isHugo) {
      // Fall back to detecting Hugo config files
      isHugo = await File(path.join(projectPath, 'config.toml')).exists() ||
               await File(path.join(projectPath, 'config.yaml')).exists() ||
               await File(path.join(projectPath, 'hugo.toml')).exists();
    }

    // Initialize launch directory if not set
    if (bob?['directory'] == null) {
      String? defaultDir;
      if (isHugo) {
        defaultDir = 'public';
      } else {
        defaultDir = _detectDefaultLaunchDirectory(packageJson);
      }

      // Set the default if detected
      if (defaultDir != null) {
        if (bob == null) {
          packageJson['bob'] = {'directory': defaultDir};
        } else {
          bob['directory'] = defaultDir;
        }
        needsWrite = true;
      }
    }

    // For Hugo projects, ensure hugo-extended is in devDependencies
    if (isHugo && !devDeps.containsKey('hugo-extended')) {
      devDeps['hugo-extended'] = '^0';
      packageJson['devDependencies'] = devDeps;
      needsWrite = true;
    }

    if (needsWrite) {
      await _writePackageJson(projectPath, packageJson);
    }
  }


  Future<Result<Project>> importProject() async {
    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select project directory',
    );

    // Return immediately if user cancelled
    if (directoryPath == null) {
      return Result.failure('No directory selected');
    }

    try {
      final directory = Directory(directoryPath);

      if (!await directory.exists()) {
        return Result.failure('Directory does not exist: $directoryPath');
      }

      // Bookmark will be created when project is saved via PreferencesService

      final packageJsonPath = path.join(directoryPath, 'package.json');
      final packageJsonFile = File(packageJsonPath);

      if (!await packageJsonFile.exists()) {
        // Create a default package.json
        final defaultPackageJson = {
          'name': path.basename(directoryPath),
          'version': '1.0.0',
          'description': '',
          'scripts': {},
        };

        final jsonString = await compute(encodeJson, defaultPackageJson);
        await packageJsonFile.writeAsString(jsonString);
      }

      final content = await packageJsonFile.readAsString();
      final json = await compute(decodeJson, content);

      // Initialize launch directory based on project type
      await _initializeLaunchDirectory(directoryPath, json);

      final project = Project.fromPackageJson(directoryPath, json);

      return Result.success(project);
    } on FormatException catch (e) {
      return Result.failure('Invalid JSON format: ${e.message}');
    } on FileSystemException catch (e) {
      return Result.failure('File system error: ${e.message}');
    } catch (e) {
      return Result.failure('Failed to import project: ${e.toString()}');
    }
  }

  Future<Result<Project>> createProject({
    required String projectName,
    required String parentDirectory,
    required ProjectType projectType,
    Function(String)? onOutput,
  }) async {
    try {
      final projectPath = path.join(parentDirectory, projectName);
      final directory = Directory(projectPath);

      // Make creation idempotent - if directory exists with package.json, just reload it
      if (await directory.exists()) {
        final packageJsonPath = path.join(projectPath, 'package.json');
        final packageJsonFile = File(packageJsonPath);

        if (await packageJsonFile.exists()) {
          onOutput?.call('Directory already exists with package.json, loading existing project…\n');
          final content = await packageJsonFile.readAsString();
          final json = await compute(decodeJson, content);
          final project = Project.fromPackageJson(projectPath, json);
          return Result.success(project);
        }

        // Directory exists but no package.json, continue with creation
        onOutput?.call('Directory exists, initializing as new project…\n');
      } else {
        await directory.create(recursive: true);
      }

      // For 11ty projects, run bun commands to set up
      if (projectType == ProjectType.eleventy) {
        return await _createEleventyProject(projectPath, projectName, onOutput);
      }

      // For Hugo projects, run hugo commands to set up
      if (projectType == ProjectType.hugo) {
        return await _createHugoProject(projectPath, projectName, onOutput);
      }

      // For other project types, create/update package.json directly
      onOutput?.call('Creating project configuration…\n');

      final packageJsonPath = path.join(projectPath, 'package.json');
      final packageJsonFile = File(packageJsonPath);

      Map<String, dynamic> packageJson;
      if (await packageJsonFile.exists()) {
        onOutput?.call('Updating existing package.json…\n');
        final content = await packageJsonFile.readAsString();
        packageJson = await compute(decodeJson, content);
      } else {
        onOutput?.call('Creating new package.json…\n');
        // Generate from template
        final template = ProjectTemplate(projectType);
        packageJson = template.generatePackageJson(projectName);
      }

      // Ensure name is set
      packageJson['name'] = packageJson['name'] ?? projectName;

      await _writePackageJson(projectPath, packageJson);
      onOutput?.call('✓ Project configured\n');

      final project = Project.fromPackageJson(projectPath, packageJson);

      return Result.success(project);
    } on FileSystemException catch (e) {
      return Result.failure('File system error: ${e.message}');
    } catch (e) {
      return Result.failure('Failed to create project: ${e.toString()}');
    }
  }

  Future<Map<String, String>> _buildEnvironmentWithManagedBinaries() async {
    // Get paths to all managed binaries
    final bunPath = await _binaryManager.getBunPath();

    // Build environment with managed binaries in PATH
    return ProcessUtils.buildEnvironmentWithBinaries([bunPath]);
  }

  Future<int> _runProcessWithOutput(
    String executable,
    List<String> args,
    String workingDirectory,
    Function(String)? onOutput,
  ) async {
    final environment = await _buildEnvironmentWithManagedBinaries();

    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows, // Use shell on Windows to ensure child processes are killed
      environment: environment,
    );

    process.stdout.transform(utf8.decoder).listen((data) => onOutput?.call(data));
    process.stderr.transform(utf8.decoder).listen((data) => onOutput?.call(data));

    return await process.exitCode;
  }

  Future<Map<String, dynamic>> _readPackageJson(String projectPath) async {
    final packageJsonPath = path.join(projectPath, 'package.json');
    final content = await File(packageJsonPath).readAsString();
    return await compute(decodeJson, content);
  }

  Future<void> _writePackageJson(String projectPath, Map<String, dynamic> packageJson) async {
    final packageJsonPath = path.join(projectPath, 'package.json');
    final jsonString = await compute(encodeJson, packageJson);
    await File(packageJsonPath).writeAsString(jsonString);
  }

  // Public methods for package.json manipulation
  Future<Map<String, dynamic>> readPackageJson(String projectPath) async {
    return await _readPackageJson(projectPath);
  }

  Future<void> writePackageJson(String projectPath, Map<String, dynamic> packageJson) async {
    await _writePackageJson(projectPath, packageJson);
  }

  Future<Result<Project>> _createEleventyProject(
    String projectPath,
    String projectName,
    Function(String)? onOutput,
  ) async {
    try {
      onOutput?.call('Creating Eleventy project configuration…\n');

      // Read existing package.json if present, or create new one
      final packageJsonPath = path.join(projectPath, 'package.json');
      final packageJsonFile = File(packageJsonPath);

      Map<String, dynamic> packageJson;
      if (await packageJsonFile.exists()) {
        onOutput?.call('Updating existing package.json…\n');
        final content = await packageJsonFile.readAsString();
        packageJson = await compute(decodeJson, content);
      } else {
        onOutput?.call('Creating new package.json…\n');
        packageJson = {
          'name': projectName,
        };
      }

      // Ensure name is set
      packageJson['name'] = packageJson['name'] ?? projectName;

      // Update devDependencies
      final devDeps = packageJson['devDependencies'] as Map<String, dynamic>? ?? {};
      devDeps['@11ty/eleventy'] = '^3';
      packageJson['devDependencies'] = devDeps;

      // Update scripts (only if not already configured)
      final scripts = packageJson['scripts'] as Map<String, dynamic>? ?? {};
      if (!scripts.containsKey('build')) {
        scripts['build'] = 'bun x @11ty/eleventy';
      }
      if (!scripts.containsKey('start')) {
        scripts['start'] = 'bun x @11ty/eleventy --serve';
      }
      packageJson['scripts'] = scripts;

      // Set launch directory for 11ty
      final bob = packageJson['bob'] as Map<String, dynamic>? ?? {};
      bob['directory'] = '_site';
      packageJson['bob'] = bob;

      await _writePackageJson(projectPath, packageJson);
      onOutput?.call('✓ Project configured\n');
      final project = Project.fromPackageJson(projectPath, packageJson);
      return Result.success(project);
    } catch (e) {
      return Result.failure('Failed to create 11ty project: ${e.toString()}');
    }
  }

  Future<Result<Project>> _createHugoProject(
    String projectPath,
    String projectName,
    Function(String)? onOutput,
  ) async {
    try {
      // Create package.json first with hugo-extended
      onOutput?.call('Creating package.json…\n');
      final packageJsonPath = path.join(projectPath, 'package.json');
      final packageJsonFile = File(packageJsonPath);

      final Map<String, dynamic> packageJson = {
        'name': projectName,
        'devDependencies': {
          'hugo-extended': '^0',
        },
      };

      await _writePackageJson(projectPath, packageJson);

      // Install hugo-extended
      onOutput?.call('Installing hugo-extended…\n');
      final bunPath = await _binaryManager.getBunPath();
      final installExitCode = await _runProcessWithOutput(
        bunPath,
        ['install'],
        projectPath,
        onOutput,
      );

      if (installExitCode != 0) {
        return Result.failure('Failed to install hugo-extended (exit code: $installExitCode)');
      }

      // Create Hugo site using bunx
      onOutput?.call('Creating Hugo site…\n');
      final exitCode = await _runProcessWithOutput(
        bunPath,
        ['x', 'hugo-extended', 'new', 'site', '.', '--force'],
        projectPath,
        onOutput,
      );

      if (exitCode != 0) {
        return Result.failure('Failed to create Hugo site (exit code: $exitCode)');
      }

      onOutput?.call('\nConfiguring project…\n');

      // Read the package.json again (Hugo might have modified it)
      if (await packageJsonFile.exists()) {
        onOutput?.call('Updating package.json…\n');
        final content = await packageJsonFile.readAsString();
        final updatedPackageJson = await compute(decodeJson, content);

        // Ensure devDependencies still has hugo-extended
        updatedPackageJson['devDependencies'] ??= {};
        updatedPackageJson['devDependencies']['hugo-extended'] = '^0';

        packageJson.clear();
        packageJson.addAll(updatedPackageJson);
      }

      // Ensure name is set
      packageJson['name'] = packageJson['name'] ?? projectName;

      // Update scripts
      final scripts = packageJson['scripts'] as Map<String, dynamic>? ?? {};
      scripts['build'] = 'hugo';
      scripts['start'] = 'hugo server';
      packageJson['scripts'] = scripts;

      // Set launch directory for Hugo
      final bob = packageJson['bob'] as Map<String, dynamic>? ?? {};
      bob['directory'] = 'public';
      packageJson['bob'] = bob;

      await _writePackageJson(projectPath, packageJson);
      onOutput?.call('✓ Project configured\n');

      final project = Project.fromPackageJson(projectPath, packageJson);
      return Result.success(project);
    } catch (e) {
      return Result.failure('Failed to create Hugo project: ${e.toString()}');
    }
  }

  Future<List<Project>> scanDirectory(String directoryPath) async {
    final projects = <Project>[];
    final directory = Directory(directoryPath);

    if (!await directory.exists()) {
      return projects;
    }

    try {
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File && path.basename(entity.path) == 'package.json') {
          try {
            final content = await entity.readAsString();
            final json = await compute(decodeJson, content);
            final projectPath = path.dirname(entity.path);
            projects.add(Project.fromPackageJson(projectPath, json));
          } catch (e) {
            // Skip invalid package.json files
          }
        }
      }
    } catch (e) {
      // Return partial results if directory scan fails
    }

    return projects;
  }

  Future<Result<Project>> reloadProject(Project project) async {
    try {
      final packageJsonPath = path.join(project.path, 'package.json');
      final packageJsonFile = File(packageJsonPath);

      if (!await packageJsonFile.exists()) {
        return Result.failure('package.json not found at ${project.path}');
      }

      final content = await packageJsonFile.readAsString();
      final json = await compute(decodeJson, content);

      final reloadedProject = Project.fromPackageJson(project.path, json);

      return Result.success(reloadedProject);
    } on FormatException catch (e) {
      return Result.failure('Invalid JSON format: ${e.message}');
    } on FileSystemException catch (e) {
      return Result.failure('File system error: ${e.message}');
    } catch (e) {
      return Result.failure('Failed to reload project: ${e.toString()}');
    }
  }



  Future<Result<Project>> addSite(
    Project project,
    Site site,
  ) async {
    try {
      final packageJson = await _readPackageJson(project.path);

      // Get or create bob section
      final bob = packageJson['bojb'] as Map<String, dynamic>? ?? {};
      packageJson['bob'] = bob;

      // Get or create targets section
      final sites = bob['sites'] as Map<String, dynamic>? ?? {};
      bob['sites'] = sites;

      // Check if target already exists
      if (sites.containsKey(site.name)) {
        return Result.failure('A launch site named "${site.name}" already exists');
      }

      // Add the new target
      sites[site.name] = {
        'domain': site.domain,
        'service': site.service,
      };

      // Write back to package.json
      await _writePackageJson(project.path, packageJson);

      // Reload and return the updated project
      return await reloadProject(project);
    } on FileSystemException catch (e) {
      return Result.failure('File system error: ${e.message}');
    } catch (e) {
      return Result.failure('Failed to add site: ${e.toString()}');
    }
  }
}
