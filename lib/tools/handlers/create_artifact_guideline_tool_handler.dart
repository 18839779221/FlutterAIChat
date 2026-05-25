import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/tool_result.dart';
import '../../services/artifact/artifact_guideline_contract_builder.dart';
import '../../theme/app_theme_spec.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

class CreateArtifactGuidelineToolHandler extends ToolHandler {
  CreateArtifactGuidelineToolHandler({
    required AppThemeSpec Function() activeThemeSpecProvider,
    ArtifactGuidelineContractBuilder? contractBuilder,
  })  : _activeThemeSpecProvider = activeThemeSpecProvider,
        _contractBuilder = contractBuilder ?? const ArtifactGuidelineContractBuilder();

  final AppThemeSpec Function() _activeThemeSpecProvider;
  final ArtifactGuidelineContractBuilder _contractBuilder;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'create_artifact__guideline',
        title: 'Artifact Guideline',
        localizedTitle: LocalizedToolText(
          english: 'Artifact Guideline',
          chinese: 'Artifact 规范说明',
        ),
        descriptionForModel: _englishDescription,
        localizedDescriptionForModel: LocalizedToolText(
          english: _englishDescription,
          chinese: _chineseDescription,
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List history,
    required DateTime now,
  }) async {
    return ToolArgumentResolution.valid(const <String, dynamic>{});
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    final contract = _contractBuilder.build(
      spec: _activeThemeSpecProvider(),
    );
    return ToolResult(
      toolName: 'create_artifact__guideline',
      status: ToolExecutionStatus.success,
      summary: '已返回 artifact guideline',
      data: contract.toJson(),
    );
  }
}

const String _englishDescription = '''
Read the current design-token contract and host rendering constraints for explanatory artifacts that should feel native to the app.

IMPORTANT: If you are about to create an artifact for visualization or explanatory enhancement, you MUST call `create_artifact__guideline` before the first `create_artifact` call for that artifact. Do not skip this step for the first version.

Use this tool immediately before the first `create_artifact` call for a new explanatory artifact. This tool is a paired prerequisite for `create_artifact`, not the artifact creation step itself.

This tool returns the current host markup contract, token references, layout constraints, and rendering rules that the artifact must follow. Use the returned token references and host contract instead of hardcoding theme-specific visual values.

After reading the guideline for the same artifact, do not call this tool again unless the guideline context is missing or likely changed.
''';

const String _chineseDescription = '''
读取当前解释增强型 artifact 所需的 design token contract 与宿主渲染约束，使生成结果更贴近 app 原生设计语言。

重要：如果你准备创建一个用于可视化或描述增强的 artifact，那么在该 artifact 的第一次 `create_artifact` 调用前，必须先调用 `create_artifact__guideline`。不要跳过这一步直接生成首版 artifact。

当你准备为一个新的解释增强型 artifact 发起第一次 `create_artifact` 调用时，应立即先调用此工具。该工具是 `create_artifact` 的配套前置步骤，而不是 artifact 创建步骤本身。

该工具会返回当前宿主 markup contract、token 引用、布局约束和渲染规则。生成 artifact 时应优先复用这些引用与约束，而不是硬编码主题特定的视觉值。

对于同一个 artifact，读取过一次 guideline 后，不要再次重复调用，除非 guideline 上下文缺失或很可能已发生变化。
''';
