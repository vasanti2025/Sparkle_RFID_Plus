import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/result.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

class LoginParams {
  const LoginParams({
    required this.username,
    required this.password,
    required this.rememberMe,
  });

  final String username;
  final String password;
  final bool rememberMe;
}

class Login implements UseCase<User, LoginParams> {
  const Login(this.repository);

  final AuthRepository repository;

  @override
  Future<Result<User>> call(LoginParams params) {
    return repository.login(
      username: params.username,
      password: params.password,
      rememberMe: params.rememberMe,
    );
  }
}
