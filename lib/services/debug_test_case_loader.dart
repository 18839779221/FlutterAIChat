import 'dart:convert';

import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:flutter/services.dart';

abstract class DebugTestCaseLoader {
  Future<DebugTestCaseLibrary> load();
}

class AssetDebugTestCaseLoader implements DebugTestCaseLoader {
  static const String assetPath = 'assets/debug/test_cases.json';

  final AssetBundle _assetBundle;

  AssetDebugTestCaseLoader({
    AssetBundle? assetBundle,
  }) : _assetBundle = assetBundle ?? rootBundle;

  @override
  Future<DebugTestCaseLibrary> load() async {
    final rawJson = await _assetBundle.loadString(assetPath);
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Debug test case root 必须是对象');
    }

    final version = decoded['version'];
    if (version is! int) {
      throw const FormatException('Debug test case version 必须是整数');
    }

    final rawCases = decoded['cases'];
    if (rawCases is! List) {
      throw const FormatException('Debug test case cases 必须是数组');
    }

    final allCases = rawCases
        .whereType<Map<String, dynamic>>()
        .map(DebugTestCase.fromJson)
        .where((item) => item.enabled)
        .toList(growable: false);

    return DebugTestCaseLibrary(
      version: version,
      allCases: allCases,
    );
  }
}
