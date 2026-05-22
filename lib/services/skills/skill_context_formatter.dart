import '../../models/skill/invoked_skill_context.dart';
import '../../models/skill/skill_catalog_entry.dart';

/// Formats planner-visible skill context with stable limits and metadata.
class SkillContextFormatter {
  final int maxCatalogItems;
  final int maxInstructionCharacters;

  const SkillContextFormatter({
    this.maxCatalogItems = 20,
    this.maxInstructionCharacters = 6000,
  });

  String formatCatalogReminder(List<SkillCatalogEntry> skills) {
    final enabled =
        skills.where((skill) => skill.isEnabled).toList(growable: false)
          ..sort((a, b) {
            final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return byName != 0 ? byName : a.id.compareTo(b.id);
          });
    if (enabled.isEmpty) {
      return '';
    }

    final limit = maxCatalogItems < 0 ? 0 : maxCatalogItems;
    final visible = enabled.take(limit).toList(growable: false);
    final omitted = enabled.length - visible.length;
    final lines = <String>[
      'The following skills are available for use with the Skill tool:',
      '',
      for (final skill in visible) '- ${skill.name}: ${skill.description}',
      if (omitted > 0)
        '... $omitted more ${omitted == 1 ? 'skill' : 'skills'} omitted.',
    ];
    return lines.join('\n');
  }

  InvokedSkillContext prepareInvokedContext(InvokedSkillContext context) {
    final limit = maxInstructionCharacters < 0 ? 0 : maxInstructionCharacters;
    if (context.instructionBody.length <= limit) {
      return context;
    }
    return InvokedSkillContext(
      skillId: context.skillId,
      name: context.name,
      qualifiedPath: context.qualifiedPath,
      baseDirectory: context.baseDirectory,
      instructionBody: context.instructionBody.substring(0, limit),
      instructionBodyTruncated: true,
      originalInstructionLength: context.instructionBody.length,
    );
  }

  String formatInvokedReminder(InvokedSkillContext context) {
    final lines = <String>[
      '<system-reminder>',
      'The following skills were invoked in this session. Continue to follow these guidelines:',
      '',
      '### Skill: ${context.name}',
      'Path: ${context.qualifiedPath}',
      '',
      'Base directory for this skill: ${context.baseDirectory}',
      '',
      context.instructionBody,
      if (context.instructionBodyTruncated) ...[
        '',
        '[truncated] Skill instructions were shortened from ${context.originalInstructionLength ?? 'unknown'} characters for planner context.',
      ],
      '</system-reminder>',
    ];
    return lines.join('\n');
  }
}
