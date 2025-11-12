import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';
import '../services/preferences_service.dart';
import '../services/web_publication_service.dart';

class _ApiKeyEntry {
  final String id;
  String service;
  String apiKey;

  static int _idCounter = 0;

  _ApiKeyEntry({
    String? id,
    required this.service,
    required this.apiKey,
  }) : id = id ?? 'apikey_${_idCounter++}';
}

class SettingsForm extends StatefulWidget {
  final PreferencesService preferencesService;
  final VoidCallback onCancel;
  final String? bannerMessage;
  final String? prefilledService;

  const SettingsForm({
    super.key,
    required this.preferencesService,
    required this.onCancel,
    this.bannerMessage,
    this.prefilledService,
  });

  @override
  State<SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<SettingsForm> {
  List<_ApiKeyEntry> _apiKeys = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final apiKeys = await widget.preferencesService.getApiKeys();

      // If a service is prefilled and not in the existing keys, add it
      if (widget.prefilledService != null && !apiKeys.containsKey(widget.prefilledService)) {
        apiKeys[widget.prefilledService!] = '';
      }

      setState(() {
        _apiKeys = apiKeys.entries
            .map((e) => _ApiKeyEntry(service: e.key, apiKey: e.value))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Collect all API keys
      final updatedKeys = <String, String>{};
      for (final entry in _apiKeys) {
        if (entry.service.isNotEmpty && entry.apiKey.isNotEmpty) {
          updatedKeys[entry.service] = entry.apiKey;
        }
      }

      await widget.preferencesService.setApiKeys(updatedKeys);
      if (mounted) {
        widget.onCancel();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _addApiKey() {
    setState(() {
      _apiKeys.add(_ApiKeyEntry(service: '', apiKey: ''));
    });
  }

  void _removeApiKey(int index) {
    setState(() {
      _apiKeys.removeAt(index);
    });
  }

  void _reorderApiKeys(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final entry = _apiKeys.removeAt(oldIndex);
      _apiKeys.insert(newIndex, entry);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
          padding: const EdgeInsets.all(AppConstants.rightPaneContentPadding),
          child: Row(
            children: [
              Icon(
                Icons.settings,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppConstants.spacingM),
              Expanded(
                child: Text(
                  'Settings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onCancel,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.formPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner message if provided
                if (widget.bannerMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppConstants.spacingM),
                    child: Container(
                      padding: const EdgeInsets.all(AppConstants.spacingM),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: AppConstants.spacingM),
                          Expanded(
                            child: Text(
                              widget.bannerMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Error message if present
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppConstants.spacingM),
                    child: Container(
                      padding: const EdgeInsets.all(AppConstants.spacingM),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: AppConstants.spacingM),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // API Keys section
                _buildSectionHeader(
                  context,
                  'API Keys',
                  Icons.key,
                  _addApiKey,
                ),
                const SizedBox(height: AppConstants.spacingS),
                Text(
                  'Configure API keys for different hosting services.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                ),
                const SizedBox(height: AppConstants.spacingM),
                _buildApiKeysList(),
                const SizedBox(height: AppConstants.spacingXl),

                // Save button
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppConstants.spacingM),
                    FilledButton(
                      onPressed: _saveSettings,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onAdd,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: AppConstants.spacingS),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: onAdd,
          tooltip: 'Add',
        ),
      ],
    );
  }

  Widget _buildApiKeysList() {
    if (_apiKeys.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Center(
          child: Text(
            'No API keys yet. Click + to add one.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _apiKeys.length,
      onReorder: _reorderApiKeys,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final entry = _apiKeys[index];
        final isPrefilled = widget.prefilledService == entry.service;

        return ReorderableDragStartListener(
          key: ValueKey(entry.id),
          index: index,
          child: Card(
            margin: const EdgeInsets.only(bottom: AppConstants.spacingS),
            color: isPrefilled
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            shape: isPrefilled
                ? RoundedRectangleBorder(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingM),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: AppConstants.spacingM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Service Domain',
                                  hintText: 'e.g., xmit.co',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                controller: TextEditingController(text: entry.service)
                                  ..selection = TextSelection.collapsed(offset: entry.service.length),
                                textInputAction: TextInputAction.next,
                                onChanged: (value) {
                                  entry.service = value;
                                },
                              ),
                            ),
                            const SizedBox(width: AppConstants.spacingS),
                            if (entry.service.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.open_in_browser),
                                onPressed: () async {
                                  try {
                                    // Get the API key management URL from well-known endpoint
                                    final managementUrl = await WebPublicationService.getApiKeyManagementUrl(entry.service);
                                    final uri = Uri.tryParse(managementUrl);
                                    if (uri != null && await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  } catch (e) {
                                    // Show error if service doesn't support the protocol
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(e.toString().replaceFirst('Exception: ', '')),
                                          backgroundColor: Theme.of(context).colorScheme.error,
                                        ),
                                      );
                                    }
                                  }
                                },
                                tooltip: 'Get API Key',
                              ),
                          ],
                        ),
                        const SizedBox(height: AppConstants.spacingM),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'API Key',
                            hintText: 'Enter API key',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          controller: TextEditingController(text: entry.apiKey)
                            ..selection = TextSelection.collapsed(offset: entry.apiKey.length),
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onChanged: (value) {
                            entry.apiKey = value;
                          },
                          onSubmitted: (_) => _saveSettings(),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _removeApiKey(index),
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
