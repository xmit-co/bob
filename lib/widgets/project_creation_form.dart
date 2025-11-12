import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../models/project_template.dart';
import '../services/preferences_service.dart';
import '../providers/project_provider.dart';

class ProjectCreationForm extends StatefulWidget {
  final VoidCallback onCancel;

  const ProjectCreationForm({
    super.key,
    required this.onCancel,
  });

  @override
  State<ProjectCreationForm> createState() => _ProjectCreationFormState();
}

class _ProjectCreationFormState extends State<ProjectCreationForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _preferencesService = PreferencesService();
  ProjectType _selectedType = ProjectType.defaultType;

  @override
  void initState() {
    super.initState();
    _loadParentDirectory();
  }

  Future<void> _loadParentDirectory() async {
    final parentDir = await _preferencesService.getParentDirectory();
    if (mounted) {
      setState(() {
        _locationController.text = parentDir;
      });

      // On macOS, verify we have access to the directory
      // If not, clear it and require the user to select one
      if (Platform.isMacOS && parentDir.isNotEmpty) {
        try {
          // Try to access the directory
          final dir = Directory(parentDir);
          final exists = await dir.exists();
          if (!exists) {
            // Directory doesn't exist or we don't have access
            setState(() {
              _locationController.text = '';
            });
          }
        } catch (e) {
          // Can't access directory, clear it
          setState(() {
            _locationController.text = '';
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _selectLocation() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select parent directory',
    );

    if (result != null && mounted) {
      await _preferencesService.setParentDirectory(result);
      setState(() {
        _locationController.text = result;
      });
    }
  }

  Future<void> _createProject() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final provider = Provider.of<ProjectProvider>(context, listen: false);

    // Use the new createAndAddProject method which handles everything
    await provider.createAndAddProject(
      projectName: _nameController.text,
      parentDirectory: _locationController.text,
      projectType: _selectedType,
    );

    // Close the form - project is now in the list with create task
    if (mounted) {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.formPadding),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Row(
              children: [
                Icon(
                  Icons.create_new_folder,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppConstants.spacingM),
                Text(
                  'Create New Project',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onCancel,
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingXl),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Project Name',
              hintText: 'my-project',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge),
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _createProject(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a project name';
              }
              if (!RegExp(r'^[a-z0-9-_]+$').hasMatch(value)) {
                return 'Use lowercase letters, numbers, hyphens, and underscores only';
              }
              return null;
            },
          ),
          const SizedBox(height: AppConstants.spacingL),
          TextFormField(
            controller: _locationController,
            decoration: InputDecoration(
              labelText: 'Parent Directory',
              hintText: 'Choose where to create the project',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.folder),
              suffixIcon: IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: _selectLocation,
              ),
            ),
            readOnly: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please select a parent directory';
              }
              return null;
            },
          ),
          const SizedBox(height: AppConstants.spacingL),
          Text(
            'Project Type',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppConstants.spacingM),
          RadioGroup<ProjectType>(
            groupValue: _selectedType,
            onChanged: (value) {
              setState(() {
                _selectedType = value!;
              });
            },
            child: Column(
              children: ProjectType.values.map((type) {
                return Card(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedType = type;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(AppConstants.cardPadding),
                      child: Row(
                        children: [
                          Radio<ProjectType>(value: type),
                          const SizedBox(width: AppConstants.spacingM),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  type.displayName,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: AppConstants.spacingXs),
                                Text(
                                  type.description,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppConstants.spacingL),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppConstants.spacingM),
              FilledButton.icon(
                onPressed: _createProject,
                icon: const Icon(Icons.check),
                label: const Text('Create Project'),
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
