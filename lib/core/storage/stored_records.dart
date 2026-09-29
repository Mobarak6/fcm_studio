import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

/// Reads one stored record with [fromJson]. Returns null when the record
/// can't be read (a wrong type, a missing field or an unknown value), so one
/// bad record never hides the others. Debug builds print the record's key.
T? readStoredRecord<T>(
  RecordSnapshot<String, Map<String, Object?>> record,
  T Function(Map<String, Object?> json) fromJson,
) {
  try {
    return fromJson(record.value);
  } on FormatException catch (e) {
    _reportSkipped(record, e);
  } on TypeError catch (e) {
    _reportSkipped(record, e);
  } on ArgumentError catch (e) {
    // e.g. an enum name that this version doesn't know.
    _reportSkipped(record, e);
  }
  return null;
}

void _reportSkipped(RecordSnapshot<String, Object?> record, Object error) {
  if (kDebugMode) {
    // Only the key and the error type: the values may hold device tokens.
    debugPrint(
      'Skipped the stored ${record.ref.store.name} record "${record.key}": '
      'it could not be read (${error.runtimeType}).',
    );
  }
}
