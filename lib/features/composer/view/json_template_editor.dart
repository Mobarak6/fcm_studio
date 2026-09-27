import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// The JSON editor for the message template.
///
/// Every edit reaches the cubit immediately, so Send (or Cmd/Ctrl+Enter) right
/// after typing always sends what is on screen.
class JsonTemplateEditor extends StatefulWidget {
  const JsonTemplateEditor({super.key});

  @override
  State<JsonTemplateEditor> createState() => _JsonTemplateEditorState();
}

class _JsonTemplateEditorState extends State<JsonTemplateEditor> {
  late final CodeLineEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(
      context.read<ComposerCubit>().state.templateText,
    );
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    context.read<ComposerCubit>().updateTemplateText(_controller.text);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Message JSON (the FCM "message" object, without the target)',
            style: theme.textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: CodeEditor(
            controller: _controller,
            shortcutsActivatorsBuilder: const _SendKeyFreeShortcuts(),
            style: CodeEditorStyle(
              fontSize: 13,
              codeTheme: CodeHighlightTheme(
                languages: {'json': CodeHighlightThemeMode(mode: langJson)},
                theme: dark ? atomOneDarkTheme : atomOneLightTheme,
              ),
            ),
          ),
        ),
        BlocSelector<ComposerCubit, ComposerState, String?>(
          selector: (state) => state.jsonError,
          builder: (context, error) => error == null
              ? const SizedBox.shrink()
              : Container(
                  width: double.infinity,
                  color: theme.colorScheme.errorContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    error,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
        ),
      ],
    );
  }
}

/// re_editor's default shortcuts, minus Cmd/Ctrl+Enter as "new line", so that
/// combination reaches the screen's Send shortcut.
class _SendKeyFreeShortcuts extends DefaultCodeShortcutsActivatorsBuilder {
  const _SendKeyFreeShortcuts();

  static bool _isSendKey(ShortcutActivator activator) =>
      activator is SingleActivator &&
      (activator.meta || activator.control) &&
      (activator.trigger == LogicalKeyboardKey.enter ||
          activator.trigger == LogicalKeyboardKey.numpadEnter);

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    final activators = super.build(type);
    if (type != CodeShortcutType.newLine || activators == null) {
      return activators;
    }
    return activators.where((activator) => !_isSendKey(activator)).toList();
  }
}
