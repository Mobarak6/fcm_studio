import 'package:fcm_studio/features/composer/view/message_editor_tabs.dart';
import 'package:fcm_studio/features/composer/view/preview_panel.dart';
import 'package:fcm_studio/features/composer/view/send_panel.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/presets/view/preset_actions.dart';
import 'package:fcm_studio/features/presets/view/preset_picker.dart';
import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ComposerScreen extends StatelessWidget {
  const ComposerScreen({super.key});

  static const wideLayoutMinWidth = 1000.0;

  @override
  Widget build(BuildContext context) {
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
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(title: const Text('FCM Studio')),
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= wideLayoutMinWidth) {
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
              return const DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: 'Setup'),
                        Tab(text: 'Message'),
                        Tab(text: 'Preview & result'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _SetupPane(),
                          MessageEditorTabs(),
                          _OutputPane(),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
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
