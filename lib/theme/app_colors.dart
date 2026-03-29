import 'package:flutter/material.dart';

/// Semantic colors shared by chat and settings pages.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Page background used by the chat surface.
  final Color chatBackground;

  /// Secondary grouped panel color used by the settings surface.
  final Color settingsPanelBackground;

  /// Surface for assistant document-style content blocks.
  final Color assistantSurface;

  /// Surface for the user's anchor bubble.
  final Color userBubbleSurface;

  /// Surface for foldable tool workflow cards.
  final Color toolWorkflowSurface;

  /// Surface for structured output blocks.
  final Color structuredSurface;

  /// Primary readable text color.
  final Color primaryText;

  /// Secondary readable text color.
  final Color secondaryText;

  /// Divider color for low-noise grouping.
  final Color divider;

  /// Accent for in-progress workflow state.
  final Color workflowRunning;

  /// Accent for successful workflow state.
  final Color workflowSuccess;

  /// Accent for risky or warning workflow state.
  final Color workflowWarning;

  const AppColors({
    required this.chatBackground,
    required this.settingsPanelBackground,
    required this.assistantSurface,
    required this.userBubbleSurface,
    required this.toolWorkflowSurface,
    required this.structuredSurface,
    required this.primaryText,
    required this.secondaryText,
    required this.divider,
    required this.workflowRunning,
    required this.workflowSuccess,
    required this.workflowWarning,
  });

  factory AppColors.light() {
    return const AppColors(
      chatBackground: Color(0xFFF7F8FA),
      settingsPanelBackground: Color(0xFFF1F2F4),
      assistantSurface: Color(0xFFF8F5EF),
      userBubbleSurface: Color(0xFFDCE6F2),
      toolWorkflowSurface: Color(0xFFEEF3F8),
      structuredSurface: Color(0xFFF6F3EC),
      primaryText: Color(0xFF1D2733),
      secondaryText: Color(0xFF5F6B7A),
      divider: Color(0x14271D33),
      workflowRunning: Color(0xFF4D6FA3),
      workflowSuccess: Color(0xFF3D7A57),
      workflowWarning: Color(0xFFA46A2A),
    );
  }

  factory AppColors.dark() {
    return const AppColors(
      chatBackground: Color(0xFF0E1012),
      settingsPanelBackground: Color(0xFF171A1D),
      assistantSurface: Color(0xFF15181C),
      userBubbleSurface: Color(0xFF243545),
      toolWorkflowSurface: Color(0xFF1B232B),
      structuredSurface: Color(0xFF191C20),
      primaryText: Color(0xFFF0F3F6),
      secondaryText: Color(0xFFB2BCC8),
      divider: Color(0x24FFFFFF),
      workflowRunning: Color(0xFF7D9CCB),
      workflowSuccess: Color(0xFF76B08C),
      workflowWarning: Color(0xFFD29A5A),
    );
  }

  @override
  ThemeExtension<AppColors> copyWith({
    Color? chatBackground,
    Color? settingsPanelBackground,
    Color? assistantSurface,
    Color? userBubbleSurface,
    Color? toolWorkflowSurface,
    Color? structuredSurface,
    Color? primaryText,
    Color? secondaryText,
    Color? divider,
    Color? workflowRunning,
    Color? workflowSuccess,
    Color? workflowWarning,
  }) {
    return AppColors(
      chatBackground: chatBackground ?? this.chatBackground,
      settingsPanelBackground:
          settingsPanelBackground ?? this.settingsPanelBackground,
      assistantSurface: assistantSurface ?? this.assistantSurface,
      userBubbleSurface: userBubbleSurface ?? this.userBubbleSurface,
      toolWorkflowSurface: toolWorkflowSurface ?? this.toolWorkflowSurface,
      structuredSurface: structuredSurface ?? this.structuredSurface,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      divider: divider ?? this.divider,
      workflowRunning: workflowRunning ?? this.workflowRunning,
      workflowSuccess: workflowSuccess ?? this.workflowSuccess,
      workflowWarning: workflowWarning ?? this.workflowWarning,
    );
  }

  @override
  ThemeExtension<AppColors> lerp(
    covariant ThemeExtension<AppColors>? other,
    double t,
  ) {
    if (other is! AppColors) {
      return this;
    }
    return AppColors(
      chatBackground: Color.lerp(chatBackground, other.chatBackground, t)!,
      settingsPanelBackground: Color.lerp(
        settingsPanelBackground,
        other.settingsPanelBackground,
        t,
      )!,
      assistantSurface: Color.lerp(assistantSurface, other.assistantSurface, t)!,
      userBubbleSurface:
          Color.lerp(userBubbleSurface, other.userBubbleSurface, t)!,
      toolWorkflowSurface:
          Color.lerp(toolWorkflowSurface, other.toolWorkflowSurface, t)!,
      structuredSurface: Color.lerp(structuredSurface, other.structuredSurface, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      workflowRunning: Color.lerp(workflowRunning, other.workflowRunning, t)!,
      workflowSuccess: Color.lerp(workflowSuccess, other.workflowSuccess, t)!,
      workflowWarning: Color.lerp(workflowWarning, other.workflowWarning, t)!,
    );
  }
}
