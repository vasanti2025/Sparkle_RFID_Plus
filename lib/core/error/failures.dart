import '../constants/app_strings.dart';

abstract class Failure {
  const Failure(this.message);

  final String message;
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = AppStrings.serverError]);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = AppStrings.cacheError]);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = AppStrings.noInternet]);
}

class ValidationFailure extends Failure {
  const ValidationFailure([super.message = AppStrings.invalidInput]);
}
