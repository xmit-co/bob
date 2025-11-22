import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:cbor/cbor.dart';

/// Service for requesting API keys from the xmit server
/// Implements the key request protocol defined in xmitd/xhttpd/cli.go
class KeyRequestService {
  final http.Client _httpClient = http.Client();
  http.Client? _pollClient;
  static const Duration _httpTimeout = Duration(seconds: 30);
  static const Duration _pollTimeout = Duration(seconds: 90);
  bool _cancelled = false;

  /// Normalize service domain to full URL with https://
  String _normalizeServiceUrl(String service) {
    if (service.startsWith('http://') || service.startsWith('https://')) {
      return service;
    }
    return 'https://$service';
  }

  /// Request a new API key from the server
  /// Returns a KeyRequestResponse with browser URL, poll URL, and secret
  Future<KeyRequestResponse> requestKey({
    required String serviceUrl,
    String? applicationName,
  }) async {
    final url = _normalizeServiceUrl(serviceUrl);
    final endpoint = '$url/api/0/request-key';

    // Get hostname for the request
    final hostname = Platform.localHostname;

    // Build CBOR request with application name and hostname
    final fields = <int, CborValue>{};
    final name = applicationName != null && applicationName.isNotEmpty
        ? '$applicationName on $hostname'
        : hostname;
    fields[1] = CborString(name);

    // Encode request
    final requestCbor = CborMap(
      fields.map((k, v) => MapEntry(CborSmallInt(k), v)),
    );
    final encoded = cbor.encode(requestCbor);
    final compressed = gzip.encode(encoded);

    try {
      // Send request
      final response = await _httpClient
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/cbor+gzip',
              'Accept': 'application/cbor+gzip',
            },
            body: compressed,
          )
          .timeout(_httpTimeout);

      if (response.statusCode != 200) {
        throw Exception('Request failed: ${response.statusCode}');
      }

      // Decode response
      final decompressed = gzip.decode(response.bodyBytes);
      final decoded = cbor.decode(decompressed) as CborMap;

      // Parse response fields
      final success = (decoded[CborSmallInt(1)] as CborBool?)?.value ?? false;
      if (!success) {
        final errors = _parseCborStringList(decoded, 2);
        throw Exception('Request failed: ${errors.join(', ')}');
      }

      final browserUrl = (decoded[CborSmallInt(5)] as CborString?)?.toString() ?? '';
      final pollUrl = (decoded[CborSmallInt(6)] as CborString?)?.toString() ?? '';
      final secret = (decoded[CborSmallInt(7)] as CborString?)?.toString() ?? '';
      final requestId = (decoded[CborSmallInt(8)] as CborString?)?.toString() ?? '';

      if (browserUrl.isEmpty || pollUrl.isEmpty || secret.isEmpty) {
        throw Exception('Invalid response: missing required fields');
      }

      return KeyRequestResponse(
        browserUrl: browserUrl,
        pollUrl: pollUrl,
        secret: secret,
        baseUrl: url,
        requestId: requestId,
      );
    } catch (e) {
      throw Exception('Failed to request key: $e');
    }
  }

  /// Poll for the API key after user approves in browser
  /// Returns the API key when approved, or throws if timeout/error
  Future<String> awaitKey({
    required KeyRequestResponse keyRequest,
  }) async {
    final pollUrl = '${keyRequest.baseUrl}${keyRequest.pollUrl}?secret=${Uri.encodeComponent(keyRequest.secret)}';

    // Use dedicated poll client so it can be cancelled
    _pollClient = http.Client();

    try {
      // Make long-polling request (server will wait up to 90s)
      final response = await _pollClient!
          .get(Uri.parse(pollUrl))
          .timeout(_pollTimeout);

      if (response.statusCode == 200) {
        // Success - return the API key as plain text
        return response.body;
      } else if (response.statusCode == 404) {
        throw Exception('Key request not found or expired');
      } else if (response.statusCode == 401) {
        throw Exception('Invalid secret');
      } else if (response.statusCode == 408) {
        throw Exception('Request timeout - please try again');
      } else {
        throw Exception('Failed to get key: ${response.statusCode}');
      }
    } catch (e) {
      if (_cancelled) {
        throw Exception('Request cancelled');
      }
      if (e is TimeoutException) {
        throw Exception('Poll timeout - user may not have approved yet');
      }
      rethrow;
    } finally {
      _pollClient = null;
    }
  }

  /// Cancel any ongoing key request polling
  void cancelRequest() {
    _cancelled = true;
    _pollClient?.close();
    _pollClient = null;
  }

  /// Request and wait for API key with polling
  /// This is a convenience method that combines requestKey and awaitKey
  /// The onPollStart callback is called with the browser URL and request ID before polling starts
  Future<String> requestAndAwaitKey({
    required String serviceUrl,
    String? applicationName,
    required void Function(String browserUrl, String requestId) onPollStart,
    Duration? pollInterval,
  }) async {
    _cancelled = false;

    // Request key
    final keyRequest = await requestKey(
      serviceUrl: serviceUrl,
      applicationName: applicationName,
    );

    if (_cancelled) {
      throw Exception('Request cancelled');
    }

    // Notify caller to open browser
    onPollStart(keyRequest.browserUrl, keyRequest.requestId);

    // Poll with retries (server uses long-polling, so we retry on timeout)
    final interval = pollInterval ?? const Duration(seconds: 2);
    final maxAttempts = 30; // 30 attempts * 90s each = up to 45 minutes total

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_cancelled) {
        throw Exception('Request cancelled');
      }

      try {
        final apiKey = await awaitKey(keyRequest: keyRequest);
        return apiKey;
      } catch (e) {
        if (_cancelled) {
          throw Exception('Request cancelled');
        }
        // If timeout, retry after interval
        if (e.toString().contains('timeout') && attempt < maxAttempts - 1) {
          await Future.delayed(interval);
          continue;
        }
        // Other errors or last attempt - rethrow
        rethrow;
      }
    }

    throw Exception('Key request timeout - maximum poll attempts exceeded');
  }

  /// Parse a list of strings from CBOR map at given key
  List<String> _parseCborStringList(CborMap map, int key) {
    final value = map[CborSmallInt(key)];
    if (value is CborList) {
      return value
          .map((item) => item is CborString ? item.toString() : '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Dispose of resources
  void dispose() {
    _httpClient.close();
  }
}

/// Response from the key request endpoint
class KeyRequestResponse {
  final String browserUrl;
  final String pollUrl;
  final String secret;
  final String baseUrl;
  final String requestId;

  KeyRequestResponse({
    required this.browserUrl,
    required this.pollUrl,
    required this.secret,
    required this.baseUrl,
    required this.requestId,
  });
}
