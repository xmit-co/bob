import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:cbor/cbor.dart';
import 'package:thirds/blake3.dart';
import '../models/project.dart';
import 'task_service.dart';

class LaunchService {
  final TaskService _taskService = TaskService();
  static const String _apiPrefix = '/api/0';
  final Map<String, bool> _cancellationTokens = {};
  final http.Client _httpClient = http.Client();
  static const Duration _httpTimeout = Duration(seconds: 30);

  /// Normalize service domain to full URL with https://
  String _normalizeServiceUrl(String service) {
    if (service.startsWith('http://') || service.startsWith('https://')) {
      return service;
    }
    return 'https://$service';
  }

  /// Discover the hosting provider's protocol and base URL
  /// Returns a record of (protocol, baseUrl)
  Future<({List<String> protocols, String baseUrl})> _discoverProtocol(
    String serviceDomain,
  ) async {
    final serviceUrl = _normalizeServiceUrl(serviceDomain);
    final wellKnownUrl = '$serviceUrl/.well-known/web-publication-protocol';

    try {
      final response = await _httpClient
          .get(Uri.parse(wellKnownUrl))
          .timeout(_httpTimeout);

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to discover protocol: HTTP ${response.statusCode}',
        );
      }

      // Parse JSON response
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Failed to parse protocol discovery response: $e');
      }

      final protocolsRaw = json['protocols'];
      final List<String> protocols;

      if (protocolsRaw is List) {
        protocols = protocolsRaw.map((e) => e.toString()).toList();
      } else {
        protocols = [];
      }

      if (protocols.isEmpty) {
        throw Exception(
          'Protocols field missing or empty in discovery response',
        );
      }

      // Validate protocol
      if (!protocols.contains('xmit/0')) {
        throw Exception(
          'Unknown protocols: ${protocols.join(', ')}. Expected xmit/0',
        );
      }

      final baseUrl = json['url'] as String?;

      if (baseUrl == null || baseUrl.isEmpty) {
        throw Exception(
          'URL field missing or empty in discovery response',
        );
      }

      return (protocols: protocols, baseUrl: baseUrl);
    } catch (e) {
      throw Exception('Protocol discovery failed: $e');
    }
  }

  /// Cancel a launch by its identifier
  void cancelLaunch(String launchId) {
    _cancellationTokens[launchId] = true;
  }

  /// Check if launch is cancelled
  bool _isCancelled(String launchId) {
    return _cancellationTokens[launchId] == true;
  }

  /// Make an HTTP request with timeout and cancellation support
  Future<http.Response> _makeRequest(
    String launchId,
    Future<http.Response> Function() requestFn,
  ) async {
    // Check cancellation before starting request
    if (_isCancelled(launchId)) {
      throw Exception('Launch cancelled');
    }

    final responseFuture = requestFn();

    // Poll for cancellation while waiting for response
    final cancelCheckFuture = Future.doWhile(() async {
      if (_isCancelled(launchId)) {
        return false; // Stop polling
      }
      await Future.delayed(const Duration(milliseconds: 100));
      return true; // Continue polling
    });

    try {
      // Race between response, timeout, and cancellation
      final response =
          await Future.any([
            responseFuture,
            cancelCheckFuture.then(
              (_) => throw Exception('Launch cancelled'),
            ),
          ]).timeout(
            _httpTimeout,
            onTimeout: () {
              throw TimeoutException(
                'Request timed out after ${_httpTimeout.inSeconds} seconds',
              );
            },
          );

      return response;
    } catch (e) {
      // If cancelled, close the HTTP client to abort in-flight requests
      if (_isCancelled(launchId)) {
        _httpClient.close();
      }
      rethrow;
    }
  }

  /// Helper to track current step for logging
  LaunchStep? _currentStep;

  /// Map of file hashes to their content for missing parts upload
  final Map<String, Uint8List> _fileContents = {};

  /// Update step and add log message
  void _logToStep(String message, Function(LaunchStep)? onStepUpdate) {
    if (_currentStep != null && onStepUpdate != null) {
      _currentStep = _currentStep!.addLog(message);
      onStepUpdate(_currentStep!);
    }
  }

  /// Log errors, warnings, and messages from a response
  /// Returns true if there was a "requires a team ID suffix" error
  bool _logResponseMessages({
    required List<String> errors,
    required List<String> warnings,
    required List<String> messages,
    required Function(LaunchStep)? onStepUpdate,
  }) {
    bool hasTeamIdError = false;

    for (final error in errors) {
      if (error.contains('requires a team ID')) {
        hasTeamIdError = true;
      } else {
        _logToStep('❌ $error', onStepUpdate);
      }
    }
    for (final warning in warnings) {
      _logToStep('⚠️  $warning', onStepUpdate);
    }
    for (final message in messages) {
      _logToStep('ℹ️  $message', onStepUpdate);
    }

    return hasTeamIdError;
  }

  /// Handle team selection when team ID error occurs
  /// Returns the selected team ID, or null if cancelled/unavailable
  Future<String?> _handleTeamSelection(
    String launchId,
    String serviceUrl,
    String authKey,
    Function(LaunchStep)? onStepUpdate,
    Future<TeamSelectionResult> Function(TeamListResponse)? onTeamSelectionRequired,
  ) async {
    if (onTeamSelectionRequired == null) {
      _logToStep('❌ Team ID required for this domain', onStepUpdate);
      _logToStep(
        'Configure domain with team suffix (e.g., example.com@team-id)',
        onStepUpdate,
      );
      _logToStep(
        'Or provide onTeamSelectionRequired callback for interactive selection',
        onStepUpdate,
      );
      return null;
    }

    // Loop to support refresh and create
    while (true) {
      // Check if launch was cancelled
      if (_isCancelled(launchId)) {
        _logToStep('Team selection cancelled', onStepUpdate);
        return null;
      }

      _logToStep('Fetching available teams', onStepUpdate);
      try {
        final teamListResponse = await listTeams(serviceUrl, authKey);

        // Check cancellation after async operation
        if (_isCancelled(launchId)) {
          _logToStep('Team selection cancelled', onStepUpdate);
          return null;
        }

        if (teamListResponse.teams.isEmpty) {
          _logToStep('No teams found for this account', onStepUpdate);
          _logToStep('Create a team at ${teamListResponse.manageUrl}', onStepUpdate);
        } else {
          _logToStep('Found ${teamListResponse.teams.length} team(s)', onStepUpdate);
        }

        final result = await onTeamSelectionRequired(teamListResponse);

        // Check cancellation after user interaction
        if (_isCancelled(launchId)) {
          _logToStep('Team selection cancelled', onStepUpdate);
          return null;
        }

        // Handle different result types using pattern matching
        switch (result) {
          case TeamSelected(teamId: final teamId):
            return teamId;
          case RefreshTeamList():
            _logToStep('Refreshing team list', onStepUpdate);
            continue; // Loop again to refetch teams
          case CreateNewTeam():
            _logToStep('Please create a team at ${teamListResponse.manageUrl}', onStepUpdate);
            _logToStep('Then select "Refresh" to see the new team', onStepUpdate);
            continue; // Loop again to refetch teams
          case TeamSelectionCancelled():
            return null;
        }
      } catch (e) {
        _logToStep('Failed to fetch teams: ${e.toString()}', onStepUpdate);
        return null;
      }
    }
  }

  /// Launch a project to a target using the xmit protocol
  Future<LaunchResult> launch({
    required String projectPath,
    required Project project,
    required Site target,
    required String authKey,
    Function(LaunchStep)? onStepUpdate,
    Function(Task)? onTaskUpdate,
    Future<TeamSelectionResult> Function(TeamListResponse)? onTeamSelectionRequired,
  }) async {
    // Create unique launch ID
    final launchId = '${project.path}:${target.name}';
    _cancellationTokens[launchId] = false;
    _currentStep = null;
    String? teamId; // Track selected team ID

    try {
      // Step 0: Run build task if it exists
      final buildTask = project.tasks.cast<Task?>().firstWhere(
        (task) => task?.name == 'build',
        orElse: () => null,
      );

      if (buildTask != null) {
        if (_isCancelled(launchId)) {
          return LaunchResult.failure('Launch cancelled');
        }

        _currentStep = LaunchStep(
          title: 'Running build task',
          status: LaunchStepStatus.running,
        );
        onStepUpdate?.call(_currentStep!);
        final buildSuccess = await _runBuildTask(
          project,
          buildTask,
          null,
          onTaskUpdate,
        );

        if (_isCancelled(launchId)) {
          return LaunchResult.failure('Launch cancelled');
        }

        if (!buildSuccess) {
          _currentStep = _currentStep!.copyWith(
            status: LaunchStepStatus.failed,
            message: 'Build task failed',
          );
          onStepUpdate?.call(_currentStep!);
          return LaunchResult.failure('Build task failed');
        }
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.completed,
          endTime: DateTime.now(),
        );
        onStepUpdate?.call(_currentStep!);
      }

      if (_isCancelled(launchId)) {
        return LaunchResult.failure('Launch cancelled');
      }

      // Step 1: Discover protocol and base URL
      _currentStep = LaunchStep(
        title: 'Discovering protocol',
        status: LaunchStepStatus.running,
      );
      onStepUpdate?.call(_currentStep!);
      _logToStep('Discovering protocol from ${target.service}', onStepUpdate);

      String serviceUrl;
      try {
        final discovery = await _discoverProtocol(target.service);
        serviceUrl = discovery.baseUrl;
        _logToStep('✅ Protocols: ${discovery.protocols.join(', ')}', onStepUpdate);
        _logToStep('✅ Base URL: $serviceUrl', onStepUpdate);
      } catch (e) {
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.failed,
          message: e.toString(),
        );
        onStepUpdate?.call(_currentStep!);
        return LaunchResult.failure('Protocol discovery failed: $e');
      }

      if (_isCancelled(launchId)) {
        return LaunchResult.failure('Launch cancelled');
      }

      _currentStep = _currentStep!.copyWith(
        status: LaunchStepStatus.completed,
        endTime: DateTime.now(),
      );
      onStepUpdate?.call(_currentStep!);

      // Step 2: Create bundle node structure from project files
      _currentStep = LaunchStep(
        title: 'Creating bundle',
        status: LaunchStepStatus.running,
      );
      onStepUpdate?.call(_currentStep!);
      _fileContents.clear(); // Clear previous contents
      final bundleNode = await _createBundleNode(projectPath, project, _fileContents);

      if (_isCancelled(launchId)) {
        return LaunchResult.failure('Launch cancelled');
      }

      // Encode bundle as CBOR
      final bundleBytes = Uint8List.fromList(cbor.encode(bundleNode));
      final bundleHashBytes = Uint8List.fromList(blake3(bundleBytes));
      _currentStep = _currentStep!.copyWith(
        status: LaunchStepStatus.completed,
        endTime: DateTime.now(),
      );
      onStepUpdate?.call(_currentStep!);

      // Step 3: Suggest bundle to check if already present
      _currentStep = LaunchStep(
        title: 'Suggesting bundle',
        status: LaunchStepStatus.running,
      );
      onStepUpdate?.call(_currentStep!);

      if (_isCancelled(launchId)) {
        return LaunchResult.failure('Launch cancelled');
      }

      final suggestUrl = '$serviceUrl$_apiPrefix/suggest';

      var suggestResponse = await _suggestBundle(
        launchId,
        suggestUrl,
        authKey,
        target.domain,
        bundleHashBytes,
        teamId,
      );

      _logToStep('Server responded: ${suggestResponse.statusCode}', onStepUpdate);

      // Log any errors, warnings, or messages from the suggest response
      var hasTeamIdError = _logResponseMessages(
        errors: suggestResponse.errors,
        warnings: suggestResponse.warnings,
        messages: suggestResponse.messages,
        onStepUpdate: onStepUpdate,
      );

      // If there's a team ID error, prompt for team selection and retry
      if (hasTeamIdError) {
        _logToStep('🔐 Domain requires team ID authentication', onStepUpdate);

        // Pause the current step while waiting for team selection
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.paused,
          message: 'Waiting for team selection',
        );
        onStepUpdate?.call(_currentStep!);

        teamId = await _handleTeamSelection(
          launchId,
          serviceUrl,
          authKey,
          onStepUpdate,
          onTeamSelectionRequired,
        );

        if (teamId == null || teamId.isEmpty) {
          _currentStep = _currentStep!.copyWith(
            status: LaunchStepStatus.failed,
            message: 'Team selection cancelled or unavailable',
          );
          onStepUpdate?.call(_currentStep!);

          // Provide helpful message based on whether callback exists
          if (onTeamSelectionRequired == null) {
            return LaunchResult.failure(
              'This domain requires a team ID.',
            );
          } else {
            return LaunchResult.failure(
              'Team selection was cancelled. Launch cannot proceed without a team ID.',
            );
          }
        }

        // Resume the step and retry suggest with team ID
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.running,
          message: null,
        );
        onStepUpdate?.call(_currentStep!);

        _logToStep('✅ Using team: $teamId', onStepUpdate);
        _logToStep('Retrying bundle suggestion', onStepUpdate);

        suggestResponse = await _suggestBundle(
          launchId,
          suggestUrl,
          authKey,
          target.domain,
          bundleHashBytes,
          teamId,
        );

        _logToStep('Server responded: ${suggestResponse.statusCode}', onStepUpdate);
        hasTeamIdError = _logResponseMessages(
          errors: suggestResponse.errors,
          warnings: suggestResponse.warnings,
          messages: suggestResponse.messages,
          onStepUpdate: onStepUpdate,
        );

        if (hasTeamIdError) {
          _currentStep = _currentStep!.copyWith(
            status: LaunchStepStatus.failed,
            message: 'Team authentication failed',
          );
          onStepUpdate?.call(_currentStep!);
          return LaunchResult.failure(
            'Team ID authentication failed. Please verify your team ID is correct.',
          );
        }

        _logToStep('✅ Team authentication successful', onStepUpdate);
      }

      if (_isCancelled(launchId)) {
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.failed,
          message: 'Cancelled',
        );
        onStepUpdate?.call(_currentStep!);
        return LaunchResult.failure('Launch cancelled');
      }

      // Complete suggest step with appropriate message
      final suggestMessage = suggestResponse.present
          ? (suggestResponse.missing.isNotEmpty
              ? 'Bundle present, ${suggestResponse.missing.length} missing parts'
              : 'Bundle already present on server')
          : (suggestResponse.missing.isNotEmpty
              ? '${suggestResponse.missing.length} missing parts'
              : null);

      onStepUpdate?.call(
        LaunchStep(
          title: 'Suggesting bundle',
          status: LaunchStepStatus.completed,
          message: suggestMessage,
        ),
      );

      // Upload missing parts if any were reported
      if (suggestResponse.missing.isNotEmpty) {
        _currentStep = LaunchStep(
          title: 'Uploading missing parts',
          status: LaunchStepStatus.running,
          message: '${suggestResponse.missing.length} parts',
        );
        onStepUpdate?.call(_currentStep!);
        final missingUrl = '$serviceUrl$_apiPrefix/missing';
        await _uploadMissingParts(
          launchId,
          missingUrl,
          authKey,
          target.domain,
          suggestResponse.missing,
          _fileContents,
          teamId,
          onStepUpdate,
        );
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.completed,
          endTime: DateTime.now(),
        );
        onStepUpdate?.call(_currentStep!);
      }

      // If bundle is present (with or without missing parts now uploaded), finalize
      if (suggestResponse.present) {
        _currentStep = LaunchStep(
          title: 'Finalizing launch',
          status: LaunchStepStatus.running,
        );
        onStepUpdate?.call(_currentStep!);
        final finalizeUrl = '$serviceUrl$_apiPrefix/finalize';
        final finalizeResponse = await _finalizeLaunch(
          launchId,
          finalizeUrl,
          authKey,
          target.domain,
          bundleHashBytes,
          teamId,
        );

        // Log finalize response messages
        final alreadyPresentHasTeamIdError = _logResponseMessages(
          errors: finalizeResponse.errors,
          warnings: finalizeResponse.warnings,
          messages: finalizeResponse.messages,
          onStepUpdate: onStepUpdate,
        );

        // Handle team ID error in finalization (shouldn't happen if suggest worked)
        if (alreadyPresentHasTeamIdError) {
          _currentStep = _currentStep!.copyWith(
            status: LaunchStepStatus.failed,
            message: 'Team authentication required for finalization',
          );
          onStepUpdate?.call(_currentStep!);
          return LaunchResult.failure(
            'Team ID required for finalization. This should not happen if '
            'suggestion succeeded. Please report this issue.',
          );
        }

        // Check if finalization actually succeeded
        if (!finalizeResponse.success) {
          _currentStep = _currentStep!.copyWith(
            status: LaunchStepStatus.failed,
            message: 'Failed',
          );
          onStepUpdate?.call(_currentStep!);
          return LaunchResult.failure('Finalization failed');
        }

        // Mark step as completed (messages already logged)
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.completed,
          endTime: DateTime.now(),
        );
        onStepUpdate?.call(_currentStep!);

        return LaunchResult.success(
          'Launch complete',
        );
      }

      // Step 4: Upload bundle
      _currentStep = LaunchStep(
        title: 'Uploading bundle',
        status: LaunchStepStatus.running,
      );
      onStepUpdate?.call(_currentStep!);

      if (_isCancelled(launchId)) {
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.failed,
          message: 'Cancelled',
        );
        onStepUpdate?.call(_currentStep!);
        return LaunchResult.failure('Launch cancelled');
      }

      final uploadUrl = '$serviceUrl$_apiPrefix/bundle';
      final bundleSizeKb = (bundleBytes.length / 1024).toStringAsFixed(2);
      _logToStep('Uploading ${bundleSizeKb}KB bundle', onStepUpdate);

      final uploadResponse = await _uploadBundle(
        launchId,
        uploadUrl,
        authKey,
        target.domain,
        bundleBytes,
        teamId,
      );

      _logToStep('Upload complete', onStepUpdate);

      // Log upload response messages
      final uploadHasTeamIdError = _logResponseMessages(
        errors: uploadResponse.errors,
        warnings: uploadResponse.warnings,
        messages: uploadResponse.messages,
        onStepUpdate: onStepUpdate,
      );

      // Handle team ID error during upload (shouldn't happen if suggest worked)
      if (uploadHasTeamIdError) {
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.failed,
          message: 'Team authentication required for upload',
        );
        onStepUpdate?.call(_currentStep!);
        return LaunchResult.failure(
          'Team ID required for upload. This should not happen if '
          'suggestion succeeded. Please report this issue.',
        );
      }

      if (_isCancelled(launchId)) {
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.failed,
          message: 'Cancelled',
        );
        onStepUpdate?.call(_currentStep!);
        return LaunchResult.failure('Launch cancelled');
      }

      if (!uploadResponse.success) {
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.failed,
          message: 'Failed',
        );
        onStepUpdate?.call(_currentStep!);
        return LaunchResult.failure('Upload failed');
      }
      onStepUpdate?.call(
        LaunchStep(
          title: 'Uploading bundle',
          status: LaunchStepStatus.completed,
        ),
      );

      // Step 5: Upload missing parts if any
      if (uploadResponse.missing.isNotEmpty) {
        _currentStep = LaunchStep(
          title: 'Uploading missing parts',
          status: LaunchStepStatus.running,
          message: '${uploadResponse.missing.length} parts',
        );
        onStepUpdate?.call(_currentStep!);
        final missingUrl = '$serviceUrl$_apiPrefix/missing';
        await _uploadMissingParts(
          launchId,
          missingUrl,
          authKey,
          target.domain,
          uploadResponse.missing,
          _fileContents,
          teamId,
          onStepUpdate,
        );
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.completed,
          endTime: DateTime.now(),
        );
        onStepUpdate?.call(_currentStep!);
      }

      // Step 6: Finalize launch
      _currentStep = LaunchStep(
        title: 'Finalizing launch',
        status: LaunchStepStatus.running,
      );
      onStepUpdate?.call(_currentStep!);
      _logToStep('Requesting finalization', onStepUpdate);

      final finalizeUrl = '$serviceUrl$_apiPrefix/finalize';
      final finalizeResponse = await _finalizeLaunch(
        launchId,
        finalizeUrl,
        authKey,
        target.domain,
        uploadResponse.id,
        teamId,
      );

      _logToStep('Launch finalized', onStepUpdate);

      // Log finalize response messages
      final finalizeHasTeamIdError = _logResponseMessages(
        errors: finalizeResponse.errors,
        warnings: finalizeResponse.warnings,
        messages: finalizeResponse.messages,
        onStepUpdate: onStepUpdate,
      );

      // Handle team ID error during finalize (shouldn't happen if suggest worked)
      if (finalizeHasTeamIdError) {
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.failed,
          message: 'Team authentication required for finalization',
        );
        onStepUpdate?.call(_currentStep!);
        return LaunchResult.failure(
          'Team ID required for finalization. This should not happen if '
          'suggestion succeeded. Please report this issue.',
        );
      }

      if (!finalizeResponse.success) {
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.failed,
          message: 'Failed',
        );
        onStepUpdate?.call(_currentStep!);
        return LaunchResult.failure('Finalization failed');
      }

      // Mark step as completed (messages already logged)
      _currentStep = _currentStep!.copyWith(
        status: LaunchStepStatus.completed,
        endTime: DateTime.now(),
      );
      onStepUpdate?.call(_currentStep!);

      return LaunchResult.success(
        'Successfully launched to ${target.domain}',
      );
    } catch (e) {
      // Update current step status if it exists
      if (_currentStep != null) {
        _currentStep = _currentStep!.copyWith(
          status: LaunchStepStatus.failed,
          message: e.toString(),
        );
        onStepUpdate?.call(_currentStep!);
      }
      return LaunchResult.failure('Launch failed: ${e.toString()}');
    } finally {
      // Clean up cancellation token
      _cancellationTokens.remove(launchId);
    }
  }

  /// Run build task and wait for completion
  Future<bool> _runBuildTask(
    Project project,
    Task buildTask,
    Function(String)? onProgress,
    Function(Task)? onTaskUpdate,
  ) async {
    final completer = Completer<bool>();

    _taskService.startTask(
      project,
      buildTask,
      (output) {
        // Optionally relay output to progress callback
        // onProgress?.call(output);
      },
      (code) {
        completer.complete(code == 0);
      },
    );

    return await completer.future;
  }

  /// Create a bundle node structure from project files
  /// Uses configured directory from project, or whole project if not specified
  /// Also populates the fileContents map with hash -> content mapping
  Future<CborValue> _createBundleNode(
    String projectPath,
    Project project,
    Map<String, Uint8List> fileContents,
  ) async {
    // Determine which directory to bundle based on project configuration
    String bundleDirectory = projectPath;

    if (project.launchDirectory != null) {
      // Use configured directory from bob.directory in package.json
      bundleDirectory = path.join(projectPath, project.launchDirectory!);

      // Verify the configured directory exists
      if (!await Directory(bundleDirectory).exists()) {
        throw Exception(
          'Configured launch directory "${project.launchDirectory}" does not exist. '
          'Please build your project or update bob.directory in package.json.',
        );
      }
    }
    // If no directory configured, use whole project

    final directory = Directory(bundleDirectory);
    final files = <String, Uint8List>{};

    // Read all files into memory (excluding .git only, like xmit)
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final relativePath = path.relative(entity.path, from: bundleDirectory);

        // Skip .git directory only (exactly like xmit does)
        if (relativePath.startsWith('.git${path.separator}') ||
            relativePath == '.git') {
          continue;
        }

        final bytes = await entity.readAsBytes();
        files[relativePath] = bytes;
      }
    }

    // Build hierarchical node structure as per xmit protocol
    // Node structure: { 1: children_map, 2: file_hash }
    // where children_map is: { "name": child_node }

    // Helper to build tree recursively
    Map<String, dynamic> buildTree(Map<String, Uint8List> files) {
      final tree = <String, dynamic>{};

      for (final entry in files.entries) {
        final filePath = entry.key;
        final fileBytes = entry.value;
        final parts = path.split(filePath);

        var current = tree;
        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          final isLastPart = i == parts.length - 1;

          if (isLastPart) {
            // File node: store bytes for later hash conversion
            current[part] = fileBytes;
          } else {
            // Directory node: ensure it exists
            current[part] ??= <String, dynamic>{};
            current = current[part] as Map<String, dynamic>;
          }
        }
      }

      return tree;
    }

    // Convert tree to CBOR nodes
    CborValue treeToNode(Map<String, dynamic> tree) {
      final children = <String, CborValue>{};

      for (final entry in tree.entries) {
        final name = entry.key;
        final value = entry.value;

        if (value is Uint8List) {
          // File node with hash at key 2 (BLAKE3 hash)
          final hash = Uint8List.fromList(blake3(value));
          final hashHex = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

          // Store content by hash for missing parts upload
          fileContents[hashHex] = value;

          children[name] = CborMap({
            CborSmallInt(2): CborBytes(hash),
          });
        } else if (value is Map<String, dynamic>) {
          // Directory node with children at key 1
          children[name] = CborMap({CborSmallInt(1): treeToNode(value)});
        }
      }

      return CborMap(children.map((k, v) => MapEntry(CborString(k), v)));
    }

    final tree = buildTree(files);
    final rootChildrenCbor = treeToNode(tree);

    // Create root node with children at key 1
    return CborMap({CborSmallInt(1): rootChildrenCbor});
  }

  /// Parse a CBOR list of strings from response
  List<String> _parseCborStringList(CborMap decoded, int key) {
    final value = decoded[CborSmallInt(key)];
    if (value == null) return [];

    if (value is CborList) {
      return value
          .map((item) => item is CborString ? item.toString() : '')
          .where((s) => s.isNotEmpty)
          .toList();
    }

    return [];
  }

  /// Parse a CBOR list of byte arrays (hashes) and convert to hex strings
  List<String> _parseCborHashList(CborMap decoded, int key) {
    final value = decoded[CborSmallInt(key)];
    if (value == null) return [];

    if (value is CborList) {
      return value
          .whereType<CborBytes>()
          .map((item) {
            final bytes = item.bytes;
            return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          })
          .toList();
    }

    return [];
  }

  /// Parse CBOR bytes from response
  Uint8List _parseCborBytes(CborMap decoded, int key) {
    final value = decoded[CborSmallInt(key)];
    if (value is CborBytes) {
      return Uint8List.fromList(value.bytes);
    }
    return Uint8List(0);
  }

  /// Create and encode a CBOR request with standard fields
  Future<Uint8List> _encodeRequest(
    Map<int, CborValue> fields,
    String authKey,
    String? teamId,
  ) async {
    // Add standard fields
    fields[1] = CborString(authKey);
    if (teamId != null && teamId.isNotEmpty) {
      fields[2] = CborString(teamId);
    }

    // Convert to CBOR and compress
    final requestCbor = CborMap(
      fields.map((k, v) => MapEntry(CborSmallInt(k), v)),
    );
    final encoded = cbor.encode(requestCbor);
    final compressed = gzip.encode(encoded);
    return Uint8List.fromList(compressed);
  }

  /// Make a CBOR POST request and decode the response
  /// Returns a record of (decoded CBOR map, status code)
  Future<(CborMap, int)> _makeApiRequest(
    String launchId,
    String url,
    Uint8List compressedBody,
  ) async {
    final response = await _makeRequest(
      launchId,
      () => _httpClient.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/cbor+gzip',
          'Accept': 'application/cbor+gzip',
        },
        body: compressedBody,
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Request failed: ${response.statusCode}');
    }

    // Decompress and decode response
    final decompressed = gzip.decode(response.bodyBytes);
    final decoded = cbor.decode(decompressed) as CborMap;
    return (decoded, response.statusCode);
  }

  /// Suggest bundle to server
  Future<_SuggestResponse> _suggestBundle(
    String launchId,
    String url,
    String authKey,
    String domain,
    Uint8List bundleHash,
    String? teamId,
  ) async {
    final compressed = await _encodeRequest(
      {5: CborString(domain), 6: CborBytes(bundleHash)},
      authKey,
      teamId,
    );

    final (decoded, statusCode) = await _makeApiRequest(launchId, url, compressed);

    return _SuggestResponse(
      statusCode: statusCode,
      present: (decoded[CborSmallInt(5)] as CborBool?)?.value ?? false,
      missing: _parseCborHashList(decoded, 6),
      errors: _parseCborStringList(decoded, 2),
      warnings: _parseCborStringList(decoded, 3),
      messages: _parseCborStringList(decoded, 4),
    );
  }

  /// Upload bundle to server
  Future<_UploadResponse> _uploadBundle(
    String launchId,
    String url,
    String authKey,
    String domain,
    Uint8List bundleBytes,
    String? teamId,
  ) async {
    final compressed = await _encodeRequest(
      {5: CborString(domain), 6: CborBytes(bundleBytes)},
      authKey,
      teamId,
    );

    final (decoded, statusCode) = await _makeApiRequest(launchId, url, compressed);

    return _UploadResponse(
      statusCode: statusCode,
      success: (decoded[CborSmallInt(1)] as CborBool?)?.value ?? false,
      id: _parseCborBytes(decoded, 5),
      missing: _parseCborHashList(decoded, 6),
      errors: _parseCborStringList(decoded, 2),
      warnings: _parseCborStringList(decoded, 3),
      messages: _parseCborStringList(decoded, 4),
    );
  }

  /// Upload missing parts with chunking (like xmit)
  Future<void> _uploadMissingParts(
    String launchId,
    String url,
    String authKey,
    String domain,
    List<String> missingHashes,
    Map<String, Uint8List> fileContents,
    String? teamId,
    Function(LaunchStep)? onStepUpdate,
  ) async {
    // Extract actual file contents for missing hashes
    final toUpload = <Uint8List>[];
    for (final hash in missingHashes) {
      final content = fileContents[hash];
      if (content != null) {
        toUpload.add(content);
      } else {
        throw Exception(
          'Missing content for hash: $hash. This indicates a bug in bundle creation.',
        );
      }
    }

    if (toUpload.isEmpty) {
      _logToStep('No missing parts to upload', onStepUpdate);
      return;
    }

    // Sort by size (largest first, like xmit)
    toUpload.sort((a, b) => b.length.compareTo(a.length));

    // Chunk into 10MB chunks
    const chunkSize = 10 * 1024 * 1024; // 10MB
    final chunks = <List<Uint8List>>[];
    var currentChunk = <Uint8List>[];
    var currentChunkSize = 0;

    for (final file in toUpload) {
      if (currentChunkSize + file.length > chunkSize && currentChunk.isNotEmpty) {
        chunks.add(currentChunk);
        currentChunk = <Uint8List>[];
        currentChunkSize = 0;
      }
      currentChunk.add(file);
      currentChunkSize += file.length;
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }

    _logToStep(
      'Uploading ${toUpload.length} parts in ${chunks.length} chunk(s)',
      onStepUpdate,
    );

    // Upload each chunk
    for (var i = 0; i < chunks.length; i++) {
      if (_isCancelled(launchId)) {
        throw Exception('Upload cancelled');
      }

      final chunk = chunks[i];
      final chunkBytes = chunk.map((bytes) => CborBytes(bytes)).toList();

      _logToStep(
        'Uploading chunk ${i + 1}/${chunks.length} (${chunk.length} parts)',
        onStepUpdate,
      );

      final compressed = await _encodeRequest(
        {
          5: CborString(domain),
          7: CborList(chunkBytes),
        },
        authKey,
        teamId,
      );

      final (decoded, _) = await _makeApiRequest(launchId, url, compressed);

      // Log any response messages
      _logResponseMessages(
        errors: _parseCborStringList(decoded, 2),
        warnings: _parseCborStringList(decoded, 3),
        messages: _parseCborStringList(decoded, 4),
        onStepUpdate: onStepUpdate,
      );
    }

    _logToStep('✅ All missing parts uploaded', onStepUpdate);
  }

  /// Finalize launch
  Future<_FinalizeResponse> _finalizeLaunch(
    String launchId,
    String url,
    String authKey,
    String domain,
    Uint8List bundleId,
    String? teamId,
  ) async {
    final compressed = await _encodeRequest(
      {5: CborString(domain), 6: CborBytes(bundleId)},
      authKey,
      teamId,
    );

    final (decoded, statusCode) = await _makeApiRequest(launchId, url, compressed);

    return _FinalizeResponse(
      statusCode: statusCode,
      success: (decoded[CborSmallInt(1)] as CborBool?)?.value ?? false,
      errors: _parseCborStringList(decoded, 2),
      warnings: _parseCborStringList(decoded, 3),
      messages: _parseCborStringList(decoded, 4),
    );
  }

  /// List available teams for the authenticated user
  /// Returns a TeamListResponse with teams and management URL
  Future<TeamListResponse> listTeams(String serviceUrl, String authKey) async {
    final url = '$serviceUrl$_apiPrefix/teams';
    final compressed = await _encodeRequest({}, authKey, null);

    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/cbor+gzip',
            'Accept': 'application/cbor+gzip',
          },
          body: compressed,
        )
        .timeout(
          _httpTimeout,
          onTimeout: () {
            throw TimeoutException(
              'Team list request timed out after ${_httpTimeout.inSeconds} seconds',
            );
          },
        );

    if (response.statusCode != 200) {
      throw Exception('List teams failed: ${response.statusCode}');
    }

    final decompressed = gzip.decode(response.bodyBytes);
    final decoded = cbor.decode(decompressed) as CborMap;

    // Extract management URL (key 6)
    final manageUrl = (decoded[CborSmallInt(6)] as CborString?)?.toString() ?? 'https://xmit.co/admin';

    // Extract teams list from response
    final teams = <Team>[];
    final teamsValue = decoded[CborSmallInt(5)]; // Teams are at key 5

    if (teamsValue is CborList) {
      for (final teamItem in teamsValue) {
        if (teamItem is CborMap) {
          final id =
              (teamItem[CborSmallInt(1)] as CborString?)?.toString() ?? '';
          final name = (teamItem[CborSmallInt(2)] as CborString?)?.toString();
          if (id.isNotEmpty) {
            teams.add(Team(id: id, name: name));
          }
        }
      }
    }

    return TeamListResponse(teams: teams, manageUrl: manageUrl);
  }
}

