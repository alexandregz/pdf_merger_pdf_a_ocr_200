import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SingleActivator, LogicalKeyboardKey
import 'ui/home/minimal_home.dart';
import 'ui/pages/settings_page.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

class App extends StatelessWidget {
  const App({super.key});

  void _openSettings() {
    final ctx = _navKey.currentContext;
    if (ctx != null) {
      Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'CIG Combinador PDF/A',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const MinimalHome(),
      navigatorKey: _navKey,
    );

    if (!Platform.isMacOS) return app;

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'App',
          menus: [
            PlatformMenuItem(
              label: 'Settings…',
              onSelected: _openSettings,
              shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
            ),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
      ],
      child: app,
    );
  }
}
