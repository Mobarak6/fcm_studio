import 'dart:async';

import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// The JSON editor for the message template. Edits reach the cubit after a 300 ms pause.
class JsonTemplateEditor extends StatefulWidget {
  const JsonTemplateEditor({super.key});

  static const debounce = Duration(milliseconds: 300);

  @override
  State<JsonTemplateEditor> createState() => _JsonTemplateEditorState();
}

class _JsonTemplateEditorState extends State<JsonTemplateEditor> {
  late final CodeLineEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(
      context.read<ComposerCubit>().state.templateText,
    );
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(JsonTemplateEditor.debounce, () {
      if (mounted) {
        context.read<ComposerCubit>().updateTemplateText(_controller.text);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
