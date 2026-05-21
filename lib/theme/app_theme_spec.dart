import 'package:flutter/material.dart';

import 'app_motion.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Single source of truth for an app theme family.
@immutable
class AppThemeSpec extends ThemeExtension<AppThemeSpec> {
  final String id;
  final String displayName;
  final Brightness brightness;
  final AppCoreTokens core;
  final AppSemanticTokens semantic;
  final AppComponentTokens components;

  const AppThemeSpec({
    required this.id,
    required this.displayName,
    required this.brightness,
    required this.core,
    required this.semantic,
    required this.components,
  });

  factory AppThemeSpec.light() => AppThemeSpec.claude();

  factory AppThemeSpec.dark() => AppThemeSpec.olivePaper();

  factory AppThemeSpec.claude() {
    const surfaces = AppSurfaceSemanticTokens(
      pageBackground: Color(0xFFF5F4EE),
      panelBackground: Color(0xFFF0EEE6),
      readingSurface: Color(0xFFFAF9F5),
      userBubbleSurface: Color(0xFFEDEAE0),
      toolInlineSurface: Color(0xFFF5F2EA),
      toolResultSurface: Color(0xFFF2F1EB),
      dangerSurface: Color(0xFFFBF1E8),
      structuralSurface: Color(0xFFFAF9F5),
    );
    const text = AppTextSemanticTokens(
      primary: Color(0xFF1F1F1E),
      secondary: Color(0xFF3D3D3A),
      tertiary: Color(0xFF75726A),
      inverse: Colors.white,
    );
    const state = AppStateSemanticTokens(
      running: Color(0xFFC96442),
      success: Color(0xFF2F6A4F),
      warning: Color(0xFF9A6C37),
      error: Color(0xFFBE2222),
      info: Color(0xFF8A5A44),
    );
    const interactions = AppInteractionSemanticTokens(
      border: Color(0xFFD9D6CC),
      focus: Color(0xFFC96442),
      subtleBorder: Color(0xFFE8E6DC),
    );

    return AppThemeSpec(
      id: 'claude',
      displayName: 'Claude',
      brightness: Brightness.light,
      core: AppCoreTokens(
        colors: AppColorTokens(
          black: Color(0xFF1F1F1E),
          white: Colors.white,
          paper: Color(0xFFF5F4EE),
          ink: Color(0xFF1F1F1E),
          mutedInk: Color(0xFF3D3D3A),
          shadow: Color(0x22000000),
        ),
        typography: const AppTypographyTokens(
          uiFontFamily: 'AnthropicSans',
          documentFontFamily: 'SourceSerif4',
          codeFontFamily: 'JetBrainsMono',
          documentPackagedCjkFamily: AppTypography.documentPackagedCjkFamily,
          documentFontFallback: AppTypography.documentFontFallback,
        ),
        spacing: AppSpacing.base(),
        radius: AppRadius.base(),
        motion: AppMotion.base(),
        elevation: AppElevationTokens(
          shadowColor: Color(0x1F000000),
        ),
        stroke: const AppStrokeTokens(
          thin: 1,
          medium: 1.2,
          strong: 1.5,
        ),
      ),
      semantic: AppSemanticTokens(
        surfaces: surfaces,
        text: text,
        state: state,
        interaction: interactions,
      ),
      components: AppComponentTokens(
        chatPage: const ChatPageTokens(),
        composer: const ChatComposerTokens(),
        assistantDocument: const AssistantDocumentTokens(),
        userBubble: const UserBubbleTokens(),
        toolCard: const ToolCardTokens(),
        reasoning: const ReasoningTokens(),
        settings: const SettingsTokens(),
        markdown: const MarkdownTokens(),
      ),
    );
  }

