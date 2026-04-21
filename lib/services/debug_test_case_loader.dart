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

    final rawCases = decoded['cases'];
    if (rawCases is! List) {
      throw const FormatException('Debug test case cases 必须是数组');
    }

    final parsedCases = rawCases.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Debug test case case 元素必须是对象');
      }
      return DebugTestCase.fromJson(item);
    }).toList(growable: false);
    _validateUniqueIds(parsedCases);

    return DebugTestCaseLibrary(
      allCases:
          parsedCases.where((item) => item.enabled).toList(growable: false),
    );
  }

  void _validateUniqueIds(List<DebugTestCase> cases) {
    final seen = <String>{};
    for (final item in cases) {
      if (!seen.add(item.id)) {
        throw FormatException('Debug test case id 重复: ${item.id}');
      }
    }
  }
}
