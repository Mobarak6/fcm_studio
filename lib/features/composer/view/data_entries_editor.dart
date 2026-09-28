import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The `data` key/value table: rows can be added, moved and removed.
class DataEntriesEditor extends StatelessWidget {
  const DataEntriesEditor({required this.entries, super.key});

  static const addKey = Key('data-add');

  final List<MapEntry<String, Object?>> entries;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    void replace(List<MapEntry<String, Object?>> updated) =>
        cubit.setDataEntries(updated);
    List<MapEntry<String, Object?>> changed(
      int index,
      MapEntry<String, Object?> entry,
    ) => [...entries]..[index] = entry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, entry) in entries.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SyncedTextField(
                  key: ValueKey('data-key-$index'),
                  label: 'Key',
                  value: entry.key,
                  validator: (key) => _keyProblem(key, index),
                  onChanged: (key) {
                    // A refused key is not applied, so no entry is lost.
                    if (_keyProblem(key, index) == null) {
                      replace(
                        changed(index, MapEntry(key.trim(), entry.value)),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SyncedTextField(
                  key: ValueKey('data-value-$index'),
                  label: 'Value',
                  value: formText(entry.value),
                  onChanged: (value) =>
                      replace(changed(index, MapEntry(entry.key, value))),
                ),
              ),
              IconButton(
                key: ValueKey('data-up-$index'),
                tooltip: 'Move up',
                icon: const Icon(Icons.arrow_upward),
                onPressed: index == 0 ? null : () => replace(_moved(index, -1)),
              ),
              IconButton(
                key: ValueKey('data-down-$index'),
                tooltip: 'Move down',
                icon: const Icon(Icons.arrow_downward),
                onPressed: index == entries.length - 1
                    ? null
                    : () => replace(_moved(index, 1)),
              ),
              IconButton(
                key: ValueKey('data-remove-$index'),
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => replace([...entries]..removeAt(index)),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: addKey,
            onPressed: () => replace([...entries, MapEntry(_freeKey(), '')]),
            icon: const Icon(Icons.add),
            label: const Text('Add data field'),
          ),
        ),
      ],
    );
  }

  String? _keyProblem(String key, int index) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return 'Enter a key';
    }
    for (final (i, entry) in entries.indexed) {
      if (i != index && entry.key == trimmed) {
        return 'Duplicate key';
      }
    }
    return null;
  }

  String _freeKey() {
    final keys = {for (final entry in entries) entry.key};
    if (!keys.contains('key')) {
      return 'key';
    }
    var n = 2;
    while (keys.contains('key_$n')) {
      n++;
    }
    return 'key_$n';
  }

  List<MapEntry<String, Object?>> _moved(int index, int delta) {
    final result = [...entries];
    final entry = result.removeAt(index);
    result.insert(index + delta, entry);
    return result;
  }
}
