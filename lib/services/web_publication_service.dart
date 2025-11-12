import 'dart:convert';
import 'package:http/http.dart' as http;

class WebPublicationProtocol {
  final List<String> protocols;
  final String url;
  final String apiKeyManagementUrl;

  WebPublicationProtocol({
    required this.protocols,
    required this.url,
    required this.apiKeyManagementUrl,
  });

  factory WebPublicationProtocol.fromJson(Map<String, dynamic> json) {
    final protocolsRaw = json['protocols'];
    final List<String> protocols;

    if (protocolsRaw is List) {
      protocols = protocolsRaw.map((e) => e.toString()).toList();
    } else {
      protocols = [];
    }

    return WebPublicationProtocol(
      protocols: protocols,
      url: json['url'] as String? ?? '',
      apiKeyManagementUrl: json['apiKeyManagementUrl'] as String? ?? '',
    );
  }
}

class WebPublicationService {
  static final Map<String, WebPublicationProtocol> _cache = {};

  /// Fetch the web publication protocol metadata for a service
  /// Returns null if the service doesn't support the protocol or if there's an error
  static Future<WebPublicationProtocol?> getProtocolMetadata(String serviceDomain) async {
    // Check cache first
    if (_cache.containsKey(serviceDomain)) {
      return _cache[serviceDomain];
    }

    try {
      // Ensure the domain has a scheme
      var url = serviceDomain;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      // Fetch the well-known endpoint
      final wellKnownUrl = Uri.parse('$url/.well-known/web-publication-protocol');
      final response = await http.get(wellKnownUrl).timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final metadata = WebPublicationProtocol.fromJson(json);

        // Cache the result
        _cache[serviceDomain] = metadata;

        return metadata;
      }
    } catch (e) {
      // Silently fail - service might not support the protocol
    }

    return null;
  }

  /// Get the API key management URL for a service
  /// Throws an exception if the well-known endpoint is not available
  static Future<String> getApiKeyManagementUrl(String serviceDomain) async {
    final metadata = await getProtocolMetadata(serviceDomain);

    if (metadata != null && metadata.apiKeyManagementUrl.isNotEmpty) {
      return metadata.apiKeyManagementUrl;
    }

    // No well-known endpoint available - throw error
    throw Exception('Service $serviceDomain does not support Oncle Bob\'s protocol');
  }

  /// Clear the cache (useful for testing or forcing a refresh)
  static void clearCache() {
    _cache.clear();
  }
}
