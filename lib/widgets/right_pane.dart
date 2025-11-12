import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/project.dart';
import '../providers/project_provider.dart';
import '../widgets/terminal_output.dart';
import '../widgets/launch_status.dart';

class RightPane extends StatelessWidget {
  final Task? selectedTask;
  final Site? selectedLaunch;
  final Widget? customContent;

  const RightPane({
    super.key,
    this.selectedTask,
    this.selectedLaunch,
    this.customContent,
  });

  @override
  Widget build(BuildContext context) {
    if (customContent != null) {
      return customContent!;
    }

    // Show launch output if a launch is selected
    if (selectedLaunch != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  Icons.upload,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedLaunch!.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                      ),
                      const SizedBox(height: AppConstants.spacingXs),
                      Text(
                        selectedLaunch!.domain,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer
                                  .withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Selector<ProjectProvider, (bool, List, String)>(
              selector: (_, p) => (p.isWaitingForTeamSelection, p.availableTeams, p.teamManageUrl),
              builder: (context, data, _) {
                final (isWaiting, teams, manageUrl) = data;
                final provider = context.read<ProjectProvider>();
                return LaunchStatusWidget(
                  steps: selectedLaunch!.steps,
                  isWaitingForTeamSelection: isWaiting,
                  availableTeams: teams.cast(),
                  teamManageUrl: manageUrl,
                  onRefresh: provider.refreshTeamList,
                  onCreate: provider.requestTeamCreation,
                  onCancel: provider.cancelTeamSelection,
                  onTeamSelected: provider.completeTeamSelection,
                );
              },
            ),
          ),
        ],
      );
    }

    if (selectedTask == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.terminal,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppConstants.spacingM),
            Text(
              'Select a task or launch to view output',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                Icons.terminal,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppConstants.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedTask!.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: AppConstants.spacingXs),
                    Text(
                      selectedTask!.command,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
                                .withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TerminalOutput(
            output: selectedTask!.output,
            autoScroll: true,
            placeholder: selectedTask!.status == TaskStatus.idle
                ? Text(
                    'Task not started yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
