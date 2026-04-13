import '../models/agent/chat_turn_step.dart';
import '../storage/chat_storage.dart';

class ChatTurnStepRepository {
  final ChatStorage _storage;

  ChatTurnStepRepository(this._storage);

  Future<int> createStep(ChatTurnStep step) {
    return _storage.insertTurnStep(step);
  }

  Future<List<ChatTurnStep>> listSteps(int turnId) {
    return _storage.getTurnSteps(turnId);
  }

  Future<ChatTurnStep?> getStep(int id) {
    return _storage.getTurnStep(id);
  }

  Future<void> updateStep(ChatTurnStep step) {
    return _storage.updateTurnStep(step);
  }

  Future<void> markRunning(int stepId) async {
    final step = await _requireStep(stepId);
    await _storage.updateTurnStep(
      step.copyWith(
        status: ChatTurnStepStatus.running,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markCompleted(
    int stepId, {
    required String resultSummary,
    Map<String, dynamic>? resultJson,
  }) async {
    final step = await _requireStep(stepId);
    await _storage.updateTurnStep(
      step.copyWith(
        status: ChatTurnStepStatus.completed,
        resultSummary: resultSummary,
        resultJson: resultJson ?? step.resultJson,
        updatedAt: DateTime.now(),
        completedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markFailed(
    int stepId, {
    required String errorCode,
    String? resultSummary,
    Map<String, dynamic>? resultJson,
  }) async {
    final step = await _requireStep(stepId);
    await _storage.updateTurnStep(
      step.copyWith(
        status: ChatTurnStepStatus.failed,
        errorCode: errorCode,
        resultSummary: resultSummary ?? step.resultSummary,
        resultJson: resultJson ?? step.resultJson,
        updatedAt: DateTime.now(),
        completedAt: DateTime.now(),
      ),
    );
  }

  Future<ChatTurnStep> _requireStep(int stepId) async {
    final step = await _storage.getTurnStep(stepId);
    if (step != null) {
      return step;
    }
    throw StateError('Turn step $stepId not found');
  }
}
