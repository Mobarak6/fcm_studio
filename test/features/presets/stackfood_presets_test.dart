import 'dart:io';

import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';

/// The message shapes the StackFood backend sends (its push payload
/// catalogue, app/CentralLogics/Helpers.php), with the `data` keys each
/// delivers.
enum Envelope {
  device(
    dataKeys: {
      'title',
      'body',
      'image',
      'order_id',
      'type',
      'conversation_id',
      'advertisement_id',
      'data_id',
      'sender_type',
      'order_type',
      'click_action',
      'sound',
    },
    hasNotification: true,
  ),
  topic(
    dataKeys: {
      'title',
      'body',
      'order_id',
      'order_type',
      'type',
      'image',
      'title_loc_key',
      'body_loc_key',
      'click_action',
      'sound',
    },
    hasNotification: true,
  ),
  topicGeneral(
    dataKeys: {
      'title',
      'body',
      'order_id',
      'type',
      'image',
      'body_loc_key',
      'click_action',
      'sound',
    },
    hasNotification: true,
  ),
  topicDataOnly(
    dataKeys: {'title', 'body', 'type', 'image', 'body_loc_key'},
    hasNotification: false,
  );

  const Envelope({required this.dataKeys, required this.hasNotification});

  final Set<String> dataKeys;

  /// A `notification` block, `android.notification.channel_id` and the iOS
  /// sound. Data-only messages have none of them.
  final bool hasNotification;
}

const envelopes = {
  'builtin.stackfood.all.push_notification': Envelope.topicGeneral,
  'builtin.stackfood.all.maintenance': Envelope.topicDataOnly,
  'builtin.stackfood.user.order_status': Envelope.device,
  'builtin.stackfood.user.message': Envelope.device,
  'builtin.stackfood.user.wallet': Envelope.device,
  'builtin.stackfood.user.account': Envelope.device,
  'builtin.stackfood.user.subscription': Envelope.device,
  'builtin.stackfood.user.cart_abandon': Envelope.device,
  'builtin.stackfood.restaurant.new_order': Envelope.device,
  'builtin.stackfood.restaurant.order_status': Envelope.device,
  'builtin.stackfood.restaurant.message': Envelope.device,
  'builtin.stackfood.restaurant.account': Envelope.device,
  'builtin.stackfood.restaurant.withdraw': Envelope.device,
  'builtin.stackfood.restaurant.advertisement': Envelope.device,
  'builtin.stackfood.restaurant.subscription': Envelope.device,
  'builtin.stackfood.restaurant.promotion': Envelope.device,
  'builtin.stackfood.restaurant.promotion_new': Envelope.topic,
  'builtin.stackfood.restaurant.verified_badge': Envelope.device,
  'builtin.stackfood.panel.new_order': Envelope.topic,
  'builtin.stackfood.delivery.order_request': Envelope.topic,
  'builtin.stackfood.delivery.order_status': Envelope.device,
  'builtin.stackfood.delivery.assign': Envelope.device,
  'builtin.stackfood.delivery.cash_collect': Envelope.device,
  'builtin.stackfood.delivery.shift': Envelope.device,
  'builtin.stackfood.delivery.account': Envelope.device,
  'builtin.stackfood.delivery.message': Envelope.device,
  'builtin.stackfood.admin.new_order': Envelope.topic,
  'builtin.stackfood.admin.message': Envelope.topic,
};

/// Every `data.type` the backend sends, spelled as it sends them
/// (`CashBack` and `delivery_nam_shift_update` included).
const backendTypes = {
  'add_fund',
  'advertisement',
  'assign',
  'block',
  'bogo_offer',
  'campaign',
  'cart_abandon',
  'cash_collect',
  'CashBack',
  'customer_subscription_activated',
  'customer_subscription_expire_reminder',
  'delivery_nam_shift_update',
  'general',
  'happy_hour',
  'maintenance',
  'message',
  'new_order',
  'order_request',
  'order_status',
  'referral_code',
  'referral_earn',
  'stackfood_demo_reset',
  'subscription',
  'subscription_canceled',
  'subscription_expired',
  'unassign',
  'unblock',
  'verified_badge',
  'withdraw',
};

const namePrefixes = {
  // StackFood's own names for its apps, so no name clashes with 6amMart's.
  'all': 'All apps · ',
  'user': 'Customer app · ',
  'restaurant': 'Restaurant app · ',
  'panel': 'Restaurant panel · ',
  'delivery': 'Deliveryman app · ',
  'admin': 'Admin panel · ',
};

void main() {
  final presets = [
    for (final preset in PresetCodec.decode(
      File('assets/presets/builtin.json').readAsStringSync(),
    ))
      if (preset.id.startsWith('builtin.stackfood.')) preset,
  ];

  /// The types [preset] can send: its fixed `data.type`, or the options of
  /// its `type` choice list.
  List<String> typesOf(Preset preset) {
    final data = preset.template['data']! as Map<String, Object?>;
    final type = data['type']! as String;
    if (type != '{{type}}') {
      return [type];
    }
    final variable = preset.variables.singleWhere((v) => v.key == 'type');
    expect(variable.type, VariableType.enumeration, reason: preset.name);
    return variable.options;
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
      expect(preset.name, isNot(startsWith('StackFood')), reason: preset.id);
      expect(preset.description, isNotEmpty, reason: preset.id);
    }
  });

  test('they are all in the StackFood group', () {
    expect({for (final preset in presets) preset.group}, {'StackFood'});
  });

  test('every type is one the backend sends, and all of them are covered', () {
    expect(backendTypes, hasLength(29));
    final covered = {for (final preset in presets) ...typesOf(preset)};
    expect(covered.difference(backendTypes), isEmpty);
    expect(backendTypes.difference(covered), isEmpty);
  });

  for (final MapEntry(key: id, value: envelope) in envelopes.entries) {
    test('$id renders the ${envelope.name} envelope for each of its types', () {
      final preset = presets.singleWhere((p) => p.id == id);
      for (final type in typesOf(preset)) {
        final message = render(preset, type: type);
        final data = message['data']! as Map<String, Object?>;
        final reason = '$id ($type)';

        expect(data.keys, unorderedEquals(envelope.dataKeys), reason: reason);
        expect(data['type'], type, reason: reason);
        // The apps build the notification from these on Android.
        expect(data['title'], isNotEmpty, reason: reason);
        expect(data['body'], isNotEmpty, reason: reason);
        if (data.containsKey('body_loc_key')) {
          expect(data['body_loc_key'], type, reason: reason);
        }
        if (data.containsKey('title_loc_key')) {
          expect(data['title_loc_key'], data['order_id'], reason: reason);
        }

        if (envelope.hasNotification) {
          expect(message['notification'], {
            'title': data['title'],
            'body': data['body'],
            'image': data['image'],
          }, reason: reason);
          expect(message['android'], {
            'notification': {'channel_id': 'stackfood'},
          }, reason: reason);
          expect(message['apns'], {
            'payload': {
              'aps': {'sound': 'notification.wav'},
            },
          }, reason: reason);
          expect(data['sound'], 'notification.wav', reason: reason);
        } else {
          expect(message.containsKey('notification'), isFalse, reason: reason);
          expect(message.containsKey('android'), isFalse, reason: reason);
          expect(message.containsKey('apns'), isFalse, reason: reason);
        }
      }
    });
  }
}
