import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../extensions/task_status_extension.dart';
import '../models/project.dart';

class LeftPane extends StatelessWidget {
  final List<Project> projects;
  final Task? selectedTask;
  final Site? selectedLaunch;
  final bool isCreationFormVisible;
  final bool showingSettings;
  final Set<String> projectsBeingImported;
  final Map<String, String> importErrors;
  final VoidCallback onImportProject;
  final VoidCallback onCreateProject;
  final Function(Task) onTaskSelected;
  final Function(Site) onLaunchSelected;
  final Function(int, int) onReorderProjects;
  final Function(Project) onRemoveProject;
  final Function(Project, Task) onTaskToggle;
  final Function(Project, Site) onLaunchToggle;
  final Function(Project) onOpenInExplorer;
  final Function(Project) onConfigureProject;
  final Function(Project) onCreateLaunchTarget;
  final VoidCallback onOpenSettings;
  final Function(String) onDismissError;
  final Function(String) onRetryImport;

  const LeftPane({
    super.key,
    required this.projects,
    required this.selectedTask,
    required this.selectedLaunch,
    required this.isCreationFormVisible,
    required this.showingSettings,
    required this.projectsBeingImported,
    required this.importErrors,
    required this.onImportProject,
    required this.onCreateProject,
    required this.onTaskSelected,
    required this.onLaunchSelected,
    required this.onReorderProjects,
    required this.onRemoveProject,
    required this.onTaskToggle,
    required this.onLaunchToggle,
    required this.onOpenInExplorer,
    required this.onConfigureProject,
    required this.onCreateLaunchTarget,
    required this.onOpenSettings,
    required this.onDismissError,
    required this.onRetryImport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.leftPaneHeaderPadding,
              vertical: 8,
            ),
            child: Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Projects',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.create_new_folder),
                      tooltip: 'Create',
                      onPressed: onCreateProject,
                      color: isCreationFormVisible
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Import',
                      onPressed: onImportProject,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (projects.isEmpty && projectsBeingImported.isEmpty && importErrors.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 40),
                    child: CustomPaint(
                      painter: _TrianglePainter(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      size: const Size(16, 8),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppConstants.spacingM),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Create or import a project',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                // Show importing projects
                ...projectsBeingImported.map((path) {
                  final name = path.split(r'\').last.split('/').last;
                  return ListTile(
                    dense: true,
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppConstants.spacingS),
                        Icon(
                          Icons.folder,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    subtitle: Text(
                      'Importing...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                    ),
                  );
                }),
                // Show import errors
                ...importErrors.entries.map((entry) {
                  final path = entry.key;
                  final error = entry.value;
                  final name = path.split(r'\').last.split('/').last;
                  return ListTile(
                    dense: true,
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: AppConstants.spacingS),
                        Icon(
                          Icons.folder,
                          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          error,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppConstants.spacingXs),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => onRetryImport(path),
                              icon: const Icon(Icons.refresh, size: 14),
                              label: const Text('Retry'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: AppConstants.spacingS),
                            TextButton.icon(
                              onPressed: () => onDismissError(path),
                              icon: const Icon(Icons.close, size: 14),
                              label: const Text('Dismiss'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                // Regular project list (exclude projects currently being imported and those with errors)
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: projects.where((p) => !projectsBeingImported.contains(p.path) && !importErrors.containsKey(p.path)).length,
                  onReorder: (oldFilteredIndex, newFilteredIndex) {
                    // Map filtered indices to original indices in the full projects list
                    final filteredProjects = projects.where((p) => !projectsBeingImported.contains(p.path) && !importErrors.containsKey(p.path)).toList();

                    final projectToMove = filteredProjects[oldFilteredIndex];

                    // Find the actual index in the full projects list
                    final oldIndex = projects.indexWhere((p) => p.path == projectToMove.path);

                    // Calculate the new index in the full list
                    int newIndex;
                    if (newFilteredIndex >= filteredProjects.length) {
                      // Moving to the end
                      newIndex = projects.length;
                    } else {
                      // Adjust for the reorder offset
                      final adjustedFilteredIndex = newFilteredIndex > oldFilteredIndex ? newFilteredIndex : newFilteredIndex;
                      final projectAtNewPosition = filteredProjects[adjustedFilteredIndex];
                      newIndex = projects.indexWhere((p) => p.path == projectAtNewPosition.path);
                    }

                    onReorderProjects(oldIndex, newIndex);
                  },
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final filteredProjects = projects.where((p) => !projectsBeingImported.contains(p.path) && !importErrors.containsKey(p.path)).toList();
                    final project = filteredProjects[index];

                    return ReorderableDragStartListener(
                      key: ValueKey(project.path),
                      index: index,
                      child: _ProjectTile(
                        project: project,
                        selectedTask: selectedTask,
                        selectedLaunch: selectedLaunch,
                        onTaskSelected: onTaskSelected,
                        onLaunchSelected: onLaunchSelected,
                        onRemoveProject: onRemoveProject,
                        onTaskToggle: onTaskToggle,
                        onLaunchToggle: onLaunchToggle,
                        onOpenInExplorer: onOpenInExplorer,
                        onConfigureProject: onConfigureProject,
                        onCreateLaunchTarget: onCreateLaunchTarget,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingS),
            decoration: showingSettings
                ? BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                  )
                : null,
            child: ListTile(
              dense: true,
              leading: Icon(
                Icons.settings,
                color: showingSettings
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              title: Text(
                'Settings',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: showingSettings ? FontWeight.bold : FontWeight.normal,
                      color: showingSettings
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : null,
                    ),
              ),
              onTap: onOpenSettings,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final Project project;
  final Task? selectedTask;
  final Site? selectedLaunch;
  final Function(Task) onTaskSelected;
  final Function(Site) onLaunchSelected;
  final Function(Project) onRemoveProject;
  final Function(Project, Task) onTaskToggle;
  final Function(Project, Site) onLaunchToggle;
  final Function(Project) onOpenInExplorer;
  final Function(Project) onConfigureProject;
  final Function(Project) onCreateLaunchTarget;

  const _ProjectTile({
    required this.project,
    required this.selectedTask,
    required this.selectedLaunch,
    required this.onTaskSelected,
    required this.onLaunchSelected,
    required this.onRemoveProject,
    required this.onTaskToggle,
    required this.onLaunchToggle,
    required this.onOpenInExplorer,
    required this.onConfigureProject,
    required this.onCreateLaunchTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          dense: true,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.drag_indicator,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              Icon(
                Icons.folder,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
              ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name),
                    Text(
                      project.path,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert),
            tooltip: 'Project actions',
            onSelected: (value) {
              switch (value) {
                case 'configure':
                  onConfigureProject(project);
                  break;
                case 'open':
                  onOpenInExplorer(project);
                  break;
                case 'remove':
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Remove Project'),
                      content: Text(
                        'Remove "${project.name}" from the list?\n\nThis will not delete the project files.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onRemoveProject(project);
                          },
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'configure',
                child: Row(
                  children: [
                    Icon(Icons.settings),
                    SizedBox(width: AppConstants.spacingM),
                    Text('Configure'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'open',
                child: Row(
                  children: [
                    Icon(Icons.folder_open),
                    SizedBox(width: AppConstants.spacingM),
                    Text('Manage files'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'remove',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline),
                    SizedBox(width: AppConstants.spacingM),
                    Text('Remove from list'),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (project.tasks.isNotEmpty)
          ...project.tasks.map((task) {
            final isTaskSelected = task == selectedTask;
            return Container(
              decoration: isTaskSelected
                  ? BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                    )
                  : (task.status == TaskStatus.failed
                      ? BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                        )
                      : null),
                child: ListTile(
                  dense: true,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: AppConstants.spacingXl),
                      Icon(
                        Icons.subdirectory_arrow_right,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                  title: Text(
                    task.name,
                    style: TextStyle(
                      fontWeight:
                          isTaskSelected ? FontWeight.bold : FontWeight.normal,
                      color: isTaskSelected
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : (task.status == TaskStatus.failed
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : null),
                    ),
                  ),
                  subtitle: task.status != TaskStatus.idle &&
                             (task.status == TaskStatus.running ||
                              (task.lastExitCode != null && task.lastExitCode != 0))
                      ? Text(
                          task.status == TaskStatus.running
                              ? 'Running...'
                              : 'Exit: ${task.lastExitCode ?? 'N/A'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isTaskSelected
                                    ? Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                                    : (task.status == TaskStatus.failed
                                        ? Theme.of(context).colorScheme.onErrorContainer.withValues(alpha: 0.7)
                                        : null),
                              ),
                        )
                      : null,
                  trailing: IconButton(
                    icon: Icon(
                      task.status.getIcon(),
                      color: isTaskSelected
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : (task.status == TaskStatus.failed
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : task.status.getColor(context)),
                    ),
                    onPressed: () {
                      onTaskToggle(project, task);
                    },
                    padding: EdgeInsets.zero,
                  ),
                  onTap: () => onTaskSelected(task),
                ),
              );
          }),
        if (project.sites.isEmpty)
          ListTile(
            dense: true,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: AppConstants.spacingXl),
                Icon(
                  Icons.upload,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                ),
              ],
            ),
            title: Text(
              'Launch',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontStyle: FontStyle.italic,
              ),
            ),
            onTap: () => onCreateLaunchTarget(project),
          )
        else
          ...project.sites.map((target) {
            final isLaunchSelected = target == selectedLaunch;
            return Container(
              decoration: isLaunchSelected
                  ? BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                    )
                  : (target.status == TaskStatus.failed
                      ? BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                        )
                      : null),
              child: ListTile(
                dense: true,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: AppConstants.spacingXl),
                    Icon(
                      Icons.upload,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ],
                ),
                title: Text(
                  target.name,
                  style: TextStyle(
                    fontWeight:
                        isLaunchSelected ? FontWeight.bold : FontWeight.normal,
                    color: isLaunchSelected
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : (target.status == TaskStatus.failed
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : null),
                  ),
                ),
                subtitle: target.status != TaskStatus.idle
                    ? Text(
                        target.status == TaskStatus.running
                            ? 'Launching...'
                            : (target.status == TaskStatus.success
                                ? 'Launched'
                                : 'Failed'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isLaunchSelected
                                  ? Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                                  : (target.status == TaskStatus.failed
                                      ? Theme.of(context).colorScheme.onErrorContainer.withValues(alpha: 0.7)
                                      : null),
                            ),
                      )
                    : Text(
                        target.domain,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                      ),
                trailing: IconButton(
                  icon: Icon(
                    target.status.getIcon(),
                    color: isLaunchSelected
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : (target.status == TaskStatus.failed
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : target.status.getColor(context)),
                  ),
                  onPressed: () {
                    onLaunchToggle(project, target);
                  },
                  padding: EdgeInsets.zero,
                ),
                onTap: () => onLaunchSelected(target),
              ),
            );
          }),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0) // Top point
      ..lineTo(0, size.height) // Bottom left
      ..lineTo(size.width, size.height) // Bottom right
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
