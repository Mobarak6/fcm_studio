import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/composer/view/composer_screen.dart';
import 'package:fcm_studio/features/devices/view/devices_screen.dart';
import 'package:fcm_studio/features/history/view/history_screen.dart';
import 'package:fcm_studio/features/presets/view/presets_screen.dart';
import 'package:fcm_studio/features/settings/view/settings_screen.dart';
import 'package:fcm_studio/features/targets/view/targets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The navigation rail and the screens behind it (spec §3.3). Screens stay
/// alive in an IndexedStack, so switching keeps their state.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const logoAsset = 'assets/branding/mark.png';
  static const logoKey = Key('app-logo');

  /// The rail's sections, in order. Devices is always there: on the web it
  /// explains when the browser can't reach phones. Settings holds the adb
  /// path, so it is desktop only (spec §3.1; WebUSB design §4.9).
  static List<AppSection> sectionsFor(PlatformFeatures platform) => [
    AppSection.composer,
    AppSection.presets,
    AppSection.targets,
    AppSection.history,
    AppSection.devices,
    if (platform.canRunAdb) AppSection.settings,
  ];

  @override
  Widget build(BuildContext context) {
    final sections = sectionsFor(context.read<PlatformFeatures>());
    final section = context.watch<NavigationCubit>().state;
    final index = sections.contains(section) ? sections.indexOf(section) : 0;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 12),
              child: Tooltip(
                message: 'FCM Studio',
                child: Image(
                  key: logoKey,
                  image: AssetImage(logoAsset),
                  width: 40,
                  height: 40,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            onDestinationSelected: (i) =>
                context.read<NavigationCubit>().show(sections[i]),
            destinations: [for (final s in sections) _destination(s)],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [for (final s in sections) _screen(s)],
            ),
          ),
        ],
      ),
    );
  }

  static NavigationRailDestination _destination(AppSection section) =>
      switch (section) {
        AppSection.composer => const NavigationRailDestination(
          icon: Icon(Icons.send_outlined),
          selectedIcon: Icon(Icons.send),
          label: Text('Composer', key: Key('nav-composer')),
        ),
        AppSection.presets => const NavigationRailDestination(
          icon: Icon(Icons.bookmarks_outlined),
          selectedIcon: Icon(Icons.bookmarks),
          label: Text('Presets', key: Key('nav-presets')),
        ),
        AppSection.targets => const NavigationRailDestination(
          icon: Icon(Icons.star_outline),
          selectedIcon: Icon(Icons.star),
          label: Text('Targets', key: Key('nav-targets')),
        ),
        AppSection.history => const NavigationRailDestination(
          icon: Icon(Icons.history),
          label: Text('History', key: Key('nav-history')),
        ),
        AppSection.devices => const NavigationRailDestination(
          icon: Icon(Icons.phone_android_outlined),
          selectedIcon: Icon(Icons.phone_android),
          label: Text('Devices', key: Key('nav-devices')),
        ),
        AppSection.settings => const NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings', key: Key('nav-settings')),
        ),
      };

  static Widget _screen(AppSection section) => switch (section) {
    AppSection.composer => const ComposerScreen(),
    AppSection.presets => const PresetsScreen(),
    AppSection.targets => const TargetsScreen(),
    AppSection.history => const HistoryScreen(),
    AppSection.devices => const DevicesScreen(),
    AppSection.settings => const SettingsScreen(),
  };
}
