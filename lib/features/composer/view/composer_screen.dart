import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/message_editor_tabs.dart';
import 'package:fcm_studio/features/composer/view/preview_panel.dart';
import 'package:fcm_studio/features/composer/view/prod_banner.dart';
import 'package:fcm_studio/features/composer/view/send_panel.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/presets/view/preset_actions.dart';
import 'package:fcm_studio/features/presets/view/preset_picker.dart';
import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ComposerScreen extends StatefulWidget {
  const ComposerScreen({super.key});

  static const wideLayoutMinWidth = 1000.0;

  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  final _focusNode = FocusNode(debugLabel: 'composer');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The shortcuts only fire while focus is inside the composer, so take
    // focus back whenever the user returns to it from another screen.
    return BlocListener<NavigationCubit, AppSection>(
      listenWhen: (previous, current) => current == AppSection.composer,
      // The screen is still hidden when the cubit emits; wait for the frame
      // that shows it, or the request is ignored.
      listener: (context, section) =>
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _focusNode.requestFocus();
            }
          }),
      child: _shortcuts(context),
    );
  }

  Widget _shortcuts(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
          includeRepeats: false,
        ): () =>
            sendSelected(context),
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
          includeRepeats: false,
        ): () =>
            sendSelected(context),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            savePreset(context),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            savePreset(context),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(title: const Text('FCM Studio')),
          body: Column(
            children: [
              const ProdBanner(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >=
                        ComposerScreen.wideLayoutMinWidth) {
                      return const Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 320, child: _SetupPane()),
                          VerticalDivider(width: 1),
                          Expanded(child: MessageEditorTabs()),
                          VerticalDivider(width: 1),
                          SizedBox(width: 420, child: _OutputPane()),
                        ],
                      );
                    }
                    return const _NarrowLayout();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three panes as tabs. All three stay mounted (an IndexedStack, not a
/// TabBarView), so "Show in JSON" works from the result tab.
class _NarrowLayout extends StatefulWidget {
  const _NarrowLayout();

  @override
  State<_NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends State<_NarrowLayout>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(_onTabChanged);

  void _onTabChanged() => setState(() {});

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ComposerCubit, ComposerState>(
      // "Show in JSON" brings the Message tab to the front.
      listenWhen: (previous, current) =>
          current.jsonFocus != null && previous.jsonFocus != current.jsonFocus,
      listener: (context, state) => _tabs.index = 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Setup'),
              Tab(text: 'Message'),
              Tab(text: 'Preview & result'),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _tabs.index,
              children: const [
                _SetupPane(),
                MessageEditorTabs(),
                _OutputPane(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupPane extends StatelessWidget {
  const _SetupPane();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ProjectSwitcher(),
        SizedBox(height: 24),
        TargetPicker(),
        SizedBox(height: 24),
        PresetPicker(),
      ],
    );
  }
}

class _OutputPane extends StatelessWidget {
  const _OutputPane();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: PreviewPanel()),
        Divider(height: 1),
        SendPanel(),
      ],
    );
  }
}
