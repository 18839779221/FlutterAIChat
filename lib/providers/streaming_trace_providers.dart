import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/services/debug/streaming_trace_recorder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight overlay visibility state for the runtime-only streaming trace UI.
class StreamingTraceOverlayState {
  const StreamingTraceOverlayState({
    required this.isVisible,
    this.anchorId,
  });

  final bool isVisible;
  final String? anchorId;

  StreamingTraceOverlayState copyWith({
    bool? isVisible,
    String? anchorId,
  }) {
    return StreamingTraceOverlayState(
      isVisible: isVisible ?? this.isVisible,
      anchorId: anchorId,
    );
  }
}

/// Coordinates long-press open/close behavior for the streaming trace overlay.
class StreamingTraceOverlayController
    extends StateNotifier<StreamingTraceOverlayState> {
  StreamingTraceOverlayController()
      : super(const StreamingTraceOverlayState(isVisible: false));

  void show({
    required String anchorId,
    required bool hasActiveTrace,
  }) {
    if (!hasActiveTrace) {
      return;
    }
    state = StreamingTraceOverlayState(
      isVisible: true,
      anchorId: anchorId,
    );
  }

  void close() {
    if (!state.isVisible) {
      return;
    }
    state = const StreamingTraceOverlayState(isVisible: false);
  }

  void closeIfAnchorDisappeared() {
    close();
  }
}

final streamingTraceRecorderProvider = StateNotifierProvider<
    StreamingTraceRecorder, StreamingTraceSnapshot?>((ref) {
  return StreamingTraceRecorder();
});

final streamingTraceSnapshotProvider = Provider<StreamingTraceSnapshot?>((ref) {
  return ref.watch(streamingTraceRecorderProvider);
});

final streamingTraceOverlayControllerProvider = StateNotifierProvider<
    StreamingTraceOverlayController, StreamingTraceOverlayState>((ref) {
  return StreamingTraceOverlayController();
});
