import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_spec.dart';
import '../widgets/chat_glass_button.dart';
import '../widgets/chat_header_button.dart';
import '../widgets/chat_top_chrome_motion.dart';
import '../widgets/chat_top_bar_button.dart';

class HomeTopButtonsLabPage extends StatefulWidget {
  const HomeTopButtonsLabPage({super.key});

  @override
  State<HomeTopButtonsLabPage> createState() => _HomeTopButtonsLabPageState();
}

class _HomeTopButtonsLabPageState extends State<HomeTopButtonsLabPage> {
  bool _debugInspectorEnabled = true;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Scaffold(
      backgroundColor: colors.chatBackground,
      body: _HomeTopButtonsLabScene(
        radius: radius,
        spacing: spacing,
        colors: colors,
        debugInspectorEnabled: _debugInspectorEnabled,
        onToggleDebugInspector: () {
          setState(
            () => _debugInspectorEnabled = !_debugInspectorEnabled,
          );
        },
      ),
    );
  }
}

class _HomeTopButtonsLabScene extends StatefulWidget {
  const _HomeTopButtonsLabScene({
    required this.radius,
    required this.spacing,
    required this.colors,
    required this.debugInspectorEnabled,
    required this.onToggleDebugInspector,
  });

  final AppRadius radius;
  final AppSpacing spacing;
  final AppThemeSpec colors;
  final bool debugInspectorEnabled;
  final VoidCallback onToggleDebugInspector;

  @override
  State<_HomeTopButtonsLabScene> createState() =>
      _HomeTopButtonsLabSceneState();
}

class _HomeTopButtonsLabSceneState extends State<_HomeTopButtonsLabScene> {
  late final ScrollController _scrollController;
  double _scrollOffset = 0;

