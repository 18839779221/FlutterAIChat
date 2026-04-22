import '../../services/prompt/prompt_locale.dart';

/// Localized tool-facing text with English as the default source.
class LocalizedToolText {
  final String english;
  final String? chinese;

  const LocalizedToolText({
    required this.english,
    this.chinese,
  });

  const LocalizedToolText.englishOnly(this.english) : chinese = null;

  String resolve(PromptLocale locale) {
    switch (locale) {
      case PromptLocale.chinese:
        final localized = chinese?.trim();
        if (localized != null && localized.isNotEmpty) {
          return localized;
        }
        return english;
      case PromptLocale.english:
        return english;
    }
  }
}
