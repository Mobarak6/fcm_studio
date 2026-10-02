import 'package:equatable/equatable.dart';

/// Written into every stored project record, for future migrations.
const kProjectSchemaVersion = 1;

enum ProjectEnvironment { dev, staging, prod }

/// Which credential a project uses: a service account key or a Google account (spec §4.2).
sealed class CredentialRef extends Equatable {
  const CredentialRef();

  /// The SecretStore key that holds this credential's secret.
  String get secretKey;

  Map<String, Object?> toJson();

  static CredentialRef fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'service_account' => ServiceAccountRef(json['clientEmail']! as String),
        'google_account' => GoogleAccountRef(json['email']! as String),
        final kind => throw FormatException('Unknown credential kind: $kind'),
      };
}

final class ServiceAccountRef extends CredentialRef {
  const ServiceAccountRef(this.clientEmail);

  final String clientEmail;

  @override
  String get secretKey => 'sa:$clientEmail';

  @override
  Map<String, Object?> toJson() => {
    'kind': 'service_account',
    'clientEmail': clientEmail,
  };

  @override
  List<Object?> get props => [clientEmail];
}

final class GoogleAccountRef extends CredentialRef {
  const GoogleAccountRef(this.email);

  /// Lowercase (plan Decision 13).
  final String email;

  @override
  String get secretKey => 'google:$email';

  @override
  Map<String, Object?> toJson() => {'kind': 'google_account', 'email': email};

  @override
  List<Object?> get props => [email];
}

class Project extends Equatable {
  const Project({
    required this.id,
    required this.displayName,
    required this.credential,
    this.projectNumber,
    this.environment = ProjectEnvironment.dev,
  });

  factory Project.fromJson(Map<String, Object?> json) => Project(
    id: json['id']! as String,
    displayName: json['displayName']! as String,
    projectNumber: json['projectNumber'] as String?,
    environment: ProjectEnvironment.values.byName(
      json['environment']! as String,
    ),
    credential: CredentialRef.fromJson(
      json['credential']! as Map<String, Object?>,
    ),
  );

  /// The Firebase project ID, e.g. `demo-project`.
  final String id;
  final String displayName;

  /// Firebase project number (= FCM sender ID). Optional.
  final String? projectNumber;
  final ProjectEnvironment environment;
  final CredentialRef credential;

  String get label => displayName == id ? id : '$displayName ($id)';

  Project copyWith({
    String? displayName,
    String? Function()? projectNumber,
    ProjectEnvironment? environment,
    CredentialRef? credential,
  }) {
    return Project(
      id: id,
      displayName: displayName ?? this.displayName,
      projectNumber: projectNumber != null
          ? projectNumber()
          : this.projectNumber,
      environment: environment ?? this.environment,
      credential: credential ?? this.credential,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': kProjectSchemaVersion,
    'id': id,
    'displayName': displayName,
    'projectNumber': projectNumber,
    'environment': environment.name,
    'credential': credential.toJson(),
  };

  @override
  List<Object?> get props => [
    id,
    displayName,
    projectNumber,
    environment,
    credential,
  ];
}