class Team {
  final String id;
  final String? name;

  Team({required this.id, this.name});
}

class TeamListResponse {
  final List<Team> teams;
  final String manageUrl;

  TeamListResponse({required this.teams, required this.manageUrl});
}

/// Result of team selection from user
sealed class TeamSelectionResult {
  const TeamSelectionResult();
}

/// User selected a specific team
class TeamSelected extends TeamSelectionResult {
  final String teamId;
  const TeamSelected(this.teamId);
}

/// User requested to refresh the team list
class RefreshTeamList extends TeamSelectionResult {
  const RefreshTeamList();
}

/// User requested to create a new team
class CreateNewTeam extends TeamSelectionResult {
  const CreateNewTeam();
}

/// User cancelled team selection
class TeamSelectionCancelled extends TeamSelectionResult {
  const TeamSelectionCancelled();
}

class LaunchResult {
  final bool success;
  final String message;

  LaunchResult._({required this.success, required this.message});

  factory LaunchResult.success(String message) {
    return LaunchResult._(success: true, message: message);
  }

  factory LaunchResult.failure(String message) {
    return LaunchResult._(success: false, message: message);
  }
}

class _SuggestResponse {
  final int statusCode;
  final bool present;
  final List<String> missing;
  final List<String> errors;
  final List<String> warnings;
  final List<String> messages;

  _SuggestResponse({
    required this.statusCode,
    required this.present,
    required this.missing,
    this.errors = const [],
    this.warnings = const [],
    this.messages = const [],
  });
}

class _UploadResponse {
  final int statusCode;
  final bool success;
  final Uint8List id; // Bundle ID as bytes (hash)
  final List<String> missing;
  final List<String> errors;
  final List<String> warnings;
  final List<String> messages;

  _UploadResponse({
    required this.statusCode,
    required this.success,
    required this.id,
    required this.missing,
    this.errors = const [],
    this.warnings = const [],
    this.messages = const [],
  });
}

class _FinalizeResponse {
  final int statusCode;
  final bool success;
  final List<String> errors;
  final List<String> warnings;
  final List<String> messages;

  _FinalizeResponse({
    required this.statusCode,
    required this.success,
    this.errors = const [],
    this.warnings = const [],
    this.messages = const [],
  });
}