  ChatTopChromeMotion get _motion => ChatTopChromeMotion.fromScrollOffset(
        offset: _scrollOffset,
        transitionDistance: 40,
      );

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
  }

  void _handleScroll() {
    final nextOffset =
        (_scrollController.hasClients ? _scrollController.offset : 0.0)
            .toDouble();
    if ((_scrollOffset - nextOffset).abs() < 0.5) {
      return;
    }
    setState(() {
      _scrollOffset = nextOffset;
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const glassGradientColors = <Color>[
      Color(0xECFFFFFF),
      Color(0xCCFFFFFF),
      Color(0x96FBFAF7),
    ];
    const glassBorderColor = Color(0x73FFFFFF);
    const glassEdgeGlowColor = Color(0x8CFFFFFF);
    const glassTopHighlightColors = <Color>[
      Color(0xF5FFFFFF),
      Color(0x00FFFFFF),
    ];
    final motion = _motion;
    final gatherInsetDx = 6 * motion.groupInsetProgress;
    final delayedWorkspaceDx = 3 * motion.centerSettleProgress;
    const contentMaxWidth = 860.0;

    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xFFFCFBF8),
                  Color(0xFFF8F6F1),
                  Color(0xFFF2ECE3),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.colors.semantic.text.inverse.withValues(alpha: 0.08),
                  widget.colors.semantic.text.inverse.withValues(alpha: 0.03),
                  Colors.transparent,
                ],
                stops: const [0, 0.16, 0.42],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: SingleChildScrollView(
            key: const ValueKey('home-top-buttons-lab-scroll-view'),
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              widget.spacing.lg,
              92,
              widget.spacing.lg,
              132,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                child: _LabScrollRunway(
                  radius: widget.radius,
                  spacing: widget.spacing,
                  colors: widget.colors,
                ),
              ),
            ),
          ),
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: _LabTopOverlayVeil(),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            minimum: EdgeInsets.only(top: widget.spacing.xxs),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: widget.spacing.lg),
                  child: SizedBox(
                    key: const ValueKey('top-chrome-motion-host'),
                    height: 56,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const iconButtonSize = 46.0;
                        const workspaceLabel = 'default';
                        const rightButtonCount = 3;
                        final rightClusterWidth = rightButtonCount *
                                iconButtonSize +
                            (rightButtonCount - 1) * (widget.spacing.xxs + 2);
                        final workspaceButtonMaxWidth = (constraints.maxWidth -
                                iconButtonSize -
                                rightClusterWidth -
                                widget.spacing.xs -
                                widget.spacing.sm)
                            .clamp(64.0, 170.0);

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Transform.translate(
                              offset: Offset(gatherInsetDx, 0),
                              child: Row(
                                key: const ValueKey('header-left-cluster'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ChatTopBarButton(
                                    shellKey: const ValueKey(
                                      'header-menu-button-shell',
                                    ),
                                    buttonKey:
                                        const ValueKey('header-menu-button'),
                                    icon: Icons.menu,
                                    tooltip: '会话列表',
                                    onPressed: () {},
                                    motion: motion,
                                    shadowSpec:
                                        const ChatHeaderButtonShadowSpec(
                                      nearShadowAlpha: 0.13,
                                      nearShadowBlur: 26,
                                      nearShadowOffsetY: 10,
                                      farShadowAlpha: 0.1,
                                      farShadowBlur: 12,
                                      farShadowOffsetY: 5,
                                      highlightAlpha: 0.26,
                                    ),
                                  ),
                                  SizedBox(width: widget.spacing.xs),
                                  Transform.translate(
                                    offset: Offset(-delayedWorkspaceDx, 0),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: workspaceButtonMaxWidth,
                                      ),
                                      child: ChatTopBarButton(
                                        shellKey: const ValueKey(
                                          'header-workspace-button-shell',
                                        ),
                                        buttonKey: const ValueKey(
                                          'header-workspace-button',
                                        ),
                                        tooltip: workspaceLabel,
                                        label: workspaceLabel,
                                        width: workspaceButtonMaxWidth,
                                        onPressed: () {},
                                        motion: motion,
                                        shadowSpec:
                                            const ChatHeaderButtonShadowSpec(
                                          nearShadowAlpha: 0.09,
                                          nearShadowBlur: 20,
                                          nearShadowOffsetY: 7,
                                          farShadowAlpha: 0.06,
                                          farShadowBlur: 8,
                                          farShadowOffsetY: 3,
                                          highlightAlpha: 0.21,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            SizedBox(width: widget.spacing.sm),
                            Transform.translate(
                              offset: Offset(-gatherInsetDx, 0),
                              child: Row(
                                key: const ValueKey('header-right-cluster'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ChatTopBarButton(
                                    shellKey: const ValueKey(
                                      'header-new-chat-button-shell',
                                    ),
                                    buttonKey: const ValueKey(
                                      'header-new-chat-button',
                                    ),
                                    icon: Icons.add_rounded,
                                    tooltip: '新建对话',
                                    onPressed: () {},
                                    motion: motion,
                                    shadowSpec:
                                        const ChatHeaderButtonShadowSpec(
                                      nearShadowAlpha: 0.11,
                                      nearShadowBlur: 22,
                                      nearShadowOffsetY: 8,
                                      farShadowAlpha: 0.08,
                                      farShadowBlur: 9,
                                      farShadowOffsetY: 4,
                                      highlightAlpha: 0.24,
                                    ),
                                  ),
                                  SizedBox(width: widget.spacing.xxs + 2),
                                  ChatTopBarButton(
                                    shellKey: const ValueKey(
                                      'header-debug-cases-button-shell',
                                    ),
                                    buttonKey: const ValueKey(
                                      'debug-test-cases-button',
                                    ),
                                    icon: Icons.science_outlined,
                                    tooltip: '测试案例',
                                    onPressed: () {},
                                    motion: motion,
                                    shadowSpec:
                                        const ChatHeaderButtonShadowSpec(
                                      nearShadowAlpha: 0.1,
                                      nearShadowBlur: 21,
                                      nearShadowOffsetY: 8,
                                      farShadowAlpha: 0.07,
                                      farShadowBlur: 9,
                                      farShadowOffsetY: 4,
                                      highlightAlpha: 0.23,
                                    ),
                                  ),
                                  SizedBox(width: widget.spacing.xxs + 2),
                                  ChatTopBarButton(
                                    shellKey: const ValueKey(
                                      'header-debug-inspector-button-shell',
                                    ),
                                    buttonKey: const ValueKey(
                                      'debug-turn-inspector-button',
                                    ),
                                    icon: Icons.bug_report_outlined,
                                    tooltip: '调试检查器',
                                    onPressed: widget.debugInspectorEnabled
                                        ? widget.onToggleDebugInspector
                                        : null,
                                    motion: motion,
                                    shadowSpec:
                                        const ChatHeaderButtonShadowSpec(
                                      nearShadowAlpha: 0.1,
                                      nearShadowBlur: 21,
                                      nearShadowOffsetY: 8,
                                      farShadowAlpha: 0.07,
                                      farShadowBlur: 9,
                                      farShadowOffsetY: 4,
                                      highlightAlpha: 0.23,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.fromLTRB(
              widget.spacing.lg,
              0,
              widget.spacing.lg,
              widget.spacing.lg,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ChatGlassButton(
                    label: 'default',
                    enabled: true,
                    maxTextWidth: 170,
                    gradientColors: glassGradientColors,
                    borderColor: glassBorderColor,
                    edgeGlowColor: glassEdgeGlowColor,
                    topHighlightColors: glassTopHighlightColors,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LabTopOverlayVeil extends StatelessWidget {
  const _LabTopOverlayVeil();

  static const double _headerRegionHeight = 76;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final statusBarHeight = MediaQuery.of(context).padding.top > 0
        ? MediaQuery.of(context).padding.top
        : spacing.lg;
    final totalHeight = statusBarHeight + _headerRegionHeight;
    final headerBottomFraction =
        ((statusBarHeight + 56) / totalHeight).clamp(0.0, 1.0);

    return SizedBox(
      height: totalHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.chatBackground.withValues(alpha: 0.96),
              colors.chatBackground.withValues(alpha: 0.88),
              colors.chatBackground.withValues(alpha: 0.18),
              colors.chatBackground.withValues(alpha: 0),
            ],
            stops: [
              0,
              headerBottomFraction * 0.6,
              headerBottomFraction * 0.98,
              1,
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LabScrollRunway extends StatelessWidget {
  const _LabScrollRunway({
    required this.radius,
    required this.spacing,
    required this.colors,
  });

  final AppRadius radius;
  final AppSpacing spacing;
  final AppThemeSpec colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.userBubbleSurface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(radius.lg + 2),
            boxShadow: [
              BoxShadow(
                color:
                    colors.core.elevation.shadowColor.withValues(alpha: 0.03),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.lg,
              vertical: spacing.md,
            ),
            child: Text(
              '帮我梳理一下这次首页顶部按钮动效的目标，以及它和内容阅读状态之间的关系。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.primaryText.withValues(alpha: 0.92),
                    height: 1.55,
                  ),
            ),
          ),
        ),
        SizedBox(height: spacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.assistantSurface.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(radius.lg + 6),
            border: Border.all(
              color: colors.semantic.text.inverse.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color:
                    colors.core.elevation.shadowColor.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.lg,
              spacing.lg,
              spacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '可以先把这次动效理解成一个很轻的“阅读状态切换”。页面静止时，顶部 chrome 更舒展一些，像是在等待下一次输入；开始阅读后，它再轻微收拢，把注意力慢慢让给内容。',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.primaryText.withValues(alpha: 0.92),
                        height: 1.72,
                      ),
                ),
                SizedBox(height: spacing.lg),
                _LabReplySection(
                  title: '1. 为什么要在阅读时变化',
                  body:
                      '如果顶部按钮在整段阅读过程中始终保持同样的存在感，用户会一直感到页面上方有一块较强的视觉重量悬着。轻微收拢之后，header 不需要消失，但它会从“前景工具”变成“背景工具”，这样注意力会更自然地落在回复文本本身。',
                  spacing: spacing,
                  colors: colors,
                ),
                _LabReplySection(
                  title: '2. 什么样的变化是合理的',
                  body:
                      '合理的变化通常不是单独移动某一个按钮，而是让整组 chrome 像同一层材料一样发生收束：边界稍微聚焦、阴影更克制、玻璃更亮一些，左右两组按钮再带一点点位移。这样用户感知到的是“表面状态变了”，而不是“图标被推走了”。',
                  spacing: spacing,
                  colors: colors,
                ),
                _LabReplySection(
                  title: '3. 这段位移本身的价值',
                  body:
                      '位移应该只是辅助信号。它真正的价值不在于让界面看起来更活，而在于配合材质和层级变化，告诉用户页面已经从待操作状态进入阅读状态。如果单独看位移没有带来更聚焦的感受，那它就应该继续减弱，甚至可以去掉。',
                  spacing: spacing,
                  colors: colors,
                ),
                SizedBox(height: spacing.lg),
                Text(
                  '继续往下打磨时，可以优先关注这几个问题：',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.primaryText.withValues(alpha: 0.9),
                        height: 1.68,
                      ),
                ),
                SizedBox(height: spacing.sm),
                ..._labReplyChecklist.map(
                  (item) => Padding(
                    padding: EdgeInsets.only(bottom: spacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: spacing.xs),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: colors.semantic.text.inverse
                                  .withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        SizedBox(width: spacing.sm),
                        Expanded(
                          child: Text(
                            item,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colors.primaryText
                                      .withValues(alpha: 0.86),
                                  height: 1.68,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: spacing.md),
                Text(
                  '如果你现在是在 Lab 里看这段效果，重点不一定是“它动了没有”，而是当你往下阅读时，顶部按钮是否真的比静止时更像一个安静的玻璃工具层。',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.primaryText.withValues(alpha: 0.92),
                        height: 1.72,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LabReplySection extends StatelessWidget {
  const _LabReplySection({
    required this.title,
    required this.body,
    required this.spacing,
    required this.colors,
  });

  final String title;
  final String body;
  final AppSpacing spacing;
  final AppThemeSpec colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.primaryText.withValues(alpha: 0.94),
                ),
          ),
          SizedBox(height: spacing.sm),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.primaryText.withValues(alpha: 0.84),
                  height: 1.72,
                ),
          ),
        ],
      ),
    );
  }
}

const List<String> _labReplyChecklist = [
  '收拢之后，顶部 chrome 有没有真的降低存在感，而不是只是横向位移了一点点。',
  '玻璃层是否随着滚动更聚焦、更轻，不会显得发灰或者像一块独立浮板。',
  '阅读一小段长文案时，视线能不能稳定停在正文，而不会频繁被顶部按钮抢走注意力。',
];
