import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/speech_controller.dart';
import '../providers/chat_providers.dart';
import '../providers/speech_providers.dart';

class ChatInput extends ConsumerStatefulWidget {
  const ChatInput({super.key});

  @override
  ConsumerState<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<ChatInput>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _voiceAnimationController;
  late final FocusNode _focusNode;
  bool _isInputFocused = false;
  String _speechDraftPrefix = '';
  bool _isVoicePressActive = false;
  bool _isStoppingFromGesture = false;
  Timer? _longPressTimer;
  int? _activePointer;
  Offset? _pointerDownPosition;
  bool _didTriggerVoiceByPress = false;
  bool _willCancelBySlide = false;
  double _slideUpDistance = 0;

  static const Duration _voicePressDelay = Duration(milliseconds: 280);
  static const double _voicePressSlop = 16;
  static const double _slideCancelThreshold = 74;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _focusNode = ref.read(focusNodeProvider);
    _isInputFocused = _focusNode.hasFocus;
    _focusNode.addListener(_onFocusChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listen<String>(speechTextProvider, (previous, next) {
        if (next.trim().isNotEmpty) {
          _mergeSpeechResultIntoInput(next);
        }
      });

      ref.listen<bool>(isListeningProvider, (previous, next) {
        if (next) {
          _speechDraftPrefix = ref.read(textControllerProvider).text.trim();
          _voiceAnimationController.repeat();
        } else {
          _voiceAnimationController.stop();
          _voiceAnimationController.reset();
        }
      });

      ref.listen<String?>(speechErrorProvider, (previous, next) {
        if (next == null || next.trim().isEmpty || !mounted) {
          return;
        }

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(next),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );

        ref.read(speechControllerProvider).clearError();
      });
    });
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChanged);
    _voiceAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && ref.read(isListeningProvider)) {
      _finishVoicePress();
    }
    if (state != AppLifecycleState.resumed) {
      _clearPointerTracking();
    }
  }

  void _onFocusChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isInputFocused = _focusNode.hasFocus;
    });
  }

  void _mergeSpeechResultIntoInput(String speechText) {
    final textController = ref.read(textControllerProvider);
    final recognized = speechText.trim();
    final mergedText = _speechDraftPrefix.isEmpty
        ? recognized
        : '${_speechDraftPrefix.trim()} $recognized';

    if (textController.text == mergedText) {
      return;
    }

    textController.value = textController.value.copyWith(
      text: mergedText,
      selection: TextSelection.collapsed(offset: mergedText.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _startListeningByLongPress() async {
    _isVoicePressActive = true;
    final speechController = ref.read(speechControllerProvider);
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    await speechController.startListening();
    if (!ref.read(isListeningProvider)) {
      _isVoicePressActive = false;
    }
  }

  Future<void> _stopListeningByLongPress() async {
    final speechController = ref.read(speechControllerProvider);
    await speechController.stopListening();
  }

  Future<void> _finishVoicePress({bool cancelResult = false}) async {
    if (_isStoppingFromGesture) {
      return;
    }
    if (!_isVoicePressActive && !ref.read(isListeningProvider)) {
      return;
    }

    _isStoppingFromGesture = true;
    _isVoicePressActive = false;
    try {
      await _stopListeningByLongPress();
      if (cancelResult) {
        final textController = ref.read(textControllerProvider);
        final restoredText = _speechDraftPrefix.trim();
        textController.value = textController.value.copyWith(
          text: restoredText,
          selection: TextSelection.collapsed(offset: restoredText.length),
          composing: TextRange.empty,
        );
        ref.read(speechTextProvider.notifier).state = '';
      }
    } finally {
      _isStoppingFromGesture = false;
    }
  }

  void _onVoicePointerDown(PointerDownEvent event) {
    if (_activePointer != null) {
      return;
    }

    _activePointer = event.pointer;
    _pointerDownPosition = event.position;
    _didTriggerVoiceByPress = false;
    _willCancelBySlide = false;
    _slideUpDistance = 0;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_voicePressDelay, () async {
      if (_activePointer != event.pointer || _pointerDownPosition == null) {
        return;
      }
      _didTriggerVoiceByPress = true;
      if (mounted) {
        setState(() {});
      }
      await _startListeningByLongPress();
    });
  }

  void _onVoicePointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer || _pointerDownPosition == null) {
      return;
    }

    final dx = event.position.dx - _pointerDownPosition!.dx;
    final dy = event.position.dy - _pointerDownPosition!.dy;
    final moveDistance = math.sqrt(dx * dx + dy * dy);

    if (!_didTriggerVoiceByPress) {
      if (moveDistance > _voicePressSlop) {
        _longPressTimer?.cancel();
      }
      return;
    }

    final upDistance =
        (_pointerDownPosition!.dy - event.position.dy).clamp(0, 160).toDouble();
    final willCancel = upDistance >= _slideCancelThreshold;
    if (willCancel != _willCancelBySlide ||
        (upDistance - _slideUpDistance).abs() > 1.5) {
      setState(() {
        _willCancelBySlide = willCancel;
        _slideUpDistance = upDistance;
      });
    }
  }

  Future<void> _onVoicePointerRelease(int pointer) async {
    if (_activePointer != pointer) {
      return;
    }

    _longPressTimer?.cancel();
    final shouldFinish = _didTriggerVoiceByPress ||
        _isVoicePressActive ||
        ref.read(isListeningProvider);
    final shouldCancel = _willCancelBySlide;
    _clearPointerTracking();

    if (shouldFinish) {
      await _finishVoicePress(cancelResult: shouldCancel);
    }
  }

  void _clearPointerTracking() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _activePointer = null;
    _pointerDownPosition = null;
    _didTriggerVoiceByPress = false;
    if (_willCancelBySlide || _slideUpDistance > 0) {
      if (mounted) {
        setState(() {
          _willCancelBySlide = false;
          _slideUpDistance = 0;
        });
      } else {
        _willCancelBySlide = false;
        _slideUpDistance = 0;
      }
      return;
    }
    _willCancelBySlide = false;
    _slideUpDistance = 0;
  }

  void _sendText() {
    final textController = ref.read(textControllerProvider);
    final chatController = ref.read(chatControllerProvider);
    final text = textController.text.trim();
    if (text.isEmpty) {
      return;
    }
    chatController.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final isGenerating = ref.watch(isGeneratingProvider);
    final useReasoning = ref.watch(useReasoningProvider);
    final useConciseMode = ref.watch(useConciseModeProvider);
    final textController = ref.watch(textControllerProvider);
    final chatController = ref.read(chatControllerProvider);

    final isListening = ref.watch(isListeningProvider);
    final speechText = ref.watch(speechTextProvider).trim();
    final speechError = ref.watch(speechErrorProvider);
    final showSpeechStatus = isListening ||
        speechText.isNotEmpty ||
        (speechError?.isNotEmpty ?? false);

    final bottomHomeHeight = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin:
          EdgeInsets.only(bottom: keyboardHeight > 0 ? 0 : bottomHomeHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildModeButton(
                context: context,
                label: '深度思考',
                active: useReasoning,
                onPressed: () => chatController.setUseReasoning(!useReasoning),
              ),
              const SizedBox(width: 8),
              _buildModeButton(
                context: context,
                label: '简洁模式',
                active: useConciseMode,
                onPressed: () =>
                    chatController.setUseConciseMode(!useConciseMode),
              ),
            ],
          ),
          if (showSpeechStatus) ...[
            const SizedBox(height: 8),
            if (isListening)
              AnimatedBuilder(
                animation: _voiceAnimationController,
                builder: (context, child) {
                  return _SpeechStatusBar(
                    isListening: isListening,
                    speechText: speechText,
                    speechError: speechError,
                    willCancel: _willCancelBySlide,
                    voiceProgress: _voiceAnimationController.value,
                    slideProgress: (_slideUpDistance / _slideCancelThreshold)
                        .clamp(0.0, 1.0),
                  );
                },
              )
            else
              _SpeechStatusBar(
                isListening: isListening,
                speechText: speechText,
                speechError: speechError,
                willCancel: _willCancelBySlide,
                voiceProgress: 0,
                slideProgress: 0,
              ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 148),
                  decoration: BoxDecoration(
                    color: isListening
                        ? Theme.of(context).primaryColor.withValues(alpha: 0.08)
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow
                            .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isListening
                          ? Theme.of(context)
                              .primaryColor
                              .withValues(alpha: 0.75)
                          : Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _onVoicePointerDown,
                    onPointerMove: _onVoicePointerMove,
                    onPointerUp: (event) =>
                        _onVoicePointerRelease(event.pointer),
                    onPointerCancel: (event) =>
                        _onVoicePointerRelease(event.pointer),
                    child: Stack(
                      children: [
                        TextField(
                          focusNode: _focusNode,
                          controller: textController,
                          maxLines: null,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          enableInteractiveSelection: false,
                          decoration: InputDecoration(
                            hintText: isListening
                                ? '正在语音输入，松开即停止...'
                                : (_isInputFocused ? '发消息...' : '单击输入，长按语音...'),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                          ),
                          onSubmitted: (text) {
                            if (text.trim().isNotEmpty) {
                              chatController.sendMessage(text);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: MaterialButton(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  color: Theme.of(context).primaryColor,
                  onPressed: () {
                    if (isGenerating) {
                      chatController.cancelStreamSubscription();
                    } else {
                      _sendText();
                    }
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: isGenerating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required BuildContext context,
    required String label,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: active ? Theme.of(context).primaryColor : Colors.grey[300]!,
            width: 1,
          ),
        ),
        backgroundColor: active
            ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
            : Colors.transparent,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Theme.of(context).primaryColor : Colors.grey[600],
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _SpeechStatusBar extends StatelessWidget {
  final bool isListening;
  final String speechText;
  final String? speechError;
  final bool willCancel;
  final double voiceProgress;
  final double slideProgress;

  const _SpeechStatusBar({
    required this.isListening,
    required this.speechText,
    required this.speechError,
    required this.willCancel,
    required this.voiceProgress,
    required this.slideProgress,
  });

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color iconColor;
    late final String title;

    if (isListening) {
      icon = willCancel ? Icons.cancel_outlined : Icons.graphic_eq_rounded;
      iconColor = willCancel ? Colors.orange : Colors.redAccent;
      title = willCancel ? '松开将取消本次语音输入' : '录音中，上滑可取消，松开结束';
    } else if (speechError != null && speechError!.isNotEmpty) {
      icon = Icons.error_outline_rounded;
      iconColor = Colors.orange;
      title = '语音识别失败，请重试';
    } else {
      icon = Icons.check_circle_outline_rounded;
      iconColor = Colors.green;
      title = '语音已转文字，可直接编辑并发送';
    }

    final tone = willCancel ? Colors.orange : Colors.redAccent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isListening
              ? [
                  tone.withValues(alpha: 0.1),
                  tone.withValues(alpha: 0.04),
                ]
              : [
                  Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.52),
                  Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.52),
                ],
        ),
        border: Border.all(
          color: isListening
              ? tone.withValues(alpha: 0.34)
              : Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (isListening) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: slideProgress,
                      backgroundColor: tone.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        tone.withValues(alpha: 0.84),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 88,
                  height: 15,
                  child: CustomPaint(
                    painter: _EqualizerPainter(
                      progress: voiceProgress,
                      color: tone,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (speechText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              speechText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _EqualizerPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gradient = LinearGradient(
      colors: [
        color.withValues(alpha: 0.25),
        color.withValues(alpha: 0.92),
        color.withValues(alpha: 0.25),
      ],
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = gradient.createShader(Offset.zero & size);

    const bars = 24;
    const barWidth = 2.0;
    final spacing = (size.width - bars * barWidth) / (bars + 1);
    final centerY = size.height / 2;
    final maxHeight = size.height * 0.92;
    const middle = (bars - 1) / 2;

    for (var i = 0; i < bars; i++) {
      final x = spacing + i * (barWidth + spacing) + barWidth / 2;
      final centerDistance =
          ((i - middle).abs() / middle).clamp(0, 1).toDouble();
      final envelope = 1 - centerDistance * 0.62;
      final wave =
          0.5 + 0.5 * math.sin(progress * 2 * math.pi * 1.45 + i * 0.53);
      final dynamicFactor = (0.22 + wave * 0.78) * envelope;
      final barHeight = dynamicFactor * maxHeight;

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
