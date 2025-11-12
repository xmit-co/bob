import 'dart:convert';

/// Top-level functions for JSON encoding/decoding in isolates
/// These must be top-level to be used with compute()

/// Decode a JSON string into a Map
Map<String, dynamic> decodeJson(String jsonString) {
  return jsonDecode(jsonString) as Map<String, dynamic>;
}

/// Encode a Map into a formatted JSON string with 2-space indentation
String encodeJson(Map<String, dynamic> data) {
  return const JsonEncoder.withIndent('  ').convert(data);
}
