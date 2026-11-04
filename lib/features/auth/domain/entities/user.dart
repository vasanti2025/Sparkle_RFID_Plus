class User {
  const User({
    required this.id,
    required this.username,
    this.token = '',
    this.displayName = '',
    this.clientCode = '',
    this.branchId = 0,
    this.roleId = 0,
    this.branchName = '',
    this.organisationName = '',
    this.notice,
  });

  final String id;
  final String username;
  final String token;
  final String displayName;
  final String clientCode;
  final int branchId;
  final int roleId;
  final String branchName;
  final String organisationName;
  final String? notice;
}
