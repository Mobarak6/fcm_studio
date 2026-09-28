import 'dart:convert';

import 'package:flutter/material.dart';

/// How a template value shows in a form field.
String formText(Object? value) => switch (value) {
  null => '',
  final String text => text,
  _ => jsonEncode(value),
};

/// A text field for a value the cubit owns. It follows changes made
/// elsewhere (the JSON tab, a loaded preset) without fighting the typing.
class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;

  /// Returns an error to show under the field, or null.
  final String? Function(String text)? validator;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  String? _error;

  @override
  void didUpdateWidget(SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a change from outside replaces the text. The user's own edits come
    // back here unchanged, and a refused edit (e.g. a duplicate key) leaves
    // the value as it was, so the typed text stays with its error.
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
      _error = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controller,
        minLines: 1,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: _error,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (text) {
          final error = widget.validator?.call(text);
          if (error != _error) {
            setState(() => _error = error);
          }
          widget.onChanged(text);
        },
      ),
    );
  }
}

/// A dropdown with a "Not set" choice (the empty value).
class ChoiceField extends StatelessWidget {
  const ChoiceField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // A value the list doesn't know (e.g. "{{priority}}") is still shown.
    final all = [
      ...options,
      if (value.isNotEmpty && !options.contains(value)) value,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isDense: true,
            isExpanded: true,
            value: value,
            items: [
              const DropdownMenuItem(value: '', child: Text('Not set')),
              for (final option in all)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: (selected) => onChanged(selected ?? ''),
          ),
        ),
      ),
    );
  }
}

/// A titled group of form fields.
class FormSection extends StatelessWidget {
  const FormSection({
    required this.title,
    required this.children,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
