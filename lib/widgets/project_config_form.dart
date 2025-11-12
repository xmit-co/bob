import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../models/project.dart';
import '../services/project_service.dart';

class _LaunchTargetEntry {
  final String id;
  String name;
  String domain;
  String service;

  static int _idCounter = 0;

  _LaunchTargetEntry({
    String? id,
    required this.name,
    required this.domain,
    this.service = 'https://xmit.co',
  }) : id = id ?? 'target_${_idCounter++}';

  Map<String, dynamic> toJson() {
    return {
      'domain': domain,
      'service': service,
    };
  }

  factory _LaunchTargetEntry.fromJson(String name, Map<String, dynamic> json) {
    return _LaunchTargetEntry(
      name: name,
      domain: json['domain'] as String? ?? '',
      service: json['service'] as String? ?? 'https://xmit.co',
    );
  }
}

class TaskEntry {
  final String id;
  String name;
  String command;

  static int _idCounter = 0;

  TaskEntry({
    String? id,
    required this.name,
    required this.command,
  }) : id = id ?? 'task_${_idCounter++}';
}

class ProjectConfigForm extends StatefulWidget {
  final Project project;
  final ProjectService projectService;
  final VoidCallback onCancel;
  final Function(Project) onSaved;

  const ProjectConfigForm({
    super.key,
    required this.project,
    required this.projectService,
    required this.onCancel,
    required this.onSaved,
  });

  @override
  State<ProjectConfigForm> createState() => _ProjectConfigFormState();
}

class _ProjectConfigFormState extends State<ProjectConfigForm> {
  List<TaskEntry> _tasks = [];
  List<_LaunchTargetEntry> _sites = [];
  final _launchDirectoryController = TextEditingController();
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  @override
  void didUpdateWidget(ProjectConfigForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload configuration if the project changed
    if (oldWidget.project.path != widget.project.path) {
      _loadConfiguration();
    }
  }

  @override
  void dispose() {
    _launchDirectoryController.dispose();
    super.dispose();
  }

