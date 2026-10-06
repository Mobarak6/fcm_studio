import 'dart:io';

import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';

/// The message shapes the 6Valley backend sends (its push payload catalogue,
/// app/Traits/PushNotificationTrait.php), with the `data` keys each delivers.
/// None of them has an `android` block.
enum Envelope {
  device(
    dataKeys: {
      'title',
      'body',
      'image',
      'order_id',
      'order_details_id',
      'refund_id',
      'deliveryman_charge',
      'expected_delivery_date',
      'type',
      'is_read',
      'message_key',
      'notification_key',
      'notification_from',
      'auction_id',
      'auction_slug',
      'auction_product_name',
      'auction_product_thumbnail_full_url',
      'excluded_user_id',
      'recipient_user_id',
      'recipient_type',
    },
    hasNotification: true,
    hasApns: true,
  ),
  chatting(
    dataKeys: {
      'title',
      'body',
      'image',
      'order_id',
      'refund_id',
      'deliveryman_charge',
      'expected_delivery_date',
      'is_read',
      'type',
      'message_key',
      'notification_key',
      'notification_from',
    },
    hasNotification: true,
    hasApns: true,
  ),
  topic(
    dataKeys: {
      'title',
      'body',
      'image',
      'order_id',
      'type',
      'message_key',
      'excluded_user_id',
      'auction_id',
      'auction_slug',
      'auction_product_name',
      'auction_product_thumbnail_full_url',
      'is_read',
    },
    hasNotification: true,
    hasApns: true,
  ),
  maintenance(
    dataKeys: {'title', 'body', 'image', 'type', 'is_read'},
    hasNotification: false,
    hasApns: false,
  ),
  restock(
    dataKeys: {
      'title',
      'product_id',
      'slug',
      'body',
      'image',
      'type',
      'status',
      'route',
      'is_read',
    },
    hasNotification: true,
    hasApns: false,
  ),
  minimal(
    dataKeys: {'title', 'body', 'image'},
    hasNotification: true,
    hasApns: false,
  );

  const Envelope({
    required this.dataKeys,
    required this.hasNotification,
    required this.hasApns,
  });

  final Set<String> dataKeys;

  /// A `notification` block with the title and body (never an image).
  final bool hasNotification;

  /// `apns.payload.aps.sound: default`.
  final bool hasApns;
}

const envelopes = {
  'builtin.6valley.all.push_notification': Envelope.topic,
  'builtin.6valley.all.maintenance': Envelope.maintenance,
  'builtin.6valley.all.demo_reset': Envelope.topic,
  'builtin.6valley.all.chat': Envelope.chatting,
  'builtin.6valley.all.withdraw': Envelope.device,
  'builtin.6valley.all.auction_owner': Envelope.device,
  'builtin.6valley.customer.order_status': Envelope.device,
  'builtin.6valley.customer.verification_code': Envelope.device,
  'builtin.6valley.customer.referral': Envelope.device,
  'builtin.6valley.customer.wallet': Envelope.device,
  'builtin.6valley.customer.auction': Envelope.device,
  'builtin.6valley.customer.restock': Envelope.restock,
  'builtin.6valley.seller.order_status': Envelope.device,
  'builtin.6valley.seller.refund': Envelope.device,
  'builtin.6valley.seller.product': Envelope.device,
  'builtin.6valley.seller.restock_request': Envelope.minimal,
  'builtin.6valley.seller.theme': Envelope.topic,
  'builtin.6valley.delivery.order_status': Envelope.device,
  'builtin.6valley.delivery.cash_collect': Envelope.device,
  'builtin.6valley.admin.auction': Envelope.topic,
};

