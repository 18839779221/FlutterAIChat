import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_spec.dart';
import '../theme/app_typography.dart';

class InputSelectLabPage extends StatefulWidget {
  const InputSelectLabPage({super.key});

  @override
  State<InputSelectLabPage> createState() => _InputSelectLabPageState();
}

class _InputSelectLabPageState extends State<InputSelectLabPage> {
  final TextEditingController _referencePromptController =
      TextEditingController();
  final TextEditingController _themedProviderController =
      TextEditingController(text: 'Minimax');
  final TextEditingController _themedBaseUrlController =
      TextEditingController(text: 'https://api.minimax.chat/v1');

  String? _referenceModel = 'Claude 4 Sonnet';
  String? _themedApiStyle = 'Responses API';
  String? _themedSideModel = 'DeepSeek R1';

  static const List<String> _modelOptions = <String>[
    'Claude 4 Sonnet',
    'Claude 3.5 Haiku',
    'DeepSeek R1',
    'GPT-4.1 mini',
  ];

  static const List<String> _apiStyleOptions = <String>[
    'Responses API',
    'Chat Completions',
    'Anthropic Messages',
  ];

  @override
  void dispose() {
    _referencePromptController.dispose();
    _themedProviderController.dispose();
    _themedBaseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Scaffold(
      backgroundColor: const Color(0xFFFCFCFB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            spacing.xl + spacing.sm,
            spacing.xl + spacing.xs,
            spacing.xl + spacing.sm,
            spacing.xl + spacing.lg,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Input + Select Lab',
                    style: AppTypography.uiStyle(
                      color: const Color(0xFF111827),
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1.06,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '先按 shadcn 的克制骨架做 Flutter 原生输入框和选择器，再看它们与当前主题语义结合后是否还成立。'
                    ' 这版只追求 demo 效果和交互手感，不提前抽成正式生产组件。',
                    style: AppTypography.uiStyle(
                      color: const Color(0xFF6B7280),
                      fontSize: 14.5,
                      height: 1.65,
                    ),
                  ),
                  SizedBox(height: spacing.xl + spacing.sm),
                  Theme(
                    data: _buildReferenceTheme(),
                    child: _LabSurface(
                      title: 'Input Reference',
                      subtitle:
                          '先验证最基础的输入框骨架：高度、边框、聚焦 ring、禁用态和错误态都要克制，不带多余装饰。',
                      child: Wrap(
                        spacing: spacing.lg,
                        runSpacing: spacing.lg,
                        children: [
                          SizedBox(
                            width: 280,
                            child: _FieldDemoItem(
                              title: 'Default',
                              caption: 'Placeholder + clean border',
                              child: _LabInputField(
                                tone: _LabFieldTone.reference,
                                placeholder: 'Ask anything',
                                controller: _referencePromptController,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _FieldDemoItem(
                              title: 'With Value',
                              caption:
                                  'Value should stay readable and centered',
                              child: _LabStaticInputField(
                                tone: _LabFieldTone.reference,
                                value: 'https://api.example.com/v1',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: _FieldDemoItem(
                              title: 'Disabled + Error',
                              caption:
                                  'Disabled surface should recede; error should stay thin',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _LabStaticInputField(
                                    tone: _LabFieldTone.reference,
                                    placeholder: 'Disabled',
                                    enabled: false,
                                  ),
                                  SizedBox(height: spacing.sm),
                                  const _LabStaticInputField(
                                    tone: _LabFieldTone.reference,
                                    value: 'https://api.example.com',
                                    errorText: '请输入有效的 URL',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  _LabSurface(
                    title: 'Select Reference',
                    subtitle:
                        '选择器先不用 Flutter 默认下拉框，直接验证 trigger 的观感和移动优先的底部选择面板。',
                    child: Wrap(
                      spacing: spacing.lg,
                      runSpacing: spacing.lg,
                      children: [
                        SizedBox(
                          width: 280,
                          child: _FieldDemoItem(
                            title: 'Placeholder',
                            caption:
                                'Empty state should feel like a field, not a button',
                            child: _LabSelectField(
                              tone: _LabFieldTone.reference,
                              title: '选择模型',
                              subtitle: '先验证参考态的 trigger 与 sheet 语言',
                              placeholder: 'Select a model',
                              options: _modelOptions,
                              value: null,
                              onChanged: (_) {},
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 280,
                          child: _FieldDemoItem(
                            title: 'Selected',
                            caption: 'Selected text should remain understated',
                            child: _LabSelectField(
                              tone: _LabFieldTone.reference,
                              title: '选择模型',
                              subtitle: '点击可切换当前选择',
                              placeholder: 'Select a model',
                              options: _modelOptions,
                              value: _referenceModel,
                              onChanged: (value) {
                                setState(() {
                                  _referenceModel = value;
                                });
                              },
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 280,
                          child: _FieldDemoItem(
                            title: 'Disabled',
                            caption:
                                'Disabled trigger should still preserve shape',
                            child: _LabSelectField(
                              tone: _LabFieldTone.reference,
                              title: '选择模型',
                              subtitle: 'Disabled state',
                              placeholder: 'Select a model',
                              options: _modelOptions,
                              value: 'Claude 4 Sonnet',
                              enabled: false,
                              onChanged: (_) {},
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.settingsPanelBackground.withValues(
                        alpha: 0.68,
                      ),
                      borderRadius: BorderRadius.circular(radius.lg + 10),
                      border: Border.all(
                        color: colors.primaryText.withValues(alpha: 0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primaryText.withValues(alpha: 0.05),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(spacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Claude Theme Adaptation',
                            style: AppTypography.uiStyle(
                              color: colors.primaryText,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          SizedBox(height: spacing.xs),
                          Text(
                            '在不改变输入/选择器骨架的前提下，只换成当前项目的暖纸面和状态色，模拟 Provider 配置页的第一屏。',
                            style: AppTypography.uiStyle(
                              color: colors.secondaryText,
                              fontSize: 13.5,
                              height: 1.55,
                            ),
                          ),
                          SizedBox(height: spacing.lg),
                          _PreviewCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _PreviewSectionTitle(
                                  title: '运行时接入',
                                  subtitle: '只用最核心的 4 个字段判断这套基础件是否能撑起正式页面。',
                                ),
                                SizedBox(height: spacing.md),
                                _FieldDemoItem(
                                  title: 'Provider 名称',
                                  tone: _LabFieldTone.themed,
                                  child: _LabStaticInputField(
                                    tone: _LabFieldTone.themed,
                                    value: _themedProviderController.text,
                                  ),
                                ),
                                SizedBox(height: spacing.md),
                                _FieldDemoItem(
                                  title: 'Base URL',
                                  tone: _LabFieldTone.themed,
                                  child: _LabStaticInputField(
                                    tone: _LabFieldTone.themed,
                                    value: _themedBaseUrlController.text,
                                  ),
                                ),
                                SizedBox(height: spacing.md),
                                _FieldDemoItem(
                                  title: 'API Style',
                                  tone: _LabFieldTone.themed,
                                  child: _LabSelectField(
                                    tone: _LabFieldTone.themed,
                                    title: '选择 API Style',
                                    subtitle: '这版先走移动优先的底部面板',
                                    placeholder: '请选择 API Style',
                                    options: _apiStyleOptions,
                                    value: _themedApiStyle,
                                    onChanged: (value) {
                                      setState(() {
                                        _themedApiStyle = value;
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(height: spacing.md),
                                _FieldDemoItem(
                                  title: 'Side Model',
                                  caption: '保留“与主模型一致”的缺省语义',
                                  tone: _LabFieldTone.themed,
                                  child: _LabSelectField(
                                    tone: _LabFieldTone.themed,
                                    title: '选择 Side Model',
                                    subtitle: '默认留空时与主模型一致',
                                    placeholder: '与主模型一致',
                                    options: const <String>[
                                      '与主模型一致',
                                      ..._modelOptions,
                                    ],
                                    value: _themedSideModel,
                                    onChanged: (value) {
                                      setState(() {
                                        _themedSideModel = value;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(spacing.lg),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius.lg + 6),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      color: const Color(0xFFFAFAFA),
                    ),
                    child: Text(
                      '本轮只验证两件事：1）输入框和选择器脱离默认 Flutter 观感后是否足够克制；'
                      ' 2）切到当前主题语义后是否还能保持“像一个系统”，而不是又变回页面私有样式。',
                      style: AppTypography.uiStyle(
                        color: const Color(0xFF6B7280),
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ThemeData _buildReferenceTheme() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.uiFontFamily,
      scaffoldBackgroundColor: const Color(0xFFFCFCFB),
      canvasColor: Colors.transparent,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFF111827),
        selectionColor: Color(0x1A111827),
        selectionHandleColor: Color(0xFF111827),
      ),
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      shadowColor: Colors.transparent,
      textTheme: Typography.blackMountainView.apply(
        bodyColor: const Color(0xFF111827),
        displayColor: const Color(0xFF111827),
      ),
      iconTheme: const IconThemeData(
        color: Color(0xFF6B7280),
      ),
    );
  }
}

class _LabSurface extends StatelessWidget {
  const _LabSurface({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.uiStyle(
                color: const Color(0xFF111827),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppTypography.uiStyle(
                color: const Color(0xFF6B7280),
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chatBackground.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(radius.lg + 2),
        border: Border.all(
          color: colors.primaryText.withValues(alpha: 0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: child,
      ),
    );
  }
}

class _PreviewSectionTitle extends StatelessWidget {
  const _PreviewSectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.uiStyle(
            color: colors.primaryText,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: AppTypography.uiStyle(
            color: colors.secondaryText,
            fontSize: 12.8,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class _FieldDemoItem extends StatelessWidget {
  const _FieldDemoItem({
    required this.title,
    required this.child,
    this.caption,
    this.tone = _LabFieldTone.reference,
  });

  final String title;
  final String? caption;
  final Widget child;
  final _LabFieldTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>();
    final labelColor = tone == _LabFieldTone.reference
        ? const Color(0xFF111827)
        : (colors?.primaryText ?? const Color(0xFF111827));
    final captionColor = tone == _LabFieldTone.reference
        ? const Color(0xFF6B7280)
        : (colors?.secondaryText ?? const Color(0xFF6B7280));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.uiStyle(
            color: labelColor,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(
            caption!,
            style: AppTypography.uiStyle(
              color: captionColor,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

enum _LabFieldTone {
  reference,
  themed,
}

class _LabFieldPalette {
  const _LabFieldPalette({
    required this.fill,
    required this.border,
    required this.focusBorder,
    required this.hoverBorder,
    required this.text,
    required this.placeholder,
    required this.disabledText,
    required this.disabledFill,
    required this.error,
    required this.ring,
    required this.icon,
    required this.sheetSurface,
    required this.sheetBorder,
    required this.sheetSelectedFill,
  });

  final Color fill;
  final Color border;
  final Color focusBorder;
  final Color hoverBorder;
  final Color text;
  final Color placeholder;
  final Color disabledText;
  final Color disabledFill;
  final Color error;
  final Color ring;
  final Color icon;
  final Color sheetSurface;
  final Color sheetBorder;
  final Color sheetSelectedFill;

  factory _LabFieldPalette.resolve(
    BuildContext context,
    _LabFieldTone tone,
  ) {
    if (tone == _LabFieldTone.reference) {
      return const _LabFieldPalette(
        fill: Colors.white,
        border: Color(0xFFE5E7EB),
        focusBorder: Color(0xFF111827),
        hoverBorder: Color(0xFFD1D5DB),
        text: Color(0xFF111827),
        placeholder: Color(0xFF9CA3AF),
        disabledText: Color(0xFF9CA3AF),
        disabledFill: Color(0xFFF3F4F6),
        error: Color(0xFFDC2626),
        ring: Color(0x24111827),
        icon: Color(0xFF6B7280),
        sheetSurface: Colors.white,
        sheetBorder: Color(0xFFE5E7EB),
        sheetSelectedFill: Color(0xFFF3F4F6),
      );
    }

    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    return _LabFieldPalette(
      fill: colors.chatBackground.withValues(alpha: 0.96),
      border: colors.semantic.interaction.subtleBorder,
      focusBorder: colors.semantic.state.running,
      hoverBorder: colors.semantic.interaction.border,
      text: colors.primaryText,
      placeholder: colors.secondaryText.withValues(alpha: 0.72),
      disabledText: colors.secondaryText.withValues(alpha: 0.48),
      disabledFill: colors.structuredSurface.withValues(alpha: 0.62),
      error: colors.semantic.state.error,
      ring: colors.semantic.state.running.withValues(alpha: 0.16),
      icon: colors.secondaryText,
      sheetSurface: colors.settingsPanelBackground,
      sheetBorder: colors.primaryText.withValues(alpha: 0.08),
      sheetSelectedFill: colors.chatBackground.withValues(alpha: 0.94),
    );
  }
}

class _LabStaticInputField extends StatelessWidget {
  const _LabStaticInputField({
    required this.tone,
    this.placeholder,
    this.value,
    this.enabled = true,
    this.errorText,
  });

  final _LabFieldTone tone;
  final String? placeholder;
  final String? value;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final palette = _LabFieldPalette.resolve(context, tone);
    final colors = Theme.of(context).extension<AppThemeSpec>();
    final hasError = (errorText ?? '').trim().isNotEmpty;
    final borderColor = hasError ? palette.error : palette.border;
    final fillColor = enabled ? palette.fill : palette.disabledFill;
    final textColor = enabled ? palette.text : palette.disabledText;
    final shadowColor =
        colors?.primaryText.withValues(alpha: 0.02) ?? const Color(0x05111827);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 10,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            value ?? placeholder ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.uiStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 7),
          Text(
            errorText!,
            style: AppTypography.uiStyle(
              color: palette.error,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

class _LabInputField extends StatefulWidget {
  const _LabInputField({
    required this.tone,
    this.placeholder,
    this.controller,
  });

  final _LabFieldTone tone;
  final String? placeholder;
  final TextEditingController? controller;

  @override
  State<_LabInputField> createState() => _LabInputFieldState();
}

class _LabInputFieldState extends State<_LabInputField> {
  late final FocusNode _focusNode;
  late final TextEditingController _controller;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = _LabFieldPalette.resolve(context, widget.tone);
    final colors = Theme.of(context).extension<AppThemeSpec>();
    final borderColor = _focusNode.hasFocus
        ? palette.focusBorder
        : (_hovered ? palette.hoverBorder : palette.border);
    final shadowColor =
        colors?.primaryText.withValues(alpha: 0.02) ?? const Color(0x05111827);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _focusNode.requestFocus(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: palette.fill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
                boxShadow: [
                  if (_focusNode.hasFocus)
                    BoxShadow(
                      color: palette.ring,
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 10,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox.expand(
                  child: _LabEditableInputCore(
                    controller: _controller,
                    focusNode: _focusNode,
                    placeholder: widget.placeholder,
                    textColor: palette.text,
                    placeholderColor: palette.placeholder,
                    cursorColor: palette.focusBorder,
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

class _LabEditableInputCore extends StatelessWidget {
  const _LabEditableInputCore({
    required this.controller,
    required this.focusNode,
    required this.textColor,
    required this.placeholderColor,
    required this.cursorColor,
    this.placeholder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? placeholder;
  final Color textColor;
  final Color placeholderColor;
  final Color cursorColor;

  @override
  Widget build(BuildContext context) {
    final transparentTheme = Theme.of(context).copyWith(
      canvasColor: Colors.transparent,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: cursorColor,
        selectionColor: cursorColor.withValues(alpha: 0.18),
        selectionHandleColor: cursorColor,
      ),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      shadowColor: Colors.transparent,
    );
    final textStyle = AppTypography.uiStyle(
      color: textColor,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );
    final placeholderStyle = AppTypography.uiStyle(
      color: placeholderColor,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.2,
    );

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final showEditable = focusNode.hasFocus || value.text.isNotEmpty;
        return Theme(
          data: transparentTheme,
          child: DefaultSelectionStyle(
            selectionColor: cursorColor.withValues(alpha: 0.18),
            cursorColor: cursorColor,
            child: SelectionContainer.disabled(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  if (value.text.isEmpty && (placeholder ?? '').isNotEmpty)
                    IgnorePointer(
                      child: Text(
                        placeholder!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: placeholderStyle,
                      ),
                    ),
                  if (showEditable)
                    EditableText(
                      controller: controller,
                      focusNode: focusNode,
                      style: textStyle,
                      cursorColor: cursorColor,
                      backgroundCursorColor: Colors.transparent,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      maxLines: 1,
                      minLines: 1,
                      expands: false,
                      selectionColor: cursorColor.withValues(alpha: 0.18),
                      rendererIgnoresPointer: false,
                      readOnly: false,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LabSelectField extends StatefulWidget {
  const _LabSelectField({
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.placeholder,
    required this.options,
    required this.onChanged,
    this.value,
    this.enabled = true,
  });

  final _LabFieldTone tone;
  final String title;
  final String subtitle;
  final String placeholder;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? value;
  final bool enabled;

  @override
  State<_LabSelectField> createState() => _LabSelectFieldState();
}

class _LabSelectFieldState extends State<_LabSelectField> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = _LabFieldPalette.resolve(context, widget.tone);
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final hasValue = (widget.value ?? '').trim().isNotEmpty;
    final borderColor = _pressed
        ? palette.focusBorder
        : (_hovered ? palette.hoverBorder : palette.border);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed && widget.enabled ? 0.988 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.enabled ? _handleTap : null,
            onHighlightChanged: (value) {
              if (_pressed != value) {
                setState(() {
                  _pressed = value;
                });
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: widget.enabled ? palette.fill : palette.disabledFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
                boxShadow: [
                  if (_pressed)
                    BoxShadow(
                      color: palette.ring,
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  BoxShadow(
                    color: colors.primaryText.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasValue ? widget.value! : widget.placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.uiStyle(
                        color: widget.enabled
                            ? (hasValue ? palette.text : palette.placeholder)
                            : palette.disabledText,
                        fontSize: 14,
                        fontWeight:
                            hasValue ? FontWeight.w500 : FontWeight.w400,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 17,
                    color: widget.enabled ? palette.icon : palette.disabledText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _LabSelectSheet(
          tone: widget.tone,
          title: widget.title,
          subtitle: widget.subtitle,
          options: widget.options,
          selectedValue: widget.value,
        );
      },
    );
    if (selected != null) {
      widget.onChanged(selected);
    }
  }
}

class _LabSelectSheet extends StatelessWidget {
  const _LabSelectSheet({
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selectedValue,
  });

  final _LabFieldTone tone;
  final String title;
  final String subtitle;
  final List<String> options;
  final String? selectedValue;

  @override
  Widget build(BuildContext context) {
    final palette = _LabFieldPalette.resolve(context, tone);
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final titleColor = tone == _LabFieldTone.reference
        ? const Color(0xFF111827)
        : colors.primaryText;
    final subtitleColor = tone == _LabFieldTone.reference
        ? const Color(0xFF6B7280)
        : colors.secondaryText;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(spacing.md, spacing.md, spacing.md, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.sheetSurface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(radius.lg + 10),
            ),
            border: Border.all(color: palette.sheetBorder),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.sm,
              spacing.lg,
              spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: subtitleColor.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(radius.pill),
                    ),
                  ),
                ),
                SizedBox(height: spacing.md),
                Text(
                  title,
                  style: AppTypography.uiStyle(
                    color: titleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  subtitle,
                  style: AppTypography.uiStyle(
                    color: subtitleColor,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: spacing.md),
                ...options.map((option) {
                  final selected = option == selectedValue;
                  return Padding(
                    padding: EdgeInsets.only(bottom: spacing.xs),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).pop(option),
                        child: Ink(
                          decoration: BoxDecoration(
                            color: selected
                                ? palette.sheetSelectedFill
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? palette.focusBorder.withValues(alpha: 0.2)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: spacing.md,
                              vertical: spacing.sm + 1,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option,
                                    style: AppTypography.uiStyle(
                                      color: titleColor,
                                      fontSize: 14,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                    color: palette.focusBorder,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
