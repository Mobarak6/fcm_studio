import 'dart:io';

import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';

/// The message shapes the Demandium backend sends (its push payload
/// catalogue, Modules/PromotionManagement/Lib/Promotion.php), with the `data`
/// keys each delivers.
enum Envelope {
  device(
    dataKeys: {
      'title',
      'body',
      'booking_id',
      'channel_id',
      'user_id',
      'type',
      'group',
      'image',
      'advertisement_id',
      'booking_type',
      'repeat_type',
      'post_id',
      'provider_id',
      'user_name',
      'user_image',
      'user_phone',
      'user_type',
    },
    notificationHasImage: false,
    isSilent: false,
  ),
  topic(
    dataKeys: {'title', 'body', 'booking_id', 'type', 'group', 'image'},
    notificationHasImage: true,
    isSilent: false,
  ),
  silent(
    dataKeys: {'title', 'body', 'booking_id', 'type', 'group', 'image'},
    notificationHasImage: false,
    isSilent: true,
  );

  const Envelope({
    required this.dataKeys,
    required this.notificationHasImage,
    required this.isSilent,
  });

  final Set<String> dataKeys;
  final bool notificationHasImage;

  /// Data only: no `notification`, `android` or `apns` block.
  final bool isSilent;
}

const envelopes = {
  'builtin.demandium.customer.booking': Envelope.device,
  'builtin.demandium.customer.bidding': Envelope.device,
  'builtin.demandium.customer.wallet': Envelope.device,
  'builtin.demandium.customer.account': Envelope.device,
  'builtin.demandium.provider.booking': Envelope.device,
  'builtin.demandium.provider.bidding': Envelope.device,
  'builtin.demandium.provider.account': Envelope.device,
  'builtin.demandium.provider.promotion': Envelope.device,
  'builtin.demandium.provider.services': Envelope.device,
  'builtin.demandium.serviceman.booking': Envelope.device,
  'builtin.demandium.all.chat': Envelope.device,
  'builtin.demandium.all.push_notification': Envelope.topic,
  'builtin.demandium.all.pages': Envelope.topic,
  'builtin.demandium.all.business_model': Envelope.topic,
  'builtin.demandium.provider.booking_alert': Envelope.topic,
  'builtin.demandium.provider.settings': Envelope.topic,
  'builtin.demandium.provider.verified': Envelope.topic,
  'builtin.demandium.all.maintenance': Envelope.silent,
  'builtin.demandium.all.demo_reset': Envelope.silent,
};

/// The `data.type` values the catalogue spells out. Device messages take
/// theirs from notification_type(), which the catalogue doesn't list.
const knownTypes = {
  'booking_alert',
  'demo_reset',
  'general',
  'maintenance',
  'privacy_policy',
  'terms_and_conditions',
};

const namePrefixes = {
  // The group says "Demandium", so the presets for every app have no prefix.
  'all': '',
  'customer': 'Customer app · ',
  'provider': 'Provider app · ',
  'serviceman': 'Serviceman app · ',
};

void main() {
  final presets = [
    for (final preset in PresetCodec.decode(
      File('assets/presets/builtin.json').readAsStringSync(),
    ))
      if (preset.id.startsWith('builtin.demandium.')) preset,
  ];

  Map<String, Object?> dataOf(Preset preset) =>
      preset.template['data']! as Map<String, Object?>;

  VariableDef variable(Preset preset, String key) =>
      preset.variables.singleWhere((v) => v.key == key);

  /// The types [preset] sends with a fixed value or a choice list. A type
  /// typed into a text field is the user's to choose, so it isn't listed.
  List<String> fixedTypesOf(Preset preset) {
    final type = dataOf(preset)['type']! as String;
    if (type != '{{type}}') {
      return [type];
    }
    final definition = variable(preset, 'type');
    return definition.type == VariableType.enumeration
        ? definition.options
        : const [];
  }

  Map<String, Object?> render(Preset preset, {String? type}) {
    final result = const MessageRenderer().render(
      template: preset.template,
      target: const TopicTarget('test'),
      variables: preset.variables,
      values: {
        for (final v in preset.variables) v.key: v.defaultValue,
        'type': ?type,
      },
    );
    expect(result.errors, isEmpty, reason: preset.name);
    return result.request!['message']! as Map<String, Object?>;
  }

  test('there is one preset for each entry in the envelope table', () {
    expect(presets.map((p) => p.id), unorderedEquals(envelopes.keys));
  });

  test('names start with the app the preset is for', () {
    for (final preset in presets) {
      final app = preset.id.split('.')[2];
      expect(preset.name, startsWith(namePrefixes[app]!), reason: preset.id);
      expect(preset.description, isNotEmpty, reason: preset.id);
    }
  });

  test('they are all in the Demandium group', () {
    expect({for (final preset in presets) preset.group}, {'Demandium'});
  });

  test('every type the catalogue spells out is covered', () {
    final covered = {for (final preset in presets) ...fixedTypesOf(preset)};
    expect(covered, unorderedEquals(knownTypes));
  });

  test('device messages let you type the type and the group', () {
    for (final preset in presets) {
      if (envelopes[preset.id] != Envelope.device) {
        continue;
      }
      final data = dataOf(preset);
      expect(data['type'], '{{type}}', reason: preset.id);
      expect(data['group'], '{{group}}', reason: preset.id);
      expect(variable(preset, 'type').type, VariableType.text);
      expect(variable(preset, 'group').type, VariableType.text);
      expect(variable(preset, 'type').defaultValue, isNotEmpty);
    }
  });

  for (final MapEntry(key: id, value: envelope) in envelopes.entries) {
    test('$id renders the ${envelope.name} envelope', () {
      final preset = presets.singleWhere((p) => p.id == id);
      final types = fixedTypesOf(preset);
      for (final type in types.isEmpty ? const <String?>[null] : types) {
        final message = render(preset, type: type);
        final data = message['data']! as Map<String, Object?>;
        final reason = '$id ($type)';

        expect(data.keys, unorderedEquals(envelope.dataKeys), reason: reason);
        if (type != null) {
          expect(data['type'], type, reason: reason);
        }
        expect(data['title'], isNotEmpty, reason: reason);

        if (envelope.isSilent) {
          expect(message.containsKey('notification'), isFalse);
          expect(message.containsKey('android'), isFalse);
          expect(message.containsKey('apns'), isFalse);
          continue;
        }
        expect(message['notification'], {
          'title': data['title'],
          'body': data['body'],
          if (envelope.notificationHasImage) 'image': data['image'],
        }, reason: reason);
        expect(message['android'], {
          'notification': {'channel_id': 'demandium'},
        }, reason: reason);
        expect(message['apns'], {
          'payload': {
            'aps': {'sound': 'notification.wav'},
          },
        }, reason: reason);
      }
    });
  }
}