  factory AppThemeSpec.olivePaper() {
    const surfaces = AppSurfaceSemanticTokens(
      pageBackground: Color(0xFFF3F1EC),
      panelBackground: Color(0xFFE3E4DE),
      readingSurface: Color(0xFFECE7DE),
      userBubbleSurface: Color(0xFFD6DBD2),
      toolInlineSurface: Color(0xFFDDE4D8),
      toolResultSurface: Color(0xFFE1E8DE),
      dangerSurface: Color(0xFFEEE2D7),
      structuralSurface: Color(0xFFE6E1D6),
    );
    const text = AppTextSemanticTokens(
      primary: Color(0xFF182019),
      secondary: Color(0xFF596259),
      tertiary: Color(0xFF73796F),
      inverse: Colors.white,
    );
    const state = AppStateSemanticTokens(
      running: Color(0xFF35594A),
      success: Color(0xFF2F6A4F),
      warning: Color(0xFF9A6C37),
      error: Color(0xFFB5483C),
      info: Color(0xFF4B6C8A),
    );
    const interactions = AppInteractionSemanticTokens(
      border: Color(0x664F5F55),
      focus: Color(0xFF35594A),
      subtleBorder: Color(0x2E20281F),
    );

    return AppThemeSpec(
      id: 'olive-paper',
      displayName: 'Olive Paper',
      brightness: Brightness.light,
      core: AppCoreTokens(
        colors: AppColorTokens(
          black: Color(0xFF182019),
          white: Colors.white,
          paper: Color(0xFFF3F1EC),
          ink: Color(0xFF182019),
          mutedInk: Color(0xFF596259),
          shadow: Color(0x22000000),
        ),
        typography: const AppTypographyTokens(
          uiFontFamily: 'AnthropicSans',
          documentFontFamily: 'SourceSerif4',
          codeFontFamily: 'JetBrainsMono',
          documentPackagedCjkFamily: AppTypography.documentPackagedCjkFamily,
          documentFontFallback: AppTypography.documentFontFallback,
        ),
        spacing: AppSpacing.base(),
        radius: AppRadius.base(),
        motion: AppMotion.base(),
        elevation: AppElevationTokens(
          shadowColor: Color(0x1F000000),
        ),
        stroke: const AppStrokeTokens(
          thin: 1,
          medium: 1.2,
          strong: 1.5,
        ),
      ),
      semantic: AppSemanticTokens(
        surfaces: surfaces,
        text: text,
        state: state,
        interaction: interactions,
      ),
      components: AppComponentTokens(
        chatPage: const ChatPageTokens(),
        composer: const ChatComposerTokens(),
        assistantDocument: const AssistantDocumentTokens(),
        userBubble: const UserBubbleTokens(),
        toolCard: const ToolCardTokens(),
        reasoning: const ReasoningTokens(),
        settings: const SettingsTokens(),
        markdown: const MarkdownTokens(),
      ),
    );
  }

  static List<AppThemeSpec> builtInThemes() {
    return <AppThemeSpec>[
      AppThemeSpec.claude(),
      AppThemeSpec.olivePaper(),
    ];
  }

  static AppThemeSpec? resolveById(String id) {
    for (final theme in builtInThemes()) {
      if (theme.id == id) {
        return theme;
      }
    }
    return null;
  }

  static AppThemeSpec of(BuildContext context) {
    final theme = Theme.of(context);
    final spec = theme.extension<AppThemeSpec>();
    assert(spec != null, 'AppThemeSpec is missing from ThemeData.extensions');
    return spec!;
  }

  Color get chatBackground => semantic.surfaces.pageBackground;
  Color get settingsPanelBackground => semantic.surfaces.panelBackground;
  Color get assistantSurface => semantic.surfaces.readingSurface;
  Color get userBubbleSurface => semantic.surfaces.userBubbleSurface;
  Color get toolWorkflowSurface => semantic.surfaces.toolInlineSurface;
  Color get structuredSurface => semantic.surfaces.structuralSurface;
  Color get toolOutcomeSurface => semantic.surfaces.toolResultSurface;
  Color get toolExceptionSurface => semantic.surfaces.dangerSurface;
  Color get primaryText => semantic.text.primary;
  Color get secondaryText => semantic.text.secondary;
  Color get divider => semantic.interaction.subtleBorder;
  Color get workflowRunning => semantic.state.running;
  Color get workflowSuccess => semantic.state.success;
  Color get workflowWarning => semantic.state.warning;

  @override
  ThemeExtension<AppThemeSpec> copyWith({
    String? id,
    String? displayName,
    Brightness? brightness,
    AppCoreTokens? core,
    AppSemanticTokens? semantic,
    AppComponentTokens? components,
  }) {
    return AppThemeSpec(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      brightness: brightness ?? this.brightness,
      core: core ?? this.core,
      semantic: semantic ?? this.semantic,
      components: components ?? this.components,
    );
  }

  @override
  ThemeExtension<AppThemeSpec> lerp(
    covariant ThemeExtension<AppThemeSpec>? other,
    double t,
  ) {
    if (other is! AppThemeSpec) {
      return this;
    }
    return AppThemeSpec(
      id: t < 0.5 ? id : other.id,
      displayName: t < 0.5 ? displayName : other.displayName,
      brightness: t < 0.5 ? brightness : other.brightness,
      core: core,
      semantic: semantic.lerp(other.semantic, t),
      components: components,
    );
  }
}

@immutable
class AppCoreTokens {
  final AppColorTokens colors;
  final AppTypographyTokens typography;
  final AppSpacing spacing;
  final AppRadius radius;
  final AppMotion motion;
  final AppElevationTokens elevation;
  final AppStrokeTokens stroke;

  const AppCoreTokens({
    required this.colors,
    required this.typography,
    required this.spacing,
    required this.radius,
    required this.motion,
    required this.elevation,
    required this.stroke,
  });
}

@immutable
class AppColorTokens {
  final Color black;
  final Color white;
  final Color paper;
  final Color ink;
  final Color mutedInk;
  final Color shadow;

  const AppColorTokens({
    required this.black,
    required this.white,
    required this.paper,
    required this.ink,
    required this.mutedInk,
    required this.shadow,
  });
}

@immutable
class AppTypographyTokens {
  final String uiFontFamily;
  final String documentFontFamily;
  final String codeFontFamily;
  final String documentPackagedCjkFamily;
  final List<String> documentFontFallback;

