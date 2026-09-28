import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/template_edits.dart';
import 'package:fcm_studio/features/composer/view/data_entries_editor.dart';
import 'package:fcm_studio/features/composer/view/form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A structured editor for common fields (spec §5.3). Fields it doesn't
/// cover are kept unchanged in the template.
class FormTab extends StatelessWidget {
  const FormTab({super.key});

  static const readOnlyMessage =
      'The JSON has an error, so the form is read-only. Fix it in the JSON tab.';

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ComposerCubit, ComposerState>(
      buildWhen: (previous, current) => previous.template != current.template,
      builder: (context, state) {
        final template = state.template;
        if (template == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(readOnlyMessage),
          );
        }
        final cubit = context.read<ComposerCubit>();
        final dataOnly = TemplateEdits.isDataOnly(template);

        Widget field(
          List<String> path,
          String label, {
          int maxLines = 1,
          String? hint,
          Object? Function(String text)? parse,
        }) => SyncedTextField(
          key: ValueKey('form-${path.join('.')}'),
          label: label,
          hint: hint,
          maxLines: maxLines,
          value: formText(TemplateEdits.read(template, path)),
          onChanged: (text) =>
              cubit.setField(path, parse == null ? text : parse(text)),
        );

        Widget choice(List<String> path, String label, List<String> options) =>
            ChoiceField(
              key: ValueKey('form-${path.join('.')}'),
              label: label,
              options: options,
              value: formText(TemplateEdits.read(template, path)),
              onChanged: (value) => cubit.setField(path, value),
            );

        Widget flag(List<String> path, String label, String subtitle) =>
            SwitchListTile(
              key: ValueKey('form-${path.join('.')}'),
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: Text(subtitle),
              value: TemplateEdits.read(template, path) == 1,
              onChanged: (on) => cubit.setField(path, on ? 1 : null),
            );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormSection(
              title: 'Message type',
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Notification + data'),
                    ),
                    ButtonSegment(value: true, label: Text('Data only')),
                  ],
                  selected: {dataOnly},
                  onSelectionChanged: (selection) =>
                      cubit.setDataOnly(selection.first),
                ),
              ],
            ),
            if (!dataOnly)
              FormSection(
                title: 'Notification',
                children: [
                  field(['notification', 'title'], 'Title'),
                  field(['notification', 'body'], 'Body', maxLines: 4),
                  field(
                    ['notification', 'image'],
                    'Image URL',
                    hint: 'https://…',
                  ),
                ],
              ),
            FormSection(
              title: 'Data',
              children: [
                DataEntriesEditor(entries: TemplateEdits.dataEntries(template)),
              ],
            ),
            FormSection(
              title: 'Android',
              children: [
                choice(
                  ['android', 'priority'],
                  'Priority',
                  const ['normal', 'high'],
                ),
                field(['android', 'ttl'], 'TTL', hint: 'e.g. 3600s'),
                field(['android', 'collapse_key'], 'Collapse key'),
                field(['android', 'notification', 'channel_id'], 'Channel ID'),
                field(
                  ['android', 'notification', 'sound'],
                  'Sound',
                  hint: 'default',
                ),
                field([
                  'android',
                  'notification',
                  'click_action',
                ], 'Click action'),
              ],
            ),
            FormSection(
              title: 'APNs (iOS)',
              children: [
                choice(
                  ['apns', 'headers', 'apns-priority'],
                  'apns-priority',
                  const ['5', '10'],
                ),
                field(
                  ['apns', 'payload', 'aps', 'sound'],
                  'Sound',
                  hint: 'default',
                ),
                field(
                  ['apns', 'payload', 'aps', 'badge'],
                  'Badge',
                  // A number stays a number; "{{badge}}" stays a placeholder.
                  parse: (text) => int.tryParse(text.trim()) ?? text,
                ),
                flag(
                  ['apns', 'payload', 'aps', 'content-available'],
                  'content-available',
                  'Wake the app in the background',
                ),
                flag(
                  ['apns', 'payload', 'aps', 'mutable-content'],
                  'mutable-content',
                  'Let a notification service extension change it',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
