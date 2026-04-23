import '../../models/prompt/runtime_user_context_snapshot.dart';

typedef RuntimeNowProvider = DateTime Function();
typedef AgentsMdProvider = Future<String> Function();

class RuntimeUserContextService {
  RuntimeUserContextService({
    RuntimeNowProvider? nowProvider,
    AgentsMdProvider? agentsMdProvider,
  })  : _nowProvider = nowProvider ?? DateTime.now,
        _agentsMdProvider = agentsMdProvider ?? _defaultAgentsMdProvider;

  final RuntimeNowProvider _nowProvider;
  final AgentsMdProvider _agentsMdProvider;

  Future<RuntimeUserContextSnapshot> buildSnapshot() async {
    final now = _nowProvider();
    return RuntimeUserContextSnapshot(
      currentDateText: "Today's date is ${_formatIsoDate(now)}.",
      agentsMdText: (await _agentsMdProvider()).trim(),
    );
  }

  String buildCurrentMonthYearLabel() {
    final now = _nowProvider();
    return '${_englishMonthName(now.month)} ${now.year}';
  }

  static Future<String> _defaultAgentsMdProvider() async {
    return '';
  }

  static String _formatIsoDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _englishMonthName(int month) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month < 1 || month > months.length) {
      return 'Unknown';
    }
    return months[month - 1];
  }
}
