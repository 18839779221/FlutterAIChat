import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../models/skill/skill_catalog_entry.dart';
import '../../models/prompt/runtime_user_context_snapshot.dart';
import '../skills/skill_context_formatter.dart';

typedef RuntimeNowProvider = DateTime Function();
typedef AgentsMdProvider = Future<String> Function();
typedef RuntimePlatformContextProvider = List<String> Function();
typedef RuntimeSkillCatalogProvider = Future<List<SkillCatalogEntry>>
    Function();

class RuntimeUserContextService {
  RuntimeUserContextService({
    RuntimeNowProvider? nowProvider,
    AgentsMdProvider? agentsMdProvider,
    RuntimePlatformContextProvider? platformContextProvider,
    RuntimeSkillCatalogProvider? skillCatalogProvider,
    SkillContextFormatter skillContextFormatter = const SkillContextFormatter(),
  })  : _nowProvider = nowProvider ?? DateTime.now,
        _agentsMdProvider = agentsMdProvider ?? _defaultAgentsMdProvider,
        _platformContextProvider =
            platformContextProvider ?? _defaultPlatformContextProvider,
        _skillCatalogProvider =
            skillCatalogProvider ?? _defaultSkillCatalogProvider,
        _skillContextFormatter = skillContextFormatter;

  final RuntimeNowProvider _nowProvider;
  final AgentsMdProvider _agentsMdProvider;
  final RuntimePlatformContextProvider _platformContextProvider;
  final RuntimeSkillCatalogProvider _skillCatalogProvider;
  final SkillContextFormatter _skillContextFormatter;

  Future<RuntimeUserContextSnapshot> buildSnapshot() async {
    final now = _nowProvider();
    final platformSections = _platformContextProvider();
    final skillCatalog = await _skillCatalogProvider();
    return RuntimeUserContextSnapshot(
      currentDateText: "Today's date is ${_formatIsoDate(now)}.",
      agentsMdText: (await _agentsMdProvider()).trim(),
      skillsSectionText:
          _skillContextFormatter.formatCatalogReminder(skillCatalog),
      additionalSections: [
        if (platformSections.isNotEmpty)
          '# runtimePlatform\n${platformSections.join('\n')}',
      ],
    );
  }

  String buildCurrentMonthYearLabel() {
    final now = _nowProvider();
    return '${_englishMonthName(now.month)} ${now.year}';
  }

  static Future<String> _defaultAgentsMdProvider() async {
    return '';
  }

  static Future<List<SkillCatalogEntry>> _defaultSkillCatalogProvider() async {
    return const [];
  }

  static List<String> _defaultPlatformContextProvider() {
    final platformLabel = _resolvePlatformLabel();
    final formFactorLabel = _resolveFormFactorLabel();
    return <String>[
      'Current runtime platform: $platformLabel.',
      if (formFactorLabel != null)
        'Current device form factor: $formFactorLabel.',
      if (formFactorLabel == 'phone')
        'Prefer compact, touch-friendly layouts that fit narrow mobile screens without horizontal scrolling.',
      if (formFactorLabel == 'tablet')
        'Prefer touch-friendly layouts with stronger section spacing and a centered composition that still works comfortably in portrait.',
      if (platformLabel == 'macOS app')
        'You may use a wider centered layout, but keep text readable and avoid edge-to-edge content.',
    ];
  }

  static String _resolvePlatformLabel() {
    if (kIsWeb) {
      return 'web app';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android app';
      case TargetPlatform.iOS:
        return 'iOS app';
      case TargetPlatform.macOS:
        return 'macOS app';
      case TargetPlatform.windows:
        return 'Windows app';
      case TargetPlatform.linux:
        return 'Linux app';
      case TargetPlatform.fuchsia:
        return 'Android-like app';
    }
  }

  static String? _resolveFormFactorLabel() {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
      if (view == null) {
        return null;
      }
      final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
      final logicalHeight = view.physicalSize.height / view.devicePixelRatio;
      final shortestSide =
          logicalWidth < logicalHeight ? logicalWidth : logicalHeight;
      if (shortestSide >= 600) {
        return 'tablet';
      }
      if (shortestSide > 0) {
        return 'phone';
      }
      return null;
    } catch (_) {
      return null;
    }
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
