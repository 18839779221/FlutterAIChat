import '../../models/skill/invoked_skill_context.dart';
import 'skill_context_formatter.dart';

/// Builds the transcript-visible reminder text for an invoked skill.
class InvokedSkillReminderBuilder {
  const InvokedSkillReminderBuilder({
    SkillContextFormatter formatter = const SkillContextFormatter(),
  }) : _formatter = formatter;

  final SkillContextFormatter _formatter;

  String build(InvokedSkillContext context) {
    return _formatter.formatInvokedReminder(
      _formatter.prepareInvokedContext(context),
    );
  }
}
