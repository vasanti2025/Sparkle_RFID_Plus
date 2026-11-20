import '../repositories/auth_repository.dart';

class GetRememberedUsername {
  const GetRememberedUsername(this.repository);

  final AuthRepository repository;

  Future<String?> call() => repository.rememberedUsername();

  Future<String?> password() => repository.rememberedPassword();
}
