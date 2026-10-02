import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/fake_google.dart';
import '../../helpers/fake_google_auth_flow.dart';
import '../../helpers/project_fixture.dart';
import '../../helpers/service_account_fixture.dart';

class _FailingSecretStore extends MemorySecretStore {
  @override
  Future<void> write(String key, String value, {bool persist = true}) async =>
      throw Exception('Keychain access denied');
}

void main() {
  late AppDatabase database;
  late MemorySecretStore secrets;
  late ProjectsRepository repository;

  setUp(() async {
    database = await AppDatabase.inMemory();
    secrets = MemorySecretStore();
    repository = ProjectsRepository(database: database, secrets: secrets);
  });

  tearDown(() => database.close());

  ProjectsCubit buildCubit([http.Client? client]) {
    final httpClient = client ?? fakeGoogle();
    return ProjectsCubit(
      repository: repository,
      authRegistry: ProjectAuthRegistry(
        repository: repository,
        httpClient: httpClient,
      ),
      firebaseApi: FirebaseProjectsApi(httpClient: httpClient),
    );
  }

  late ProjectAuthRegistry registry;

  ProjectsCubit buildGoogleCubit(
    FakeGoogleAuthFlow flow, {
    List<String> emails = const [testGoogleEmail],
    List<Map<String, Object?>> listed = const [listedTestProject],
  }) {
    final client = fakeGoogle(firebaseProjects: listed);
    registry = ProjectAuthRegistry(
      repository: repository,
      httpClient: client,
      googleFlow: flow,
      googleUserInfo: FakeGoogleUserInfo(emails),
    );
    return ProjectsCubit(
      repository: repository,
      authRegistry: registry,
      firebaseApi: FirebaseProjectsApi(httpClient: client),
    );
  }

  const googleDemo = Project(
    id: testProjectId,
    displayName: 'Demo Project',
    projectNumber: testProjectNumber,
    credential: GoogleAccountRef(testGoogleEmail),
  );

  test('adds a project from a service account key and selects it', () async {
    final cubit = buildCubit();
    await cubit.load();

    final result = await cubit.addFromServiceAccount(
      serviceAccountJson(),
      persistKey: true,
    );

    expect(
      result,
      isA<AddProjectSuccess>().having(
        (r) => r.needsProjectNumber,
        'needsProjectNumber',
        isFalse,
      ),
    );
    expect(cubit.state.selected, testProject);
    expect(await repository.loadAll(), [testProject]);
    expect(await repository.readSelectedProjectId(), testProjectId);
    expect(await secrets.read('sa:$testClientEmail'), isNotNull);
  });

  test(
    'uses the project ID as the name when the key cannot read project details',
    () async {
      final cubit = buildCubit(fakeGoogle(firebaseStatus: 403));
      await cubit.load();

      final result = await cubit.addFromServiceAccount(
        serviceAccountJson(),
        persistKey: true,
      );

      expect(
        result,
        isA<AddProjectSuccess>().having(
          (r) => r.needsProjectNumber,
          'needsProjectNumber',
          isTrue,
        ),
      );
      expect(cubit.state.selected?.displayName, testProjectId);
      expect(cubit.state.selected?.projectNumber, isNull);
    },
  );

  test('reports an invalid key file and changes nothing', () async {
    final cubit = buildCubit();
    await cubit.load();

    final result = await cubit.addFromServiceAccount('{}', persistKey: true);

    expect(result, isA<AddProjectFailure>());
    expect(cubit.state.projects, isEmpty);
  });

  test('reports a key that Google rejects and saves nothing', () async {
    final cubit = buildCubit(fakeGoogle(tokenStatus: 400));
    await cubit.load();

    final result = await cubit.addFromServiceAccount(
      serviceAccountJson(),
      persistKey: true,
    );

    expect(
      result,
      isA<AddProjectFailure>().having(
        (r) => r.message,
        'message',
        contains('rejected this key'),
      ),
    );
    expect(await repository.loadAll(), isEmpty);
    expect(await secrets.read('sa:$testClientEmail'), isNull);
  });

  test('adding the same project again keeps its environment', () async {
    final cubit = buildCubit();
    await cubit.load();
    await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);
    await cubit.setEnvironment(testProjectId, ProjectEnvironment.prod);

    await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

    expect(cubit.state.projects, hasLength(1));
    expect(cubit.state.selected?.environment, ProjectEnvironment.prod);
  });

  test('load restores projects and the selected project', () async {
    await buildCubit().addFromServiceAccount(
      serviceAccountJson(),
      persistKey: true,
    );

    final restored = buildCubit();
    await restored.load();

    expect(restored.state.status, ProjectsStatus.ready);
    expect(restored.state.selectedId, testProjectId);
    expect(restored.state.projects, [testProject]);
  });

  test(
    'remove deletes the project and its key and selects another project',
    () async {
      final cubit = buildCubit();
      await cubit.load();
      await cubit.addFromServiceAccount(
        serviceAccountJson(
          projectId: 'other-project',
          clientEmail: 'sender@other-project.iam.gserviceaccount.com',
        ),
        persistKey: true,
      );
      await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

      await cubit.remove(testProjectId);

      expect(cubit.state.projects.map((p) => p.id), ['other-project']);
      expect(cubit.state.selectedId, 'other-project');
      expect(await secrets.read('sa:$testClientEmail'), isNull);
      expect(await repository.readSelectedProjectId(), 'other-project');
    },
  );

  test('setProjectNumber trims the value, and empty clears it', () async {
    final cubit = buildCubit(fakeGoogle(firebaseStatus: 403));
    await cubit.load();
    await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

    await cubit.setProjectNumber(testProjectId, ' 42 ');
    expect(cubit.state.selected?.projectNumber, '42');

    await cubit.setProjectNumber(testProjectId, '');
    expect(cubit.state.selected?.projectNumber, isNull);
  });

  test('a storage failure while adding is reported, not thrown', () async {
    final failingRepository = ProjectsRepository(
      database: database,
      secrets: _FailingSecretStore(),
    );
    final httpClient = fakeGoogle();
    final cubit = ProjectsCubit(
      repository: failingRepository,
      authRegistry: ProjectAuthRegistry(
        repository: failingRepository,
        httpClient: httpClient,
      ),
      firebaseApi: FirebaseProjectsApi(httpClient: httpClient),
    );
    await cubit.load();

    final result = await cubit.addFromServiceAccount(
      serviceAccountJson(),
      persistKey: true,
    );

    expect(
      result,
      isA<AddProjectFailure>().having(
        (r) => r.message,
        'message',
        contains('Keychain access denied'),
      ),
    );
    expect(cubit.state.projects, isEmpty);
  });

  group('Google sign-in', () {
    test('Google sign-in is offered only when it is set up', () {
      expect(buildCubit().canSignInWithGoogle, isFalse);
      expect(
        buildGoogleCubit(FakeGoogleAuthFlow()).canSignInWithGoogle,
        isTrue,
      );
    });

    test(
      'lists the Firebase projects of the account and saves nothing yet',
      () async {
        final cubit = buildGoogleCubit(FakeGoogleAuthFlow());
        await cubit.load();
        final result = await cubit.signInWithGoogle();
        expect(
          result,
          isA<GoogleProjectsFound>()
              .having((r) => r.email, 'email', testGoogleEmail)
              .having((r) => r.projects, 'projects', [
                const FirebaseProjectInfo(
                  projectId: testProjectId,
                  displayName: 'Demo Project',
                  projectNumber: testProjectNumber,
                ),
              ]),
        );
        expect(await repository.loadAll(), isEmpty);
        expect(await secrets.read('google:$testGoogleEmail'), isNull);
      },
    );

    test('a cancelled sign-in stops quietly', () async {
      final cubit = buildGoogleCubit(
        FakeGoogleAuthFlow(signIns: const [GoogleSignInCancelled()]),
      );
      expect(await cubit.signInWithGoogle(), isA<GoogleSignInStopped>());
    });

    test('a sign-in without the Firebase permissions is refused', () async {
      final cubit = buildGoogleCubit(
        FakeGoogleAuthFlow(
          signIns: [
            googleCredentials(scopes: const ['openid']),
          ],
        ),
      );
      expect(
        await cubit.signInWithGoogle(),
        isA<GoogleSignInFailed>().having(
          (r) => r.message,
          'message',
          missingScopesMessage,
        ),
      );
      expect(await secrets.read('google:$testGoogleEmail'), isNull);
    });

    test(
      'adding the picked project saves the sign-in, selects it and serves its tokens',
      () async {
        final cubit = buildGoogleCubit(FakeGoogleAuthFlow());
        await cubit.load();
        final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
        expect(
          await cubit.addGoogleProjects(found.session, found.projects),
          isNull,
        );
        expect(cubit.state.selected, googleDemo);
        expect(await repository.loadAll(), [googleDemo]);
        expect(await repository.readSelectedProjectId(), testProjectId);
        expect(
          await secrets.read('google:$testGoogleEmail'),
          '{"refreshToken":"1//refresh-1"}',
        );
        expect(
          await registry.providerFor(googleDemo),
          same(found.session.provider),
        );
      },
    );

    test(
      'picking a project added with a key switches it to the account',
      () async {
        final cubit = buildGoogleCubit(FakeGoogleAuthFlow());
        await cubit.load();
        await cubit.addFromServiceAccount(
          serviceAccountJson(),
          persistKey: true,
        );
        await cubit.setEnvironment(testProjectId, ProjectEnvironment.prod);
        final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
        expect(
          await cubit.addGoogleProjects(found.session, found.projects),
          isNull,
        );
        expect(
          cubit.state.selected,
          googleDemo.copyWith(environment: ProjectEnvironment.prod),
        );
        expect(await secrets.read('sa:$testClientEmail'), isNull);
      },
    );

    test('picking several keeps the current selection', () async {
      final cubit = buildGoogleCubit(
        FakeGoogleAuthFlow(),
        listed: const [
          {'projectId': 'alpha-app', 'displayName': 'Alpha'},
          {'projectId': 'beta-app', 'displayName': 'Beta'},
        ],
      );
      await cubit.load();
      await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);
      final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
      await cubit.addGoogleProjects(found.session, found.projects);
      expect(cubit.state.projects.map((p) => p.id), [
        'alpha-app',
        'beta-app',
        testProjectId,
      ]);
      expect(cubit.state.selectedId, testProjectId);
    });

    test(
      'picking several with nothing selected selects the first by name',
      () async {
        final cubit = buildGoogleCubit(
          FakeGoogleAuthFlow(),
          listed: const [
            {'projectId': 'beta-app', 'displayName': 'Beta'},
            {'projectId': 'alpha-app', 'displayName': 'Alpha'},
          ],
        );
        await cubit.load();
        final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
        await cubit.addGoogleProjects(found.session, found.projects);
        expect(cubit.state.selectedId, 'alpha-app');
      },
    );

    test('signing in again stores the new sign-in and uses it', () async {
      final flow = FakeGoogleAuthFlow(
        signIns: [
          googleCredentials(),
          googleCredentials(
            token: 'ya29.google-2',
            refreshToken: '1//refresh-2',
          ),
        ],
      );
      final cubit = buildGoogleCubit(flow);
      await cubit.load();
      final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
      await cubit.addGoogleProjects(found.session, found.projects);

      expect(
        await cubit.signInAgain(const GoogleAccountRef(testGoogleEmail)),
        isNull,
      );
      expect(flow.calls, ['signIn -', 'signIn $testGoogleEmail']);
      expect(
        await secrets.read('google:$testGoogleEmail'),
        '{"refreshToken":"1//refresh-2"}',
      );
      final provider = await registry.providerFor(googleDemo);
      expect((await provider.getToken()).value, 'ya29.google-2');
    });

    test(
      'signing in again as another account is refused and keeps the old sign-in',
      () async {
        final cubit = buildGoogleCubit(
          FakeGoogleAuthFlow(),
          emails: const [testGoogleEmail, 'other@example.com'],
        );
        await cubit.load();
        final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
        await cubit.addGoogleProjects(found.session, found.projects);

        final message = await cubit.signInAgain(
          const GoogleAccountRef(testGoogleEmail),
        );
        expect(
          message,
          allOf(contains('other@example.com'), contains(testGoogleEmail)),
        );
        expect(
          await secrets.read('google:$testGoogleEmail'),
          '{"refreshToken":"1//refresh-1"}',
        );
      },
    );

    test('a cancelled sign-in-again says so', () async {
      final cubit = buildGoogleCubit(
        FakeGoogleAuthFlow(signIns: const [GoogleSignInCancelled()]),
      );
      expect(
        await cubit.signInAgain(const GoogleAccountRef(testGoogleEmail)),
        'Sign-in was cancelled.',
      );
    });
  });
}
