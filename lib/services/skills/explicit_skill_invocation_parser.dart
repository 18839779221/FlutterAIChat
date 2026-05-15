import '../../models/skill/invoked_skill_context.dart';
import '../../models/skill/skill_descriptor.dart';
import 'skill_runtime_service.dart';

class ExplicitSkillInvocationParseResult {
  final String cleanedUserText;
  final InvokedSkillContext? invokedSkill;

  const ExplicitSkillInvocationParseResult({
    required this.cleanedUserText,
    this.invokedSkill,
  });
}

/// Parses explicit user-entered skill tokens like `/verify` from the input box.
class ExplicitSkillInvocationParser {
  const ExplicitSkillInvocationParser({
    required SkillRuntimeService skillRuntimeService,
  }) : _skillRuntimeService = skillRuntimeService;

  final SkillRuntimeService _skillRuntimeService;

  Future<ExplicitSkillInvocationParseResult> parse(String input) async {
    final trimmed = input.trim();
    if (!trimmed.startsWith('/')) {
      return ExplicitSkillInvocationParseResult(cleanedUserText: input);
    }

    final match = RegExp(r'^/([^\s]+)(?:\s+(.*))?$').firstMatch(trimmed);
    if (match == null) {
      return ExplicitSkillInvocationParseResult(cleanedUserText: input);
    }

    final lookup = match.group(1)?.trim() ?? '';
    if (lookup.isEmpty) {
      return ExplicitSkillInvocationParseResult(cleanedUserText: input);
    }

    final descriptor = await _skillRuntimeService.loadSkillById(lookup);
    if (descriptor == null || !descriptor.isEnabled) {
      return ExplicitSkillInvocationParseResult(cleanedUserText: input);
    }

    return ExplicitSkillInvocationParseResult(
      cleanedUserText: (match.group(2) ?? '').trim(),
      invokedSkill: _toInvokedContext(descriptor),
    );
  }

  InvokedSkillContext _toInvokedContext(SkillDescriptor descriptor) {
    return InvokedSkillContext(
      skillId: descriptor.id,
      name: descriptor.name,
      qualifiedPath: descriptor.skillRootPath,
      baseDirectory: descriptor.skillRootPath,
      instructionBody: descriptor.bodyText,
    );
  }
}
