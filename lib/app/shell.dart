import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/view/composer_screen.dart';
import 'package:fcm_studio/features/history/view/history_screen.dart';
import 'package:fcm_studio/features/presets/view/presets_screen.dart';
import 'package:fcm_studio/features/targets/view/targets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The navigation rail and the screens behind it (spec §3.3). Screens stay
/// alive in an IndexedStack, so switching keeps their state.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final section = context.watch<NavigationCubit>().state;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: section.index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (index) =>
                context.read<NavigationCubit>().show(AppSection.values[index]),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.send_outlined),
                selectedIcon: Icon(Icons.send),
                label: Text('Composer', key: Key('nav-composer')),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bookmarks_outlined),
                selectedIcon: Icon(Icons.bookmarks),
                label: Text('Presets', key: Key('nav-presets')),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.star_outline),
                selectedIcon: Icon(Icons.star),
                label: Text('Targets', key: Key('nav-targets')),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history),
                label: Text('History', key: Key('nav-history')),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: section.index,
              children: const [
                ComposerScreen(),
                PresetsScreen(),
                TargetsScreen(),
                HistoryScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
