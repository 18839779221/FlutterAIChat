import '../models/chat_turn.dart';
import '../storage/chat_storage.dart';

class ChatTurnRepository {
  final ChatStorage _storage;

  ChatTurnRepository(this._storage);

  Future<int> createTurn(ChatTurn turn) {
    return _storage.insertTurn(turn);
  }

  Future<ChatTurn?> getTurn(int id) {
    return _storage.getTurn(id);
  }

  Future<List<ChatTurn>> getTurnsByGroup(int groupId) {
    return _storage.getTurnsByGroup(groupId);
  }

  Future<void> incrementIteration(int turnId) async {
    final turn = await _requireTurn(turnId);
    await _storage.updateTurn(
      turn.copyWith(
        iterationCount: turn.iterationCount + 1,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> incrementToolCallCount(int turnId, {int by = 1}) async {
    final turn = await _requireTurn(turnId);
    await _storage.updateTurn(
      turn.copyWith(
        toolCallCount: turn.toolCallCount + by,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> updateRuntimeState(
    int turnId, {
    ChatTurnProviderStyle? providerStyle,
    String? modelName,
    Map<String, dynamic>? providerStateJson,
  }) async {
    final turn = await _requireTurn(turnId);
    await _storage.updateTurn(
      turn.copyWith(
        providerStyle: providerStyle ?? turn.providerStyle,
        modelName: modelName ?? turn.modelName,
        providerStateJson: providerStateJson ?? turn.providerStateJson,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markAwaitingToolConfirmation(int turnId) async {
    final turn = await _requireTurn(turnId);
    await _storage.updateTurn(
      turn.copyWith(
        status: ChatTurnStatus.awaitingToolConfirmation,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markAwaitingUserInteraction(int turnId) async {
    final turn = await _requireTurn(turnId);
    await _storage.updateTurn(
      turn.copyWith(
        status: ChatTurnStatus.awaitingUserInteraction,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markRunning(int turnId) async {
    final turn = await _requireTurn(turnId);
    await _storage.updateTurn(
      turn.copyWith(
        status: ChatTurnStatus.running,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markCancelled(int turnId, {String? stopReason}) async {
    final turn = await _requireTurn(turnId);
    await _storage.updateTurn(
      turn.copyWith(
        status: ChatTurnStatus.cancelled,
        stopReason: stopReason ?? turn.stopReason,
        completedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> incrementIterationAndToolCount(int turnId) async {
    final turn = await _requireTurn(turnId);
    await _storage.updateTurn(
      turn.copyWith(
        iterationCount: turn.iterationCount + 1,
        toolCallCount: turn.toolCallCount + 1,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markCompleted(
    int turnId, {
    String? stopReason,
    String? finalResponseText,
  }) async {
    final turn = await _requireTurn(turnId);
    await _storage.updateTurn(
      turn.copyWith(
        status: ChatTurnStatus.completed,
        stopReason: stopReason ?? turn.stopReason,
        finalResponseText: finalResponseText ?? turn.finalResponseText,
        completedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markFailed(int turnId, {String? errorMessage}) async {
    final turn = await _requireTurn(turnId);
    await _storage.updateTurn(
      turn.copyWith(
        status: ChatTurnStatus.failed,
        errorMessage: errorMessage ?? turn.errorMessage,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<ChatTurn> _requireTurn(int turnId) async {
    final turn = await _storage.getTurn(turnId);
    if (turn == null) {
      throw StateError('Turn $turnId not found');
    }
    return turn;
  }
}
