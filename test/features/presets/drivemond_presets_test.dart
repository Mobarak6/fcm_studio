import 'dart:io';

import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';

/// The message shapes the DriveMond (HexaRide-Admin) backend sends (its push
/// payload catalogue, fcm_message_formats), with the `data` keys each
/// delivers.
enum Envelope {
  device(
    dataKeys: {
      'title',
      'body',
      'status',
      'ride_request_id',
      'type',
      'user_name',
      'title_loc_key',
      'body_loc_key',
      'image',
      'action',
      'reward_type',
      'reward_amount',
      'next_level',
      'sound',
      'android_channel_id',
      'new_trip_id',
      'trip_readable_id',
      'trip_cancellation_time',
    },
    android: {
      'priority': 'high',
      'notification': {
        'channel_id': 'hexaride',
        'sound': 'notification.wav',
        'icon': 'notification_icon',
      },
    },
  ),
  topic(
    dataKeys: {
      'title',
      'body',
      'image',
      'ride_request_id',
      'type',
      'action',
      'status',
      'sound',
      'android_channel_id',
    },
    android: {
      'priority': 'high',
      'notification': {'channel_id': 'hexaride'},
    },
  ),
  legacyTopic(
    dataKeys: {
      'title',
      'body',
      'ride_request_id',
      'type',
      'title_loc_key',
      'body_loc_key',
      'image',
      'sound',
      'android_channel_id',
      'sent_by',
      'trip_reference_id',
      'route',
      'action',
      'status',
    },
    android: {
      'priority': 'high',
      'notification': {'channel_id': 'hexaride'},
    },
  );

  const Envelope({required this.dataKeys, required this.android});

  final Set<String> dataKeys;
  final Map<String, Object?> android;
}

const envelopes = {
  'builtin.drivemond.all.chat': Envelope.device,
  'builtin.drivemond.all.wallet': Envelope.device,
  'builtin.drivemond.all.level_up': Envelope.device,
  'builtin.drivemond.all.review': Envelope.device,
  'builtin.drivemond.all.legal': Envelope.device,
  'builtin.drivemond.all.safety': Envelope.device,
  'builtin.drivemond.all.maintenance': Envelope.topic,
  'builtin.drivemond.all.marketing': Envelope.topic,
  'builtin.drivemond.customer.ride': Envelope.device,
  'builtin.drivemond.customer.shared': Envelope.device,
  'builtin.drivemond.customer.bids': Envelope.device,
  'builtin.drivemond.customer.parcel': Envelope.device,
  'builtin.drivemond.customer.parcel_refund': Envelope.device,
  'builtin.drivemond.customer.arrival': Envelope.device,
  'builtin.drivemond.driver.request': Envelope.device,
  'builtin.drivemond.driver.trip': Envelope.device,
  'builtin.drivemond.driver.parcel': Envelope.device,
  'builtin.drivemond.driver.account': Envelope.device,
  'builtin.drivemond.driver.wallet': Envelope.device,
  'builtin.drivemond.driver.admin_message': Envelope.device,
  'builtin.drivemond.admin.new_trip': Envelope.topic,
  'builtin.drivemond.admin.safety': Envelope.legacyTopic,
};

/// Every `data.action` a device message can carry: the action of every push
/// template, plus the hard-coded ones (auto arrival, identity check, and
/// `no_rewards` for a level up without a reward).
const backendActions = {
  'admin_collected_cash',
  'admin_message',
  'another_driver_assigned',
  'auto_arrival_notification_customer_message',
  'auto_arrival_notification_driver_message',
  'bid_accepted',
  'bid_request_canceled_by_customer',
  'bid_request_from_driver',
  'cash_in_hand_limit_exceeds',
  'coupon_applied',
  'coupon_removed',
  'customer_canceled_shared_trip',
  'customer_canceled_trip',
  'customer_rejected_bid',
  'digital_payment_successful',
  'driver_canceled_ride_request',
  'driver_on_the_way',
  'driver_status_paused',
  'driver_suspended',
  'driver_unsuspended',
  'face_verification_completed_successfully',
  'face_verification_failed',
  'fund_added_by_admin',
  'fund_added_digitally',
  'identity_image_approved',
  'identity_image_rejected',
  'legal_updated',
  'level_up',
  'new_message',
  'new_parcel',
  'new_parcel_request',
  'new_ride_request',
  'new_shared_ride_request',
  'no_rewards',
  'parcel_amount_debited',
  'parcel_amount_deducted',
  'parcel_canceled',
  'parcel_canceled_after_trip_started',
  'parcel_delivery_completed',
  'parcel_on_the_way',
  'parcel_picked_up',
  'parcel_return_penalty',
  'parcel_returned',
  'parcel_returning_otp',
  'payment_successful',
  'pickup_time_started',
  'privacy_policy_updated',
  'received_new_bid',
  'referral_reward_received',
  'refund_accepted',
  'refund_denied',
  'refunded_as_coupon',
  'refunded_to_wallet',
  'review_from_customer',
  'review_from_driver',
  'safety_alert_sent',
  'safety_problem_resolved',
  'searching_for_rider',
  'shared_passenger_cancel_trip',
  'shared_passenger_found',
  'shared_passenger_pickup',
  'shared_trip_canceled',
  'shared_trip_completed',
  'shared_trip_paused',
  'shared_trip_request_canceled',
  'shared_trip_resumed',
  'shared_trip_route_update',
  'shared_trip_started',
  'someone_used_your_code',
  'terms_and_conditions_updated',
  'tips_from_customer',
  'trip_accepted',
  'trip_booked',
  'trip_canceled',
  'trip_canceled_for_driver_identity_mismatch',
  'trip_completed',
  'trip_edited',
  'trip_paused',
  'trip_request_canceled',
  'trip_resumed',
  'trip_started',
  'vehicle_active',
  'vehicle_request_approved',
  'vehicle_request_denied',
  'verify_driver_identity',
  'withdraw_request_approved',
  'withdraw_request_rejected',
  'withdraw_request_reversed',
  'withdraw_request_settled',
};

