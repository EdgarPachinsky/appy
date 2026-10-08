import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart' show trayManager;
import 'package:window_manager/window_manager.dart';

import 'models/project.dart';
import 'services/native_bridge.dart';
import 'services/tray_controller.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/drop_zone.dart';
import 'ui/home_page.dart';
import 'ui/project_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final state = AppState();
  await state.init();

  const options = WindowOptions(
    size: Size(1100, 720),
    minimumSize: Size(760, 500),
    center: true,
    title: 'Appy',
    backgroundColor: AppColors.bg,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  // Closing the window hides it; Appy keeps running in the menu bar.
  await windowManager.setPreventClose(true);

  runApp(AppyApp(state: state));
}

class AppyApp extends StatefulWidget {
  const AppyApp({super.key, required this.state});
  final AppState state;

  @override
  State<AppyApp> createState() => _AppyAppState();
}

class _AppyAppState extends State<AppyApp> with WindowListener {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final TrayController _tray;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _tray = TrayController(
      state: widget.state,
      onShowWindow: _showWindow,
      onOpenProject: _openProject,
      onQuit: _quit,
    );
    _tray.init().then((_) => NativeBridge.enableTrayDrop((paths) async {
          await _addFolders(paths);
          await _showWindow();
        }));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _tray.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }

  @override
  void onWindowFocus() => widget.state.refreshGit();

  Future<void> _addFolders(List<String> paths) async {
    for (final path in paths) {
      await widget.state.addFolder(path);
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _openProject(Project project) async {
    await _showWindow();
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    navigator.push(projectRoute(project, widget.state));
  }

  Future<void> _quit() async {
    await widget.state.stopAll();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Appy',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomePage(state: widget.state),
      builder: (context, child) => FolderDropZone(
        onFolders: _addFolders,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