  Future<void> _loadConfiguration() async {
    try {
      final packageJson = await widget.projectService.readPackageJson(widget.project.path);

      // Load tasks from scripts
      final scripts = packageJson['scripts'] as Map<String, dynamic>? ?? {};
      _tasks = scripts.entries
          .map((e) => TaskEntry(name: e.key, command: e.value as String))
          .toList();

      // Load launch configuration from bob
      final bob = packageJson['bob'] as Map<String, dynamic>?;

      // Load launch directory
      final directory = bob?['directory'] as String? ?? '';
      _launchDirectoryController.text = directory;

      // Load sites from bob.sites
      final sites = bob?['sites'] as Map<String, dynamic>? ?? {};
      _sites = sites.entries
          .map((e) => _LaunchTargetEntry.fromJson(e.key, e.value as Map<String, dynamic>))
          .toList();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveConfiguration() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final packageJson = await widget.projectService.readPackageJson(widget.project.path);

      // Update scripts
      final scripts = <String, String>{};
      for (final task in _tasks) {
        if (task.name.isNotEmpty && task.command.isNotEmpty) {
          scripts[task.name] = task.command;
        }
      }
      packageJson['scripts'] = scripts;

      // Update bob configuration (directory and sites)
      final directory = _launchDirectoryController.text.trim();
      final sites = <String, Map<String, dynamic>>{};
      for (final target in _sites) {
        if (target.name.isNotEmpty && target.domain.isNotEmpty) {
          sites[target.name] = target.toJson();
        }
      }

      // Build bob object
      if (directory.isNotEmpty || sites.isNotEmpty) {
        final bob = <String, dynamic>{};
        if (directory.isNotEmpty) {
          bob['directory'] = directory;
        }
        if (sites.isNotEmpty) {
          bob['sites'] = sites;
        }
        packageJson['bob'] = bob;
      } else {
        packageJson.remove('bob');
      }

      await widget.projectService.writePackageJson(widget.project.path, packageJson);

      // Reload the project
      final result = await widget.projectService.reloadProject(widget.project);
      if (result.isSuccess) {
        await widget.onSaved(result.data!);
      } else {
        setState(() {
          _error = result.error;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _addTask() {
    setState(() {
      _tasks.add(TaskEntry(name: '', command: ''));
    });
  }

  void _removeTask(int index) {
    setState(() {
      _tasks.removeAt(index);
    });
  }

  void _reorderTasks(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final task = _tasks.removeAt(oldIndex);
      _tasks.insert(newIndex, task);
    });
  }

  void _addLaunchTarget() {
    setState(() {
      _sites.add(_LaunchTargetEntry(
        name: '',
        domain: '',
        service: 'https://xmit.co',
      ));
    });
  }

  void _removeLaunchTarget(int index) {
    setState(() {
      _sites.removeAt(index);
    });
  }

  void _reorderLaunchTargets(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final target = _sites.removeAt(oldIndex);
      _sites.insert(newIndex, target);
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
                  'Configure ${widget.project.name}',
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
                // Tasks section
                _buildSectionHeader(
                  context,
                  'Tasks',
                  Icons.play_arrow,
                  _addTask,
                ),
                const SizedBox(height: AppConstants.spacingM),
                _buildTasksList(),
                const SizedBox(height: AppConstants.spacingXl),
                // Launch directory section
                Text(
                  'Uploaded Directory',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: AppConstants.spacingS),
                Text(
                  'Directory to upload (e.g., "_site" for 11ty, "public" for Hugo). Leave empty to upload the entire project directory.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                ),
                const SizedBox(height: AppConstants.spacingM),
                TextField(
                  controller: _launchDirectoryController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Directory',
                    hintText: '_site, public, or leave empty',
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveConfiguration(),
                ),
                const SizedBox(height: AppConstants.spacingXl),
                // Launch targets section
                _buildSectionHeader(
                  context,
                  'Sites',
                  Icons.upload,
                  _addLaunchTarget,
                ),
                const SizedBox(height: AppConstants.spacingM),
                _buildLaunchTargetsList(),
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
                      onPressed: _saveConfiguration,
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

  Widget _buildTasksList() {
    if (_tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Center(
          child: Text(
            'No tasks yet. Click + to add one.',
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
      itemCount: _tasks.length,
      onReorder: _reorderTasks,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return ReorderableDragStartListener(
          key: ValueKey(task.id),
          index: index,
          child: Card(
            margin: const EdgeInsets.only(bottom: AppConstants.spacingS),
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingM),
              child: Row(
                children: [
                  Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: AppConstants.spacingM),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: TextEditingController(text: task.name)
                        ..selection = TextSelection.collapsed(offset: task.name.length),
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        task.name = value;
                      },
                      onSubmitted: (_) => _saveConfiguration(),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingM),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Command',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: TextEditingController(text: task.command)
                        ..selection = TextSelection.collapsed(offset: task.command.length),
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        task.command = value;
                      },
                      onSubmitted: (_) => _saveConfiguration(),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingM),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _removeTask(index),
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

  Widget _buildLaunchTargetsList() {
    if (_sites.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Center(
          child: Text(
            'No sites yet. Click + to add one.',
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
      itemCount: _sites.length,
      onReorder: _reorderLaunchTargets,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final target = _sites[index];
        return ReorderableDragStartListener(
          key: ValueKey(target.id),
          index: index,
          child: Card(
            margin: const EdgeInsets.only(bottom: AppConstants.spacingS),
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
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          controller: TextEditingController(text: target.name)
                            ..selection = TextSelection.collapsed(offset: target.name.length),
                          textInputAction: TextInputAction.next,
                          onChanged: (value) {
                            target.name = value;
                          },
                        ),
                        const SizedBox(height: AppConstants.spacingM),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Domain',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          controller: TextEditingController(text: target.domain)
                            ..selection = TextSelection.collapsed(offset: target.domain.length),
                          textInputAction: TextInputAction.next,
                          onChanged: (value) {
                            target.domain = value;
                          },
                        ),
                        const SizedBox(height: AppConstants.spacingM),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Hosting Provider',
                                  hintText: 'xmit.co',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                controller: TextEditingController(text: target.service)
                                  ..selection = TextSelection.collapsed(offset: target.service.length),
                                textInputAction: TextInputAction.done,
                                onChanged: (value) {
                                  target.service = value;
                                },
                                onSubmitted: (_) => _saveConfiguration(),
                              ),
                            ),
                            const SizedBox(width: AppConstants.spacingS),
                            IconButton(
                              icon: const Icon(Icons.open_in_browser),
                              onPressed: target.service.isNotEmpty
                                  ? () async {
                                      var urlString = target.service;
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
                              tooltip: 'Browse to Hosting Provider',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _removeLaunchTarget(index),
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
