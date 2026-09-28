import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';

class TargetsState extends Equatable {
  const TargetsState({this.targets = const []});

  /// Most recently used first.
  final List<SavedTarget> targets;

  /// The saved target for [target], if it is saved.
  SavedTarget? matching(Target target) {
    for (final saved in targets) {
      if (saved.matches(target)) {
        return saved;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [targets];
}
