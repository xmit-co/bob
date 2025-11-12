import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';
import '../models/project.dart';
import '../services/project_service.dart';

class LaunchTargetForm extends StatefulWidget {
  final Project project;
  final ProjectService projectService;
  final VoidCallback onCancel;
  final Function(Project) onSaved;

  const LaunchTargetForm({
    super.key,
    required this.project,
    required this.projectService,
    required this.onCancel,
    required this.onSaved,
  });

  @override
  State<LaunchTargetForm> createState() => _LaunchTargetFormState();
}

class _LaunchTargetFormState extends State<LaunchTargetForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _domainController = TextEditingController();
  final _serviceController = TextEditingController(text: 'xmit.co');

  @override
  void initState() {
    super.initState();
    // Auto-update name when domain changes
    _domainController.addListener(_updateNameFromDomain);
  }

  void _updateNameFromDomain() {
    _nameController.text = _domainController.text.trim();
  }

  @override
  void dispose() {
    _domainController.removeListener(_updateNameFromDomain);
    _nameController.dispose();
    _domainController.dispose();
    _serviceController.dispose();
    super.dispose();
  }

  Future<void> _saveLaunchTarget() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final newTarget = Site(
      name: _nameController.text.trim(),
      domain: _domainController.text.trim(),
      service: _serviceController.text.trim(),
    );

    final result = await widget.projectService.addSite(
      widget.project,
      newTarget,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      await widget.onSaved(result.data!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: ${result.error}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.rightPaneContentPadding),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Text(
              'Launch',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppConstants.spacingM),
            Text(
              'Put ${widget.project.name} on the World Wide Web',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: AppConstants.spacingL),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _serviceController,
                    decoration: const InputDecoration(
                      labelText: 'Hosting provider',
                      hintText: 'xmit.co',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a hosting provider';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: AppConstants.spacingS),
                IconButton(
                  icon: const Icon(Icons.open_in_browser),
                  onPressed: _serviceController.text.isNotEmpty
                      ? () async {
                          var urlString = _serviceController.text;
                          // Add https:// if not present
                          if (!urlString.startsWith('http://') && !urlString.startsWith('https://')) {
                            urlString = 'https://$urlString';
                          }
                          final uri = Uri.tryParse(urlString);
                          if (uri != null) {
                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            } catch (e) {
                              // Silently fail if unable to launch
                            }
                          }
                        }
                      : null,
                  tooltip: 'Browse to hosting provider',
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingM),
            TextFormField(
              controller: _domainController,
              decoration: const InputDecoration(
                labelText: 'Domain',
                hintText: 'e.g., example.com',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _saveLaunchTarget(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a domain';
                }
                return null;
              },
            ),
            const SizedBox(height: AppConstants.spacingL),
            Row(
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppConstants.spacingM),
                FilledButton(
                  onPressed: _saveLaunchTarget,
                  child: const Text('Launch'),
                ),
              ],
            ),
          ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