/// Every `data.type` a topic message carries.
const backendTopicTypes = {
  'maintenance_mode_on',
  'maintenance_mode_off',
  'send_notification',
  'ride_request',
  'parcel',
  'driver',
  'customer',
};

const namePrefixes = {
  // The group says "DriveMond", so the presets for every app have no prefix.
  'all': '',
  'customer': 'Customer app · ',
  'driver': 'Driver app · ',
  'admin': 'Admin panel · ',
};

void main() {
  final presets = [
    for (final preset in PresetCodec.decode(
      File('assets/presets/builtin.json').readAsStringSync(),
    ))
      if (preset.id.startsWith('builtin.drivemond.')) preset,
  ];

  /// The values of [field] that [preset] can send: its fixed value, or the
  /// options of the choice list of the same name.
  List<String> valuesOf(Preset preset, String field) {
    final data = preset.template['data']! as Map<String, Object?>;
    final value = data[field]! as String;
    if (value != '{{$field}}') {
      return [value];
    }
    final variable = preset.variables.singleWhere((v) => v.key == field);
    expect(variable.type, VariableType.enumeration, reason: preset.name);
    return variable.options;
  }

  Map<String, Object?> render(Preset preset, {String? action, String? type}) {
    final result = const MessageRenderer().render(
      template: preset.template,
      target: const TopicTarget('test'),
      variables: preset.variables,
      values: {
        for (final v in preset.variables) v.key: v.defaultValue,
        'action': ?action,
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

  test('they are all in the DriveMond group', () {
    expect({for (final preset in presets) preset.group}, {'DriveMond'});
  });

  test('device actions cover every action the backend sends', () {
    final covered = {
      for (final preset in presets)
        if (envelopes[preset.id] == Envelope.device)
          ...valuesOf(preset, 'action'),
    };
    expect(covered.difference(backendActions), isEmpty);
    expect(backendActions.difference(covered), isEmpty);
  });

  test('topic types cover every type the backend sends to a topic', () {
    final covered = {
      for (final preset in presets)
        if (envelopes[preset.id] != Envelope.device)
          ...valuesOf(preset, 'type'),
    };
    expect(covered, unorderedEquals(backendTopicTypes));
  });

  for (final MapEntry(key: id, value: envelope) in envelopes.entries) {
    test(
      '$id renders the ${envelope.name} envelope for each of its choices',
      () {
        final preset = presets.singleWhere((p) => p.id == id);
        final byAction = envelope == Envelope.device;
        for (final value in valuesOf(preset, byAction ? 'action' : 'type')) {
          final message = byAction
              ? render(preset, action: value)
              : render(preset, type: value);
          final data = message['data']! as Map<String, Object?>;
          final reason = '$id ($value)';

          expect(data.keys, unorderedEquals(envelope.dataKeys), reason: reason);
          expect(data[byAction ? 'action' : 'type'], value, reason: reason);
          expect(data['title'], isNotEmpty, reason: reason);
          expect(data['body'], isNotEmpty, reason: reason);
          expect(data['sound'], 'notification.wav', reason: reason);
          expect(data['android_channel_id'], 'hexaride', reason: reason);
          if (data.containsKey('title_loc_key')) {
            expect(
              data['title_loc_key'],
              data['ride_request_id'],
              reason: reason,
            );
            expect(data['body_loc_key'], data['type'], reason: reason);
          }

          expect(message['notification'], {
            'title': data['title'],
            'body': data['body'],
            'image': data['image'],
          }, reason: reason);
          expect(message['android'], envelope.android, reason: reason);
          expect(message['apns'], {
            'payload': {
              'aps': {'sound': 'notification.wav'},
            },
            'headers': {'apns-priority': '10'},
          }, reason: reason);
        }
      },
    );
  }
}
