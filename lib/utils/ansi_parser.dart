import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AnsiParser {
  static final _urlRegex = RegExp(
    r'https?://[a-zA-Z0-9][-a-zA-Z0-9.]*(?::[0-9]+)?(?:/[^\s<>"{}|\\^`\[\]]*)?',
    caseSensitive: false,
  );

  static List<TextSpan> parse(String text, {required Color defaultColor}) {
    final spans = <TextSpan>[];
    final ansiRegex = RegExp(r'\x1B\[([0-9;]*)m');

    int currentIndex = 0;
    Color? currentColor = defaultColor;
    Color? currentBgColor;
    bool bold = false;
    bool dim = false;
    bool italic = false;
    bool underline = false;

    for (final match in ansiRegex.allMatches(text)) {
      // Add text before this escape code
      if (match.start > currentIndex) {
        final textSegment = text.substring(currentIndex, match.start);
        if (textSegment.isNotEmpty) {
          // Parse URLs in this segment
          spans.addAll(_parseTextWithUrls(
            textSegment,
            currentColor: currentColor,
            currentBgColor: currentBgColor,
            bold: bold,
            dim: dim,
            italic: italic,
            underline: underline,
            defaultColor: defaultColor,
          ));
        }
      }

      // Parse the escape code
      final codes = match.group(1)?.split(';') ?? ['0'];
      for (final code in codes) {
        final codeNum = int.tryParse(code) ?? 0;

        switch (codeNum) {
          case 0: // Reset
            currentColor = defaultColor;
            currentBgColor = null;
            bold = false;
            dim = false;
            italic = false;
            underline = false;
            break;
          case 1: // Bold
            bold = true;
            break;
          case 2: // Dim
            dim = true;
            break;
          case 3: // Italic
            italic = true;
            break;
          case 4: // Underline
            underline = true;
            break;
          case 22: // Normal intensity
            bold = false;
            dim = false;
            break;
          case 23: // Not italic
            italic = false;
            break;
          case 24: // Not underlined
            underline = false;
            break;

          // Foreground colors (30-37)
          case 30: currentColor = const Color(0xFF000000); break; // Black
          case 31: currentColor = const Color(0xFFCD3131); break; // Red
          case 32: currentColor = const Color(0xFF0DBC79); break; // Green
          case 33: currentColor = const Color(0xFFE5E510); break; // Yellow
          case 34: currentColor = const Color(0xFF2472C8); break; // Blue
          case 35: currentColor = const Color(0xFFBC3FBC); break; // Magenta
          case 36: currentColor = const Color(0xFF11A8CD); break; // Cyan
          case 37: currentColor = const Color(0xFFE5E5E5); break; // White
          case 39: currentColor = defaultColor; break; // Default

          // Bright foreground colors (90-97)
          case 90: currentColor = const Color(0xFF666666); break; // Bright Black (Gray)
          case 91: currentColor = const Color(0xFFF14C4C); break; // Bright Red
          case 92: currentColor = const Color(0xFF23D18B); break; // Bright Green
          case 93: currentColor = const Color(0xFFF5F543); break; // Bright Yellow
          case 94: currentColor = const Color(0xFF3B8EEA); break; // Bright Blue
          case 95: currentColor = const Color(0xFFD670D6); break; // Bright Magenta
          case 96: currentColor = const Color(0xFF29B8DB); break; // Bright Cyan
          case 97: currentColor = const Color(0xFFFFFFFF); break; // Bright White

          // Background colors (40-47)
          case 40: currentBgColor = const Color(0xFF000000); break; // Black
          case 41: currentBgColor = const Color(0xFFCD3131); break; // Red
          case 42: currentBgColor = const Color(0xFF0DBC79); break; // Green
          case 43: currentBgColor = const Color(0xFFE5E510); break; // Yellow
          case 44: currentBgColor = const Color(0xFF2472C8); break; // Blue
          case 45: currentBgColor = const Color(0xFFBC3FBC); break; // Magenta
          case 46: currentBgColor = const Color(0xFF11A8CD); break; // Cyan
          case 47: currentBgColor = const Color(0xFFE5E5E5); break; // White
          case 49: currentBgColor = null; break; // Default

          // Bright background colors (100-107)
          case 100: currentBgColor = const Color(0xFF666666); break; // Bright Black
          case 101: currentBgColor = const Color(0xFFF14C4C); break; // Bright Red
          case 102: currentBgColor = const Color(0xFF23D18B); break; // Bright Green
          case 103: currentBgColor = const Color(0xFFF5F543); break; // Bright Yellow
          case 104: currentBgColor = const Color(0xFF3B8EEA); break; // Bright Blue
          case 105: currentBgColor = const Color(0xFFD670D6); break; // Bright Magenta
          case 106: currentBgColor = const Color(0xFF29B8DB); break; // Bright Cyan
          case 107: currentBgColor = const Color(0xFFFFFFFF); break; // Bright White
        }
      }

      currentIndex = match.end;
    }

    // Add remaining text
    if (currentIndex < text.length) {
      final textSegment = text.substring(currentIndex);
      if (textSegment.isNotEmpty) {
        spans.addAll(_parseTextWithUrls(
          textSegment,
          currentColor: currentColor,
          currentBgColor: currentBgColor,
          bold: bold,
          dim: dim,
          italic: italic,
          underline: underline,
          defaultColor: defaultColor,
        ));
      }
    }

    return spans;
  }

  static List<TextSpan> _parseTextWithUrls(
    String text, {
    required Color? currentColor,
    required Color? currentBgColor,
    required bool bold,
    required bool dim,
    required bool italic,
    required bool underline,
    required Color defaultColor,
  }) {
    final spans = <TextSpan>[];
    final urlMatches = _urlRegex.allMatches(text).toList();

    if (urlMatches.isEmpty) {
      // No URLs, return as single span
      spans.add(TextSpan(
        text: text,
        style: TextStyle(
          color: currentColor,
          backgroundColor: currentBgColor,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          decoration: underline ? TextDecoration.underline : TextDecoration.none,
        ),
      ));
      return spans;
    }

    int currentIndex = 0;
    for (final urlMatch in urlMatches) {
      // Add text before URL
      if (urlMatch.start > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, urlMatch.start),
          style: TextStyle(
            color: currentColor,
            backgroundColor: currentBgColor,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            decoration: underline ? TextDecoration.underline : TextDecoration.none,
          ),
        ));
      }

      // Add URL as clickable link
      final url = urlMatch.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(
          color: const Color(0xFF3B8EEA), // Blue color for links
          backgroundColor: currentBgColor,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
      ));

      currentIndex = urlMatch.end;
    }

    // Add remaining text after last URL
    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: TextStyle(
          color: currentColor,
          backgroundColor: currentBgColor,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          decoration: underline ? TextDecoration.underline : TextDecoration.none,
        ),
      ));
    }

    return spans;
  }
}
