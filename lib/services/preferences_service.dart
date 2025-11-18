import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import '../models/project.dart';

// Top-level functions for isolate execution
List<Project> _decodeProjects(String projectsJson) {
  try {
    final List<dynamic> decoded = jsonDecode(projectsJson) as List<dynamic>;
    return decoded
        .map((item) => Project.fromJson(item as Map<String, dynamic>))
        .toList();
  } catch (e) {
    return [];
  }
}

String _encodeProjects(List<Map<String, dynamic>> projectsData) {
  return jsonEncode(projectsData);
}

class PreferencesService {
  static const String _parentDirectoryKey = 'parent_directory';
  static const String _projectsKey = 'projects';
  static const String _apiKeysKey = 'api_keys';
  static const String _bookmarksKey = 'security_bookmarks';
  static const String _parentDirBookmarkKey = 'parent_directory_bookmark';

  // Singleton pattern
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  SharedPreferences? _prefs;
  final SecureBookmarks? _secureBookmarks = Platform.isMacOS ? SecureBookmarks() : null;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    // On macOS, restore the parent directory bookmark
    if (Platform.isMacOS && _secureBookmarks != null) {
      await _restoreParentDirectoryBookmark();
    }
  }

  Future<String> getParentDirectory() async {
    if (_prefs == null) {
      await initialize();
    }

    final savedDirectory = _prefs!.getString(_parentDirectoryKey);

    if (savedDirectory != null && savedDirectory.isNotEmpty) {
      return savedDirectory;
    }

    return await _getDefaultDocumentsDirectory();
  }

  Future<void> setParentDirectory(String directory) async {
    if (_prefs == null) {
      await initialize();
    }

    await _prefs!.setString(_parentDirectoryKey, directory);

    // On macOS, create a bookmark for the parent directory
    if (Platform.isMacOS && _secureBookmarks != null && directory.isNotEmpty) {
      try {
        final bookmark = await _secureBookmarks.bookmark(Directory(directory)).timeout(
          const Duration(seconds: 2),
        );
        await _prefs!.setString(_parentDirBookmarkKey, bookmark);
      } catch (e) {
        // Bookmark creation failed, but continue
      }
    }
  }

  Future<List<Project>> getProjects() async {
    if (_prefs == null) {
      await initialize();
    }

    // Restore bookmarks first to regain access to directories
    if (Platform.isMacOS && _secureBookmarks != null) {
      await _restoreBookmarks();
    }

    final projectsJson = _prefs!.getString(_projectsKey);

    if (projectsJson == null || projectsJson.isEmpty) {
      return [];
    }

    // Decode JSON in a separate isolate to avoid blocking the UI
    final projects = await compute(_decodeProjects, projectsJson);

    return projects;
  }

  Future<void> saveProjects(List<Project> projects) async {
    if (_prefs == null) {
      await initialize();
    }

    // Create bookmarks for macOS to maintain access across app restarts
    if (Platform.isMacOS && _secureBookmarks != null) {
      await _saveBookmarks(projects);
    }

    // Encode JSON in a separate isolate to avoid blocking the UI
    final projectsData = projects.map((p) => p.toJson()).toList();
    final projectsJson = await compute(_encodeProjects, projectsData);
    await _prefs!.setString(_projectsKey, projectsJson);
  }

  Future<void> _saveBookmarks(List<Project> projects) async {
    final bookmarksMap = <String, String>{};

    for (final project in projects) {
      try {
        final bookmark = await _secureBookmarks!.bookmark(Directory(project.path)).timeout(
          const Duration(seconds: 2),
        );
        bookmarksMap[project.path] = bookmark;
      } catch (e) {
        // Bookmark creation failed for this project, continue with others
      }
    }

    if (bookmarksMap.isNotEmpty) {
      await _prefs!.setString(_bookmarksKey, jsonEncode(bookmarksMap));
    }
  }

  Future<void> _restoreParentDirectoryBookmark() async {
    try {
      final bookmark = _prefs!.getString(_parentDirBookmarkKey);
      if (bookmark == null || bookmark.isEmpty) {
        return;
      }

      final resolvedEntity = await _secureBookmarks!.resolveBookmark(bookmark);
      await _secureBookmarks.startAccessingSecurityScopedResource(resolvedEntity);
    } catch (e) {
      // Bookmark restoration failed, parent directory may not be accessible
    }
  }

  Future<void> _restoreBookmarks() async {
    try {
      final bookmarksJson = _prefs!.getString(_bookmarksKey);
      if (bookmarksJson == null || bookmarksJson.isEmpty) {
        return;
      }

      final bookmarksMap = jsonDecode(bookmarksJson) as Map<String, dynamic>;

      for (final entry in bookmarksMap.entries) {
        try {
          final bookmark = entry.value as String;
          final resolvedEntity = await _secureBookmarks!.resolveBookmark(bookmark);

          // Start accessing the security-scoped resource
          await _secureBookmarks.startAccessingSecurityScopedResource(resolvedEntity);
        } catch (e) {
          // Bookmark restoration failed for this project, continue with others
        }
      }
    } catch (e) {
      // Failed to restore bookmarks entirely, continue without them
    }
  }


  /// Get API key for a specific service
  Future<String?> getApiKey(String service) async {
    if (_prefs == null) {
      await initialize();
    }

    final apiKeys = await getApiKeys();
    return apiKeys[service];
  }

  /// Get all API keys
  Future<Map<String, String>> getApiKeys() async {
    if (_prefs == null) {
      await initialize();
    }

    final apiKeysJson = _prefs!.getString(_apiKeysKey);
    if (apiKeysJson == null || apiKeysJson.isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(apiKeysJson) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      return {};
    }
  }

  /// Set API key for a specific service
  Future<void> setApiKey(String service, String apiKey) async {
    if (_prefs == null) {
      await initialize();
    }

    final apiKeys = await getApiKeys();
    if (apiKey.isEmpty) {
      apiKeys.remove(service);
    } else {
      apiKeys[service] = apiKey;
    }

    await _prefs!.setString(_apiKeysKey, jsonEncode(apiKeys));
  }

  /// Set all API keys at once
  Future<void> setApiKeys(Map<String, String> apiKeys) async {
    if (_prefs == null) {
      await initialize();
    }

    await _prefs!.setString(_apiKeysKey, jsonEncode(apiKeys));
  }

  Future<String> _getDefaultDocumentsDirectory() async {
    try {
      if (Platform.isWindows) {
        final documentsDir = await getApplicationDocumentsDirectory();
        return documentsDir.path;
      } else if (Platform.isMacOS) {
        // On macOS, use Documents directory (now that we're not sandboxed)
        final homeDir = Platform.environment['HOME'];
        if (homeDir != null) {
          return path.join(homeDir, 'Documents');
        }
        // No valid home directory - force user to select
        return '';
      } else if (Platform.isLinux) {
        final homeDir = Platform.environment['HOME'];
        if (homeDir != null) {
          return path.join(homeDir, 'Documents');
        }
        // No valid home directory - force user to select
        return '';
      }

      // Unknown platform - force user to select
      return '';
    } catch (e) {
      // Error getting default - force user to select
      return '';
    }
  }
}