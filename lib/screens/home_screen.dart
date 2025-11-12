import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../models/project.dart';
import '../providers/project_provider.dart';
import '../services/project_service.dart';
import '../utils/process_utils.dart';
import '../utils/ui_utils.dart';
import '../widgets/left_pane.dart';
import '../widgets/project_creation_form.dart';
import '../widgets/project_config_form.dart';
import '../widgets/launch_target_form.dart';
import '../widgets/settings_form.dart';
import '../widgets/right_pane.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _handleImportProject(BuildContext context) async {
    final projectService = ProjectService();
    final provider = context.read<ProjectProvider>();

    // Mark as importing (FilePicker dialog will show)
    final result = await projectService.importProject();

    if (!context.mounted) return;

    if (result.isSuccess) {
      await provider.addProject(result.data!);
    } else if (result.error != 'No directory selected') {
      UiUtils.showErrorSnackbar(context, result.error!);
    }
  }

  Future<void> _openInExplorer(BuildContext context, Project project) async {
    try {
      await ProcessUtils.openInFileExplorer(project.path);
    } catch (e) {
      if (context.mounted) {
        UiUtils.showErrorSnackbar(
          context,
          'Failed to open file explorer: ${e.toString()}',
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ProjectProvider>();

    return Scaffold(
      body: Selector<ProjectProvider, bool>(
        selector: (_, provider) => provider.isLoadingProjects,
        builder: (context, isLoadingProjects, _) {
          // Show loading screen while projects are loading
          if (isLoadingProjects) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppConstants.spacingL),
                  Text(
                    'Loading projects...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
                ],
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              // Get window width for clamping calculations
              final windowWidth = constraints.maxWidth;

              // If window width is invalid (e.g., during initial render), don't render yet
              if (windowWidth <= 0 || windowWidth.isInfinite) {
                return const SizedBox.shrink();
              }

              return Row(
            children: [
              // Left pane - only rebuilds when projects, selection, or form visibility changes
              Selector<ProjectProvider,
                  (List<Project>, Task?, Site?, bool, Project?, Project?, bool, Set<String>, Map<String, String>)>(
                selector: (_, provider) => (
                  provider.projects,
                  provider.selectedTask,
                  provider.selectedLaunch,
                  provider.showingCreationForm,
                  provider.configuringProject,
                  provider.creatingLaunchFor,
                  provider.showingSettings,
                  provider.projectsBeingImported,
                  provider.importErrors,
                ),
                builder: (context, data, _) {
                  final (projects, selectedTask, selectedLaunch, showingForm, configuringProject, creatingLaunchFor, showingSettings, projectsBeingImported, importErrors) = data;
                  return Selector<ProjectProvider, double>(
                    selector: (_, provider) => provider.leftPaneWidth,
                    builder: (context, leftPaneWidth, _) {
                      // Clamp width in real-time as it changes
                      final minWidth = AppConstants.leftMinPaneWidth;
                      final maxWidth = windowWidth - AppConstants.rightMinPaneWidth - AppConstants.paneSeparatorWidth;

                      // Ensure maxWidth is at least minWidth (in case window is too small)
                      final safeMaxWidth = maxWidth < minWidth ? minWidth : maxWidth;
                      final clampedWidth = leftPaneWidth.clamp(minWidth, safeMaxWidth);

                      return SizedBox(
                        width: clampedWidth,
                        child: LeftPane(
                          projects: projects,
                          selectedTask: selectedTask,
                          selectedLaunch: selectedLaunch,
                          isCreationFormVisible: showingForm,
                          showingSettings: showingSettings,
                          projectsBeingImported: projectsBeingImported,
                          importErrors: importErrors,
                          onImportProject: () => _handleImportProject(context),
                          onCreateProject: provider.showCreationForm,
                          onTaskSelected: provider.selectTask,
                          onLaunchSelected: provider.selectLaunch,
                          onReorderProjects: provider.reorderProjects,
                          onRemoveProject: provider.removeProject,
                          onTaskToggle: provider.toggleTask,
                          onLaunchToggle: provider.toggleLaunch,
                          onOpenInExplorer: (project) => _openInExplorer(context, project),
                          onConfigureProject: provider.showProjectConfiguration,
                          onCreateLaunchTarget: provider.showLaunchCreation,
                          onOpenSettings: provider.showSettings,
                          onDismissError: provider.dismissImportError,
                          onRetryImport: provider.retryImportProject,
                        ),
                      );
                    },
                  );
                },
              ),
          // Resizer
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                final windowWidth = MediaQuery.of(context).size.width;
                provider.setLeftPaneWidth(
                  context.read<ProjectProvider>().leftPaneWidth + details.delta.dx,
                  windowWidth,
                );
              },
              child: Container(
                width: AppConstants.paneSeparatorWidth,
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
            ),
          ),
          // Right pane - only rebuilds when selected task or form visibility changes
          Expanded(
            child: Selector<ProjectProvider, (Task?, Site?, bool, Project?, Project?, bool, String?, String?)>(
              selector: (_, provider) => (
                provider.selectedTask,
                provider.selectedLaunch,
                provider.showingCreationForm,
                provider.configuringProject,
                provider.creatingLaunchFor,
                provider.showingSettings,
                provider.settingsBannerMessage,
                provider.settingsPrefilledService,
              ),
              builder: (context, data, _) {
                final (selectedTask, selectedLaunch, showingForm, configuringProject, creatingLaunchFor, showingSettings, settingsBannerMessage, settingsPrefilledService) = data;

                // Determine custom content
                Widget? customContent;
                if (showingForm) {
                  customContent = ProjectCreationForm(
                    onCancel: provider.hideCreationForm,
                  );
                } else if (configuringProject != null) {
                  customContent = ProjectConfigForm(
                    key: ValueKey(configuringProject.path),
                    project: configuringProject,
                    projectService: ProjectService(),
                    onCancel: provider.hideProjectConfiguration,
                    onSaved: provider.updateProjectAfterConfiguration,
                  );
                } else if (creatingLaunchFor != null) {
                  customContent = LaunchTargetForm(
                    key: ValueKey(creatingLaunchFor.path),
                    project: creatingLaunchFor,
                    projectService: ProjectService(),
                    onCancel: provider.hideLaunchCreation,
                    onSaved: provider.updateProjectAfterLaunchCreation,
                  );
                } else if (showingSettings) {
                  customContent = SettingsForm(
                    preferencesService: provider.preferencesService,
                    onCancel: provider.hideSettings,
                    bannerMessage: settingsBannerMessage,
                    prefilledService: settingsPrefilledService,
                  );
                }

                return RightPane(
                  selectedTask: selectedTask,
                  selectedLaunch: selectedLaunch,
                  customContent: customContent,
                );
              },
            ),
          ),
              ],
            );
          },
        );
        },
      ),
    );
  }
}
