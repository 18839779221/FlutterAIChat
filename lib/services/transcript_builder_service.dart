import '../models/chat_event.dart';
import '../repositories/chat_event_repository.dart';

class TranscriptBuilderService {
  final ChatEventRepository _eventRepository;

  TranscriptBuilderService({
    required ChatEventRepository eventRepository,
  }) : _eventRepository = eventRepository;

  Future<List<ChatEvent>> loadTranscript(int turnId) {
    return _eventRepository.listEventsByTurn(turnId);
  }
}
