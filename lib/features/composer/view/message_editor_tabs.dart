import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/form_tab.dart';
import 'package:fcm_studio/features/composer/view/json_template_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The Form and JSON tabs. Both stay alive, so switching keeps the editor's
/// cursor and undo history.
class MessageEditorTabs extends StatefulWidget {
  const MessageEditorTabs({super.key});

  static const formTabKey = Key('form-tab');
  static const jsonTabKey = Key('json-tab');

  @override
  State<MessageEditorTabs> createState() => _MessageEditorTabsState();
}

class _MessageEditorTabsState extends State<MessageEditorTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
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
      // "Show in JSON" brings the JSON tab to the front.
      listenWhen: (previous, current) =>
          current.jsonFocus != null && previous.jsonFocus != current.jsonFocus,
      listener: (context, state) => _tabs.index = 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(key: MessageEditorTabs.formTabKey, text: 'Form'),
              Tab(key: MessageEditorTabs.jsonTabKey, text: 'JSON'),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _tabs.index,
              children: const [FormTab(), JsonTemplateEditor()],
            ),
          ),
        ],
      ),
    );
  }
}