/// Every `data.type` the backend sends (its `data_type_values`).
const backendTypes = {
  'auction_approved',
  'auction_claim_expired',
  'auction_claim_payment_verified',
  'auction_claim_payment_verified_owner',
  'auction_claim_submitted',
  'auction_commission_payment_verified',
  'auction_commission_submitted',
  'auction_delivered',
  'auction_delivery_on_the_way',
  'auction_delivery_ready',
  'auction_denied',
  'auction_expired_result',
  'auction_item_claimed',
  'auction_new_bid',
  'auction_new_participation',
  'auction_next_bidder',
  'auction_outbid',
  'auction_participation_payment_verified',
  'auction_went_live',
  'auction_withdrawal_approved',
  'auction_withdrawal_rejected',
  'auction_withdrawal_submitted',
  'auction_won',
  'chatting',
  'demo_reset',
  'maintenance_mode',
  'notification',
  'order',
  'product_request_approved_message',
  'product_restock_update',
  'referral_code_used',
  'refund',
  'wallet',
  'wallet_withdraw',
};

const namePrefixes = {
  // The group says "6Valley", so the presets for every app have no prefix.
  'all': '',
  'customer': 'Customer app · ',
  'seller': 'Seller app · ',
  'delivery': 'Delivery man app · ',
  'admin': 'Admin panel · ',
};

void main() {
  final presets = [
    for (final preset in PresetCodec.decode(
      File('assets/presets/builtin.json').readAsStringSync(),
    ))
      if (preset.id.startsWith('builtin.6valley.')) preset,
  ];

  /// The types [preset] can send: its fixed `data.type`, the options of its
  /// `type` choice list, or none when it sends no type.
  List<String> typesOf(Preset preset) {
    final data = preset.template['data']! as Map<String, Object?>;
    final type = data['type'] as String?;
    if (type == null) {
      return const [];
    }
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
      expect(preset.description, isNotEmpty, reason: preset.id);
    }
  });

  test('they are all in the 6Valley group', () {
    expect({for (final preset in presets) preset.group}, {'6Valley'});
  });

  test('every type is one the backend sends, and all of them are covered', () {
    expect(backendTypes, hasLength(34));
    final covered = {
      for (final preset in presets)
        for (final type in typesOf(preset))
          if (type.isNotEmpty) type,
    };
    expect(covered.difference(backendTypes), isEmpty);
    expect(backendTypes.difference(covered), isEmpty);
  });

  test('a chat message names its sender in three keys', () {
    final chat = presets.singleWhere((p) => p.id == 'builtin.6valley.all.chat');
    final data = render(chat)['data']! as Map<String, Object?>;
    expect(data['message_key'], 'message_from_admin');
    expect(data['notification_key'], 'message_from_admin');
    expect(data['notification_from'], 'admin');
  });

  for (final MapEntry(key: id, value: envelope) in envelopes.entries) {
    test('$id renders the ${envelope.name} envelope for each of its types', () {
      final preset = presets.singleWhere((p) => p.id == id);
      final types = typesOf(preset);
      for (final type in types.isEmpty ? const <String?>[null] : types) {
        final message = render(preset, type: type);
        final data = message['data']! as Map<String, Object?>;
        final reason = '$id ($type)';

        expect(data.keys, unorderedEquals(envelope.dataKeys), reason: reason);
        if (type != null) {
          expect(data['type'], type, reason: reason);
        }
        expect(data['title'], isNotEmpty, reason: reason);
        expect(data['body'], isNotEmpty, reason: reason);
        if (data.containsKey('is_read')) {
          expect(data['is_read'], '0', reason: reason);
        }
        if (type != null && type.startsWith('auction_')) {
          expect(data['message_key'], type, reason: reason);
        }

        if (envelope.hasNotification) {
          expect(message['notification'], {
            'title': data['title'],
            'body': data['body'],
          }, reason: reason);
        } else {
          expect(message.containsKey('notification'), isFalse, reason: reason);
        }
        if (envelope.hasApns) {
          expect(message['apns'], {
            'payload': {
              'aps': {'sound': 'default'},
            },
          }, reason: reason);
        } else {
          expect(message.containsKey('apns'), isFalse, reason: reason);
        }
        expect(message.containsKey('android'), isFalse, reason: reason);
      }
    });
  }
}
