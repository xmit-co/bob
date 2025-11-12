import 'package:flutter/material.dart';

/// Application-wide constants and configuration values
class AppConstants {
  // Binary versions
  static const String bunVersion = '1.3.2';

  // Process timeouts
  static const Duration processKillGracePeriod = Duration(seconds: 2);
  static const Duration processKillTotalTimeout = Duration(seconds: 5);

  // UI constants
  static const double leftPaneMinWidth = 300.0;
  static const double leftPaneMaxWidth = 1000.0;
  static const double leftPaneDefaultWidth = 300.0;
  static const double paneSeparatorWidth = 8.0;
  static const double leftMinPaneWidth = 300.0;
  static const double rightMinPaneWidth = 600.0;

  // Terminal output
  static const String terminalFontFamily = 'Consolas';
  static const List<String> terminalFontFallbacks = ['Consolas', 'Menlo', 'monospace'];
  static const double terminalFontSize = 13.0;
  static const int maxOutputLines = 10000; // Circular buffer size
  static const Duration autoScrollDuration = Duration(milliseconds: 100);

  /// Returns the standard terminal text style with white text
  static const TextStyle terminalTextStyle = TextStyle(
    fontFamily: terminalFontFamily,
    fontFamilyFallback: terminalFontFallbacks,
    color: Colors.white,
  );

  // Icon sizes
  static const double taskIconSize = 18.0;
  static const double dragHandleIconSize = 20.0;
  static const double headerIconSize = 32.0;

  // Font sizes
  static const double taskNameFontSize = 12.0;
  static const double taskPathFontSize = 10.0;
  static const double projectNameFontSize = 13.0;

  // Spacing - following 8pt grid system
  static const double spacingXs = 4.0;   // Extra small spacing
  static const double spacingS = 8.0;    // Small spacing
  static const double spacingM = 16.0;   // Medium spacing
  static const double spacingL = 24.0;   // Large spacing
  static const double spacingXl = 32.0;  // Extra large spacing
  static const double spacingXxl = 48.0; // Extra extra large spacing

  // Component-specific spacing
  static const double taskIndent = 24.0;
  static const double leftPaneHeaderPadding = 16.0;
  static const double rightPaneContentPadding = 16.0;
  static const double formPadding = 24.0;
  static const double cardPadding = 12.0;

  // Output buffer
  static const int outputBufferSize = 10000;
  static const int maxLineLength = 5000;

  // Error messages
  static const String noDirectorySelectedError = 'No directory selected';
  static const String invalidJsonError = 'Invalid JSON format';
  static const String fileSystemError = 'File system error';

  AppConstants._();
}
