import 'package:flutter/material.dart';

class ComposerTextEditingController extends TextEditingController {
  int? _draftRangeStart;
  int? _draftRangeEnd;

  void updateSpeechDraftRange({
    required int? start,
    required int? end,
  }) {
    if (_draftRangeStart == start && _draftRangeEnd == end) {
      return;
    }
    _draftRangeStart = start;
    _draftRangeEnd = end;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = value.text;
    final start = _draftRangeStart;
    final end = _draftRangeEnd;
    if (text.isEmpty ||
        start == null ||
        end == null ||
        start < 0 ||
        end < start ||
        end > text.length) {
      return TextSpan(style: style, text: text);
    }

    final underlineStyle = (style ?? const TextStyle()).copyWith(
      decoration: TextDecoration.underline,
      decorationThickness: 1.6,
    );

    return TextSpan(
      style: style,
      children: [
        if (start > 0) TextSpan(text: text.substring(0, start)),
        if (end > start)
          TextSpan(
            text: text.substring(start, end),
            style: underlineStyle,
          ),
        if (end < text.length) TextSpan(text: text.substring(end)),
      ],
    );
  }
}
