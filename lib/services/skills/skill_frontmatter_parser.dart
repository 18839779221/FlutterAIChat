import 'package:yaml/yaml.dart';

/// Parsed metadata and body extracted from a `SKILL.md` file.
class SkillFrontmatterResult {
  /// Skill display name from frontmatter.
  final String name;

  /// Short user-facing description from frontmatter.
  final String description;

  /// Markdown body content after the frontmatter block.
  final String body;

  const SkillFrontmatterResult({
    required this.name,
    required this.description,
    required this.body,
  });
}

/// Thrown when a skill file does not contain the expected frontmatter shape.
class SkillFrontmatterFormatException implements Exception {
  final String message;

  const SkillFrontmatterFormatException(this.message);

  @override
  String toString() => 'SkillFrontmatterFormatException: $message';
}

class SkillFrontmatterParser {
  const SkillFrontmatterParser();

  SkillFrontmatterResult parse(String source) {
    final trimmed = source.trimLeft();
    if (!trimmed.startsWith('---')) {
      throw const SkillFrontmatterFormatException('Missing frontmatter block.');
    }

    final firstSeparator = trimmed.indexOf('---');
    final frontmatterStart = firstSeparator + 3;
    final remainder = trimmed.substring(frontmatterStart);
    final closingSeparatorIndex = remainder.indexOf('\n---');
    if (closingSeparatorIndex < 0) {
      throw const SkillFrontmatterFormatException('Unclosed frontmatter block.');
    }

    final frontmatterText = remainder.substring(0, closingSeparatorIndex).trim();
    final bodyStart = closingSeparatorIndex + 4;
    final body = remainder.substring(bodyStart).trimLeft();

    final dynamic decoded;
    try {
      decoded = loadYaml(frontmatterText);
    } catch (error) {
      throw SkillFrontmatterFormatException(
        'Invalid YAML frontmatter: $error',
      );
    }
    if (decoded is! YamlMap) {
      throw const SkillFrontmatterFormatException(
        'Frontmatter must decode to a map.',
      );
    }

    final name = decoded['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      throw const SkillFrontmatterFormatException('Missing name.');
    }

    final description = decoded['description']?.toString().trim() ?? '';
    if (description.isEmpty) {
      throw const SkillFrontmatterFormatException('Missing description.');
    }

    return SkillFrontmatterResult(
      name: name,
      description: description,
      body: body,
    );
  }
}
