import '../entities/user.dart';
import '../repositories/auth_repository.dart';

class RestoreSession {
  const RestoreSession(this.repository);

  final AuthRepository repository;

  Future<User?> call() => repository.restoreSession();
}
