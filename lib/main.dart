import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/project_provider.dart';
import 'screens/home_screen.dart';
import 'services/preferences_service.dart';

const String appVersion = '0.0.2';

// Global reference for cleanup on app exit
ProjectProvider? _projectProvider;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager to intercept close for cleanup
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);

  // Initialize preferences service before app starts
  await PreferencesService().initialize();

  // Set up signal handlers for graceful shutdown (Unix only)
  if (!Platform.isWindows) {
    ProcessSignal.sigint.watch().listen((_) => _cleanup());
    ProcessSignal.sigterm.watch().listen((_) => _cleanup());
  }

  runApp(const MainApp());
}

Future<void> _cleanup() async {
  _projectProvider?.dispose();
  exit(0);
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Clean up subprocesses before closing
    _projectProvider?.dispose();
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        _projectProvider = ProjectProvider();
        return _projectProvider!;
      },
      child: MaterialApp(
        title: 'Oncle Bob $appVersion',
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
