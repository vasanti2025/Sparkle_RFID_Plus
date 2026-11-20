import '../../../../core/utils/result.dart';
import '../entities/user.dart';

abstract class AuthRepository {
  Future<Result<User>> login({
    required String username,
    required String password,
    required bool rememberMe,
  });

  Future<String?> rememberedUsername();

  Future<String?> rememberedPassword();

  Future<User?> restoreSession();

  Future<void> signOut();
}
