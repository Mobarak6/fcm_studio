import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/composer/domain/fcm_rules.dart';
import 'package:fcm_studio/features/composer/domain/render_issue.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';

export 'package:fcm_studio/features/composer/domain/render_issue.dart';

class RenderResult extends Equatable {
  const RenderResult({
    this.request,
    this.notes = const [],
    this.warnings = const [],
    this.errors = const [],
  });

  /// The exact body for `messages:send`. Null when there are errors.
  final Map<String, Object?>? request;
  final List<RenderIssue> notes;
  final List<RenderIssue> warnings;
  final List<RenderIssue> errors;

  bool get canSend => request != null && errors.isEmpty;

  @override
  List<Object?> get props => [request, notes, warnings, errors];
}

/// Turns a template and a target into the request body FCM expects (spec §5.2).
class MessageRenderer {
  const MessageRenderer();

  RenderResult render({
    required Map<String, Object?> template,
    required Target target,
    bool validateOnly = false,
  }) {
    final notes = <RenderIssue>[];
    final warnings = <RenderIssue>[];
    final errors = <RenderIssue>[];

    for (final field in Target.messageFields) {
      if (template.containsKey(field)) {
        errors.add(
          RenderIssue(
            field,
            'Remove "$field" from the JSON and set the target in the Target field instead.',
          ),
        );
      }
    }
    errors.addAll(target.validate());

    final body = jsonDecode(jsonEncode(template)) as Map<String, Object?>
      ..removeWhere((key, _) => Target.messageFields.contains(key));

    final data = body['data'];
    if (data != null) {
      if (data is Map<String, Object?>) {
        body['data'] = _stringifyData(data, notes, warnings, errors);
      } else {
        errors.add(
          const RenderIssue(
            'data',
            '"data" must be an object of string values.',
          ),
        );
      }
    }
    if (!body.containsKey('notification') && body.containsKey('data')) {
      _checkBackgroundDelivery(body, warnings);
    }

    final message = <String, Object?>{...target.toMessageField(), ...body};
    final size = utf8.encode(jsonEncode(message)).length;
    if (size > FcmRules.maxPayloadBytes) {
      warnings.add(
        RenderIssue(
          'message',
          'The message is $size bytes. FCM may reject payloads over ${FcmRules.maxPayloadBytes} bytes.',
        ),
      );
    }

    if (errors.isNotEmpty) {
      return RenderResult(notes: notes, warnings: warnings, errors: errors);
    }
    return RenderResult(
      request: {if (validateOnly) 'validate_only': true, 'message': message},
      notes: notes,
      warnings: warnings,
    );
  }

  static Map<String, String> _stringifyData(
    Map<String, Object?> data,
    List<RenderIssue> notes,
    List<RenderIssue> warnings,
    List<RenderIssue> errors,
  ) {
    final result = <String, String>{};
    data.forEach((key, value) {
      final path = 'data.$key';
      final problem = FcmRules.reservedDataKeyProblem(key);
      if (problem != null) {
        (problem.blocking ? errors : warnings).add(
          RenderIssue(path, problem.message),
        );
      }
      switch (value) {
        case null:
          notes.add(RenderIssue(path, 'Removed because the value is null.'));
        case String():
          result[key] = value;
        case bool():
          result[key] = value.toString();
          notes.add(RenderIssue(path, 'Converted boolean to string "$value".'));
        case num():
          result[key] = value.toString();
          notes.add(RenderIssue(path, 'Converted number to string "$value".'));
        default:
          result[key] = jsonEncode(value);
          notes.add(
            RenderIssue(
              path,
              'Converted ${value is List<Object?> ? 'array' : 'object'} to a JSON string.',
            ),
          );
      }
    });
    return result;
  }

  static void _checkBackgroundDelivery(
    Map<String, Object?> body,
    List<RenderIssue> warnings,
  ) {
    final android = body['android'];
    final priority = android is Map<String, Object?>
        ? android['priority']
        : null;
    if (priority != 'high' && priority != 'HIGH') {
      warnings.add(
        const RenderIssue(
          'android.priority',
          'Data-only messages without "priority": "high" can be delayed while the phone is idle.',
        ),
      );
    }

    final apns = body['apns'];
    final headers = apns is Map<String, Object?> ? apns['headers'] : null;
    final payload = apns is Map<String, Object?> ? apns['payload'] : null;
    final aps = payload is Map<String, Object?> ? payload['aps'] : null;
    final apnsPriority = headers is Map<String, Object?>
        ? headers['apns-priority']
        : null;
    final contentAvailable = aps is Map<String, Object?>
        ? aps['content-available']
        : null;
    if (apnsPriority != '5' || contentAvailable != 1) {
      warnings.add(
        const RenderIssue(
          'apns',
          'For iOS background delivery set apns.headers["apns-priority"] to "5" '
              'and apns.payload.aps["content-available"] to 1.',
        ),
      );
    }
  }
}
