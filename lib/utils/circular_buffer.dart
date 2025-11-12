import '../config/constants.dart';

/// A circular buffer for storing a limited number of text lines.
/// When the buffer is full, the oldest lines are discarded.
class CircularBuffer {
  final int maxLines;
  final List<String> _lines = [];
  int _totalLinesWritten = 0;

  CircularBuffer({this.maxLines = AppConstants.maxOutputLines});

  /// Appends text to the buffer, splitting by newlines.
  void append(String text) {
    if (text.isEmpty) return;

    final lines = text.split('\n');
    for (final line in lines) {
      if (_lines.length >= maxLines) {
        _lines.removeAt(0);
      }
      _lines.add(line);
      _totalLinesWritten++;
    }
  }

  /// Returns the current buffer content as a single string.
  String get content {
    if (_lines.isEmpty) return '';
    return _lines.join('\n');
  }

  /// Returns true if the buffer has reached capacity and is dropping lines.
  bool get isTruncated => _totalLinesWritten > maxLines;

  /// Returns the number of lines currently in the buffer.
  int get lineCount => _lines.length;

  /// Returns the total number of lines that have been written (including dropped ones).
  int get totalLinesWritten => _totalLinesWritten;

  /// Clears the buffer.
  void clear() {
    _lines.clear();
    _totalLinesWritten = 0;
  }
}
