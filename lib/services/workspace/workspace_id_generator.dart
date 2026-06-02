import 'dart:math';

typedef WorkspaceRandomProvider = int Function(int max);

class WorkspaceIdGenerator {
  WorkspaceIdGenerator({
    WorkspaceRandomProvider? randomIntProvider,
  }) : _randomIntProvider =
           randomIntProvider ?? Random().nextInt;

  static const String defaultWorkspaceId = '.default';
  static const String _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  final WorkspaceRandomProvider _randomIntProvider;

  String generateAutoWorkspaceId({DateTime? now}) {
    final current = now ?? DateTime.now();
    final datePart =
        '${current.year.toString().padLeft(4, '0')}'
        '${current.month.toString().padLeft(2, '0')}'
        '${current.day.toString().padLeft(2, '0')}';
    final suffix = List.generate(
      6,
      (_) => _alphabet[_randomIntProvider(_alphabet.length)],
    ).join();
    return 'ws_${datePart}_$suffix';
  }
}
