import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/tool_result.dart';
import '../../services/artifact/artifact_guideline_contract_builder.dart';
import '../../theme/app_theme_spec.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';
import 'package:flutter/services.dart';

class CreateArtifactGuidelineToolHandler extends ToolHandler {
  CreateArtifactGuidelineToolHandler({
    required AppThemeSpec Function() activeThemeSpecProvider,
    ArtifactGuidelineContractBuilder? contractBuilder,
    AssetBundle? assetBundle,
  })  : _activeThemeSpecProvider = activeThemeSpecProvider,
        _contractBuilder = contractBuilder ?? const ArtifactGuidelineContractBuilder(),
        _assetBundle = assetBundle ?? rootBundle;

  final AppThemeSpec Function() _activeThemeSpecProvider;
  final ArtifactGuidelineContractBuilder _contractBuilder;
  final AssetBundle _assetBundle;

  static const String _claudeGuidelineAssetPath =
      'assets/guidelines/claude_visualizer_read_me.md';

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
    String? rawGuidelineMarkdown;
    try {
      rawGuidelineMarkdown = await _assetBundle.loadString(
        _claudeGuidelineAssetPath,
      );
    } catch (_) {
      rawGuidelineMarkdown = null;
    }
    final data = <String, dynamic>{
      ...contract.toJson(),
      if ((rawGuidelineMarkdown ?? '').isNotEmpty)
        'raw_guideline_markdown': rawGuidelineMarkdown,
    };
    return ToolResult(
      toolName: 'create_artifact__guideline',
      status: ToolExecutionStatus.success,
      summary: '已返回 artifact guideline',
      data: data,
    );
  }
}

const String _englishDescription = '''
Read the current design-token contract and host rendering constraints for explanatory artifacts that should feel native to the app.

<role>
This tool is the required prerequisite for the first version of an explanatory or visualization artifact.
Its result must be applied in the next `create_artifact` call for that artifact.
</role>

<required_usage>
- Call this tool immediately before the first `create_artifact` call for a new explanatory artifact.
- Treat the returned result as the required authoring contract for the next `create_artifact` call.
- Apply the returned contract directly in the generated `source`.
- Do not read this guideline and then generate a source that ignores its token references, scope constraints, or rendering rules.
</required_usage>

<authoring_scope>
Your generated artifact source is always authored for placement inside the host-provided `#artifact-root`.
The host always owns the outer page shell, surrounding chat surface, and embedding environment.
Do not author a separate page shell.
Do not make `html` or `body` the primary authored surface.
</authoring_scope>

<repeat_policy>
After reading the guideline for the same artifact, do not call this tool again unless the contract is missing or likely changed.
</repeat_policy>
''';

const String _chineseDescription = '''
读取当前解释增强型 artifact 所需的 design token contract 与宿主渲染约束，使生成结果更贴近 app 原生设计语言。

<role>
该工具是解释型或可视化 artifact 首版生成前的必需前置步骤。
它返回的结果必须被应用到紧接着的下一次 `create_artifact` 调用中。
</role>

<required_usage>
- 对新的解释型 artifact 发起第一次 `create_artifact` 前，必须先立即调用此工具。
- 必须将返回结果视为下一次 `create_artifact` 调用的强制 authoring contract。
- 必须把该 contract 直接落实到生成的 `source` 中。
- 不要读完 guideline 后，又生成一个忽略 token 引用、作用域约束或渲染规则的 source。
</required_usage>

<authoring_scope>
你生成的 artifact source 始终是为放置到宿主提供的 `#artifact-root` 内部而编写的。
宿主始终拥有外层 page shell、聊天表面和嵌入环境。
不要再编写单独的 page shell。
不要把 `html` 或 `body` 当作主要的编写表面。
</authoring_scope>

<repeat_policy>
同一个 artifact 读过一次 guideline 后，不要重复调用，除非 contract 缺失或很可能已经变化。
</repeat_policy>
''';
