import 'dart:io';

import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';

/// The message shapes the 6amMart backend sends (its push payload catalogue,
/// branch client_53371_fulgence_4.0), with the `data` keys each delivers.
enum Envelope {
  device(
    dataKeys: {
      'title',
      'body',
      'image',
      'order_id',
      'trip_id',
      'status',
      'type',
      'data_id',
      'advertisement_id',
      'conversation_id',
      'module_id',
      'sender_type',
      'order_type',
      'click_action',
      'sound',
    },
    hasNotification: true,
    hasPlatformBlocks: true,
  ),
  topicOrder(
    dataKeys: {
      'title',
      'body',
      'order_id',
      'order_type',
      'type',
      'image',
      'module_id',
      'zone_id',
      'title_loc_key',
      'body_loc_key',
      'click_action',
      'sound',
    },
    hasNotification: true,
    hasPlatformBlocks: true,
  ),
  topicGeneral(
    dataKeys: {
      'title',
      'body',
      'type',
      'image',
      'body_loc_key',
      'click_action',
      'sound',
    },
    hasNotification: true,
    hasPlatformBlocks: true,
  ),
  topicCoupon(
    dataKeys: {
      'title',
      'body',
      'id',
      'type',
      'module_id',
      'coupon_id',
      'image',
      'body_loc_key',
      'click_action',
    },
    hasNotification: true,
    hasPlatformBlocks: false,
  ),
  topicInterest(
    dataKeys: {
      'title',
      'body',
      'id',
      'type',
      'module_id',
      'image',
      'price',
      'body_loc_key',
      'click_action',
    },
    hasNotification: true,
    hasPlatformBlocks: false,
  ),
  topicDataOnly(
    dataKeys: {'title', 'body', 'type', 'image', 'body_loc_key'},
    hasNotification: false,
    hasPlatformBlocks: false,
  );

  const Envelope({
    required this.dataKeys,
    required this.hasNotification,
    required this.hasPlatformBlocks,
  });

  final Set<String> dataKeys;
  final bool hasNotification;

  /// `android.notification.channel_id` and the iOS sound.
  final bool hasPlatformBlocks;
}

const envelopes = {
  'builtin.6ammart.all.push_notification': Envelope.topicGeneral,
  'builtin.6ammart.all.maintenance': Envelope.topicDataOnly,
  'builtin.6ammart.user.order_status': Envelope.device,
  'builtin.6ammart.user.message': Envelope.device,
  'builtin.6ammart.user.wallet': Envelope.device,
  'builtin.6ammart.user.account': Envelope.device,
  'builtin.6ammart.user.subscription': Envelope.device,
  'builtin.6ammart.user.trip_status': Envelope.device,
  'builtin.6ammart.user.coupon': Envelope.topicCoupon,
  'builtin.6ammart.user.interest': Envelope.topicInterest,
  'builtin.6ammart.delivery.order_request': Envelope.topicOrder,
  'builtin.6ammart.delivery.assign': Envelope.device,
  'builtin.6ammart.delivery.order_status': Envelope.device,
  'builtin.6ammart.delivery.message': Envelope.device,
  'builtin.6ammart.delivery.earnings': Envelope.device,
  'builtin.6ammart.delivery.account': Envelope.device,
  'builtin.6ammart.store.new_order': Envelope.device,
  'builtin.6ammart.store.order_status': Envelope.device,
  'builtin.6ammart.store.message': Envelope.device,
  'builtin.6ammart.store.items': Envelope.device,
  'builtin.6ammart.store.advertisement': Envelope.device,
  'builtin.6ammart.store.campaign': Envelope.device,
  'builtin.6ammart.store.account': Envelope.device,
};

/// Every `data.type` the backend sends to the three apps.
const backendTypes = {
  'add_fund',
  'advertisement',
  'assign',
  'block',
  'campaign',
  'cash_collect',
  'cashback',
  'coupon',
  'customer_subscription_activated',
  'customer_subscription_expire_reminder',
  'deliveryman_referral',
  'demo_reset',
  'general',
  'interest',
  'loyalty_point',
  'maintenance',
  'message',
  'monthly_order_reminder',
  'new_order',
  'order_request',
  'order_status',
  'otp',
  'product_approve',
  'product_rejected',
  'push_notification',
  'referral_code',
  'subscription',
  'subscription_canceled',
  'subscription_expired',
  'trip_status',
  'unassign',
  'unblock',
  'verified_badge',
  'wallet_transfer',
  'withdraw',
};

const namePrefixes = {
  // The group says "6amMart", so the presets for every app have no prefix.
  'all': '',
  'user': 'User app · ',
  'delivery': 'Delivery app · ',
  'store': 'Store app · ',
};

void main() {
  final presets = [
    for (final preset in PresetCodec.decode(
      File('assets/presets/builtin.json').readAsStringSync(),
    ))
      if (preset.id.startsWith('builtin.6ammart.')) preset,
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
      expect(preset.name, isNot(startsWith('6amMart')), reason: preset.id);
      expect(preset.description, isNotEmpty, reason: preset.id);
    }
  });

  test('they are all in the 6amMart group', () {
    expect({for (final preset in presets) preset.group}, {'6amMart'});
  });

  test('every type is one the backend sends, and all of them are covered', () {
    expect(backendTypes, hasLength(35));
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
        } else {
          expect(message.containsKey('notification'), isFalse, reason: reason);
        }

        if (envelope.hasPlatformBlocks) {
          expect(message['android'], {
            'notification': {'channel_id': '6ammart'},
          }, reason: reason);
          expect(message['apns'], {
            'payload': {
              'aps': {'sound': 'notification.wav'},
            },
          }, reason: reason);
        } else {
          expect(message.containsKey('android'), isFalse, reason: reason);
          expect(message.containsKey('apns'), isFalse, reason: reason);
        }
        if (data.containsKey('sound')) {
          expect(data['sound'], 'notification.wav', reason: reason);
        }
      }
    });
  }
}
