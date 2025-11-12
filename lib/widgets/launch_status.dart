import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../models/project.dart';
import '../services/launch_service.dart';

class LaunchStatusWidget extends StatefulWidget {
  final List<LaunchStep> steps;
  final bool isWaitingForTeamSelection;
  final List<Team> availableTeams;
  final String teamManageUrl;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;
  final VoidCallback onCancel;
  final Function(String) onTeamSelected;

  const LaunchStatusWidget({
    super.key,
    required this.steps,
    this.isWaitingForTeamSelection = false,
    this.availableTeams = const [],
    this.teamManageUrl = 'https://xmit.co/admin',
    required this.onRefresh,
    required this.onCreate,
    required this.onCancel,
    required this.onTeamSelected,
  });

  @override
  State<LaunchStatusWidget> createState() => _LaunchStatusWidgetState();
}

class _LaunchStatusWidgetState extends State<LaunchStatusWidget> {
  String? _selectedTeamId;

  @override
  void didUpdateWidget(LaunchStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset selection when teams change
    if (widget.availableTeams != oldWidget.availableTeams) {
      _selectedTeamId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) {
      return Center(
        child: Text(
          'Launch not started yet',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppConstants.rightPaneContentPadding),
      children: [
        // Launch steps
        ...List.generate(widget.steps.length, (index) {
          final step = widget.steps[index];
          final isLastStep = index == widget.steps.length - 1;
          return _LaunchStepTile(
            step: step,
            isLast: isLastStep && !widget.isWaitingForTeamSelection,
          );
        }),
        // Team selection UI (shown inline after steps when required)
        if (widget.isWaitingForTeamSelection)
          _TeamSelectionTile(
            teams: widget.availableTeams,
            teamManageUrl: widget.teamManageUrl,
            selectedTeamId: _selectedTeamId,
            onTeamSelected: (teamId) {
              setState(() {
                _selectedTeamId = teamId;
              });
            },
            onRefresh: widget.onRefresh,
            onCreate: () async {
              final url = Uri.parse(widget.teamManageUrl);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
              widget.onCreate();
            },
            onCancel: widget.onCancel,
            onConfirm: () {
              if (_selectedTeamId != null) {
                widget.onTeamSelected(_selectedTeamId!);
              }
            },
          ),
      ],
    );
  }
}

class _LaunchStepTile extends StatelessWidget {
  final LaunchStep step;
  final bool isLast;

  const _LaunchStepTile({
    required this.step,
    required this.isLast,
  });

  /// Build a text widget with clickable URLs
  Widget _buildTextWithLinks(BuildContext context, String text) {
    // Regular expression to match URLs
    final urlRegex = RegExp(
      r'https?://[^\s]+',
      caseSensitive: false,
    );

    final matches = urlRegex.allMatches(text);
    if (matches.isEmpty) {
      // No URLs found, return plain text
      return Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
      );
    }

    // Build text spans with clickable URLs
    final spans = <TextSpan>[];
    int lastIndex = 0;

    for (final match in matches) {
      // Add text before URL
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
        ));
      }

      // Add clickable URL
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            launchUrl(Uri.parse(url));
          },
      ));

      lastIndex = match.end;
    }

    // Add remaining text after last URL
    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
      ));
    }

    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
        children: spans,
      ),
    );
  }

  IconData _getIcon() {
    switch (step.status) {
      case LaunchStepStatus.pending:
        return Icons.radio_button_unchecked;
      case LaunchStepStatus.running:
        return Icons.hourglass_empty;
      case LaunchStepStatus.paused:
        return Icons.pause_circle;
      case LaunchStepStatus.completed:
        return Icons.check_circle;
      case LaunchStepStatus.failed:
        return Icons.error;
    }
  }

  Color _getColor(BuildContext context) {
    switch (step.status) {
      case LaunchStepStatus.pending:
        return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3);
      case LaunchStepStatus.running:
        return Theme.of(context).colorScheme.primary;
      case LaunchStepStatus.paused:
        return Theme.of(context).colorScheme.secondary;
      case LaunchStepStatus.completed:
        return Theme.of(context).colorScheme.tertiary;
      case LaunchStepStatus.failed:
        return Theme.of(context).colorScheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon column with connecting line
          SizedBox(
            width: 32,
            child: Column(
              children: [
                // Icon
                step.status == LaunchStepStatus.running
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      )
                    : Icon(
                        _getIcon(),
                        color: color,
                        size: 20,
                      ),
                // Connecting line to next step
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(width: AppConstants.spacingM),
        // Content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.titleWithDuration,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: step.status == LaunchStepStatus.running ||
                                step.status == LaunchStepStatus.paused
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: color,
                      ),
                ),
                if (step.message != null && step.message!.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacingXs),
                  Text(
                    step.message!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                  ),
                ],
                if (step.logs.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacingXs),
                  ...step.logs.map((log) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _buildTextWithLinks(context, log),
                      )),
                ],
              ],
            ),
          ),
        ),
        ],
      ),
    );
  }
}

class _TeamSelectionTile extends StatelessWidget {
  final List<Team> teams;
  final String teamManageUrl;
  final String? selectedTeamId;
  final Function(String) onTeamSelected;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _TeamSelectionTile({
    required this.teams,
    required this.teamManageUrl,
    required this.selectedTeamId,
    required this.onTeamSelected,
    required this.onRefresh,
    required this.onCreate,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon column with connecting line
        SizedBox(
          width: 32,
          child: Column(
            children: [
              // Running icon (animated)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppConstants.spacingM),
        // Content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team selection required',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: AppConstants.spacingS),
                Text(
                  'This domain requires team authentication. Please select a team:',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                ),
                const SizedBox(height: AppConstants.spacingM),
                if (teams.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(AppConstants.spacingM),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: AppConstants.spacingS),
                        Expanded(
                          child: Text(
                            'No teams found. Create a team at $teamManageUrl',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  RadioGroup<String>(
                    groupValue: selectedTeamId,
                    onChanged: (value) {
                      if (value != null) onTeamSelected(value);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: teams.map((team) {
                          final isSelected = selectedTeamId == team.id;
                          return InkWell(
                            onTap: () => onTeamSelected(team.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppConstants.spacingM,
                                vertical: AppConstants.spacingS,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Radio<String>(
                                    value: team.id,
                                  ),
                                  const SizedBox(width: AppConstants.spacingS),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          team.name?.isNotEmpty == true ? team.name! : team.id,
                                          style: TextStyle(
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        if (team.name?.isNotEmpty == true)
                                          Text(
                                            'ID: ${team.id}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                const SizedBox(height: AppConstants.spacingM),
                Wrap(
                  spacing: AppConstants.spacingS,
                  runSpacing: AppConstants.spacingS,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.open_in_browser, size: 16),
                      label: const Text('Manage Teams'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: selectedTeamId != null ? onConfirm : null,
                      child: const Text('Select'),
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
}
