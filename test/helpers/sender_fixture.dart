import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:http/http.dart' as http;

import 'fake_google.dart';
import 'fake_token_provider.dart';

MessageSender buildSender(
  AppDatabase database, {
  http.Client? client,
  AccessTokenResolver? auth,
  HistoryRepository? history,
  TargetsRepository? targets,
}) => MessageSender(
  fcmClient: FcmClient(httpClient: client ?? fakeGoogle()),
  auth: auth ?? FakeResolver(),
  history: history ?? HistoryRepository(database: database),
  targets: targets ?? TargetsRepository(database: database),
);