  const AppTypographyTokens({
    required this.uiFontFamily,
    required this.documentFontFamily,
    required this.codeFontFamily,
    required this.documentPackagedCjkFamily,
    required this.documentFontFallback,
  });
}

@immutable
class AppElevationTokens {
  final Color shadowColor;

  const AppElevationTokens({required this.shadowColor});
}

@immutable
class AppStrokeTokens {
  final double thin;
  final double medium;
  final double strong;

  const AppStrokeTokens({
    required this.thin,
    required this.medium,
    required this.strong,
  });
}

@immutable
class AppSemanticTokens {
  final AppSurfaceSemanticTokens surfaces;
  final AppTextSemanticTokens text;
  final AppStateSemanticTokens state;
  final AppInteractionSemanticTokens interaction;

  const AppSemanticTokens({
    required this.surfaces,
    required this.text,
    required this.state,
    required this.interaction,
  });

  AppSemanticTokens lerp(AppSemanticTokens other, double t) {
    return AppSemanticTokens(
      surfaces: surfaces.lerp(other.surfaces, t),
      text: text.lerp(other.text, t),
      state: state.lerp(other.state, t),
      interaction: interaction.lerp(other.interaction, t),
    );
  }
}

@immutable
class AppSurfaceSemanticTokens {
  final Color pageBackground;
  final Color panelBackground;
  final Color readingSurface;
  final Color userBubbleSurface;
  final Color toolInlineSurface;
  final Color toolResultSurface;
  final Color dangerSurface;
  final Color structuralSurface;

  const AppSurfaceSemanticTokens({
    required this.pageBackground,
    required this.panelBackground,
    required this.readingSurface,
    required this.userBubbleSurface,
    required this.toolInlineSurface,
    required this.toolResultSurface,
    required this.dangerSurface,
    required this.structuralSurface,
  });

  AppSurfaceSemanticTokens lerp(AppSurfaceSemanticTokens other, double t) {
    return AppSurfaceSemanticTokens(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      panelBackground: Color.lerp(panelBackground, other.panelBackground, t)!,
      readingSurface: Color.lerp(readingSurface, other.readingSurface, t)!,
      userBubbleSurface:
          Color.lerp(userBubbleSurface, other.userBubbleSurface, t)!,
      toolInlineSurface:
          Color.lerp(toolInlineSurface, other.toolInlineSurface, t)!,
      toolResultSurface:
          Color.lerp(toolResultSurface, other.toolResultSurface, t)!,
      dangerSurface: Color.lerp(dangerSurface, other.dangerSurface, t)!,
      structuralSurface:
          Color.lerp(structuralSurface, other.structuralSurface, t)!,
    );
  }
}

@immutable
class AppTextSemanticTokens {
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color inverse;

  const AppTextSemanticTokens({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.inverse,
  });

  AppTextSemanticTokens lerp(AppTextSemanticTokens other, double t) {
    return AppTextSemanticTokens(
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      inverse: Color.lerp(inverse, other.inverse, t)!,
    );
  }
}

@immutable
class AppStateSemanticTokens {
  final Color running;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  const AppStateSemanticTokens({
    required this.running,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  AppStateSemanticTokens lerp(AppStateSemanticTokens other, double t) {
    return AppStateSemanticTokens(
      running: Color.lerp(running, other.running, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

@immutable
class AppInteractionSemanticTokens {
  final Color border;
  final Color focus;
  final Color subtleBorder;

  const AppInteractionSemanticTokens({
    required this.border,
    required this.focus,
    required this.subtleBorder,
  });

  AppInteractionSemanticTokens lerp(
    AppInteractionSemanticTokens other,
    double t,
  ) {
    return AppInteractionSemanticTokens(
      border: Color.lerp(border, other.border, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
    );
  }
}

@immutable
class AppComponentTokens {
  final ChatPageTokens chatPage;
  final ChatComposerTokens composer;
  final AssistantDocumentTokens assistantDocument;
  final UserBubbleTokens userBubble;
  final ToolCardTokens toolCard;
  final ReasoningTokens reasoning;
  final SettingsTokens settings;
  final MarkdownTokens markdown;

  const AppComponentTokens({
    required this.chatPage,
    required this.composer,
    required this.assistantDocument,
    required this.userBubble,
    required this.toolCard,
    required this.reasoning,
    required this.settings,
    required this.markdown,
  });
}

@immutable
class ChatPageTokens {
  const ChatPageTokens();
}

@immutable
class ChatComposerTokens {
  const ChatComposerTokens();
}

@immutable
class AssistantDocumentTokens {
  const AssistantDocumentTokens();
}

@immutable
class UserBubbleTokens {
  const UserBubbleTokens();
}

@immutable
class ToolCardTokens {
  const ToolCardTokens();
}

@immutable
class ReasoningTokens {
  const ReasoningTokens();
}

@immutable
class SettingsTokens {
  const SettingsTokens();
}

@immutable
class MarkdownTokens {
  const MarkdownTokens();
}
