import '../../models/skill/invoked_skill_context.dart';

/// Builds the transcript-visible reminder text for an invoked skill.
class InvokedSkillReminderBuilder {
  const InvokedSkillReminderBuilder();

  String build(InvokedSkillContext context) {
    return [
      '<system-reminder>',
      'The following skills were invoked in this session. Continue to follow these guidelines:',
      '',
      '### Skill: ${context.name}',
      'Path: ${context.qualifiedPath}',
      '',
      'Base directory for this skill: ${context.baseDirectory}',
      '',
      context.instructionBody,
      '</system-reminder>',
    ].join('\n');
  }
}
