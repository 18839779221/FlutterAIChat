import '../../models/artifact/artifact_record.dart';
import '../../models/artifact/artifact_type.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/tool_result.dart';
import '../../repositories/artifact_repository.dart';
import '../../services/artifact/artifact_file_storage_service.dart';
import '../../services/artifact/artifact_source_sanitizer.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

class CreateArtifactToolHandler extends ToolHandler {
  CreateArtifactToolHandler({
    required ArtifactRepository artifactRepository,
    required ArtifactFileStorageService fileStorageService,
    ArtifactSourceSanitizer? sanitizer,
  })  : _artifactRepository = artifactRepository,
        _fileStorageService = fileStorageService,
        _sanitizer = sanitizer ?? const ArtifactSourceSanitizer();

  final ArtifactRepository _artifactRepository;
  final ArtifactFileStorageService _fileStorageService;
  final ArtifactSourceSanitizer _sanitizer;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'create_artifact',
        title: 'Create Artifact',
        localizedTitle: LocalizedToolText(
          english: 'Create Artifact',
          chinese: '创建可视化产物',
        ),
        descriptionForModel: _englishArtifactDescription,
        localizedDescriptionForModel: LocalizedToolText(
          english: _englishArtifactDescription,
          chinese: _chineseArtifactDescription,
        ),
        supportedPlatforms: ['android', 'ios', 'macos'],
        argumentSchema: ToolArgumentSchema(
          properties: {
            'id': ToolArgumentProperty.string(
              description: 'Stable kebab-case artifact identifier.',
              localizedDescription: LocalizedToolText(
                english: 'Stable kebab-case artifact identifier.',
                chinese: '稳定的 kebab-case artifact 标识。',
              ),
            ),
            'type': ToolArgumentProperty.string(
              description: 'Artifact source type: html or svg.',
              localizedDescription: LocalizedToolText(
                english: 'Artifact source type: html or svg.',
                chinese: 'artifact 源类型：html 或 svg。',
              ),
            ),
            'title': ToolArgumentProperty.string(
              description: 'User-visible artifact title.',
              localizedDescription: LocalizedToolText(
                english: 'User-visible artifact title.',
                chinese: '用户可见的 artifact 标题。',
              ),
            ),
            'source': ToolArgumentProperty.string(
              description:
                  'Artifact content source authored for placement inside the host-provided #artifact-root.',
              localizedDescription: LocalizedToolText(
                english:
                    'Artifact content source authored for placement inside the host-provided #artifact-root.',
                chinese: '为宿主提供的 #artifact-root 内部编写的 artifact 内容源码。',
              ),
            ),
          },
          required: ['id', 'type', 'title', 'source'],
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List history,
    required DateTime now,
  }) async {
    final id = rawArguments['id'];
    final type = rawArguments['type'];
    final title = rawArguments['title'];
    final source = rawArguments['source'];

    if (id is! String || !RegExp(r'^[a-z0-9-]{1,40}$').hasMatch(id.trim())) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_artifact_id',
        errorSummary: 'create_artifact failed: invalid id',
      );
    }
    if (type is! String || (type != 'html' && type != 'svg')) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_artifact_type',
        errorSummary: 'create_artifact failed: invalid type',
      );
    }
    if (title is! String || title.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_artifact_title',
        errorSummary: 'create_artifact failed: invalid title',
      );
    }
    if (source is! String || source.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_artifact_source',
        errorSummary: 'create_artifact failed: invalid source',
      );
    }

    return ToolArgumentResolution.valid({
      'id': id.trim(),
      'type': type,
      'title': title.trim(),
      'source': source,
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    final artifactId = context.arguments['id'] as String;
    final type = ArtifactTypeX.fromWireValue(context.arguments['type'] as String);
    final title = context.arguments['title'] as String;
    final source = context.arguments['source'] as String;

    final sanitized = _sanitizer.sanitize(source);
    if (!sanitized.isValid) {
      return ToolResult(
        toolName: 'create_artifact',
        status: ToolExecutionStatus.failure,
        summary: '创建 artifact 失败',
        data: {
          'artifactId': artifactId,
          'reason': sanitized.errorCode ?? 'invalid_source',
        },
        errorMessage: sanitized.errorCode ?? 'invalid_source',
      );
    }

    final created = await _fileStorageService.saveArtifactSource(
      groupId: context.groupId,
      artifactId: artifactId,
      title: title,
      type: type,
      source: sanitized.sanitizedSource,
      warnings: sanitized.warnings,
    );

    await _artifactRepository.upsertRecord(
      ArtifactRecord(
        artifactId: artifactId,
        groupId: context.groupId,
        title: title,
        type: type,
        sourcePath: created.sourcePath,
        originTurnId: 0,
        createdAt: context.now,
        lastUpdatedAt: context.now,
      ),
    );

    return ToolResult(
      toolName: 'create_artifact',
      status: ToolExecutionStatus.success,
      summary: '已创建 artifact：$artifactId',
      data: {
        ...created.toJson(),
        'message': '已创建 artifact：$artifactId\nsourcePath：${created.sourcePath}',
      },
    );
  }

}

const String _englishArtifactDescription = '''
Publish an interactive, self-contained HTML artifact inline in your reply.

<role>
You are authoring an inline explanatory artifact for a host chat surface.
Your generated source is always rendered inside the host-provided `#artifact-root`.
</role>

<authoring_protocol>
1. For the first version of an explanatory or visualization artifact, call `create_artifact__guideline` immediately before creating it.
2. Treat the latest guideline result as the required authoring contract for this `create_artifact` call.
3. Apply that contract directly in the generated `source`.
4. Author only the artifact content that belongs inside `#artifact-root`.
</authoring_protocol>

<preflight_checklist>
Before writing `source`, verify all of the following:
- I am authoring only content for `#artifact-root`.
- I am not generating a full page document structure.
- I am not using `html` or `body` as the primary authored surface.
- I am not declaring a replacement root theme token set such as generic `--bg`, `--surface`, `--text`, or `--border`.
- I am not defining any custom color values in `:root` or anywhere else.
- I am not hardcoding any color values (hex, rgb, rgba, hsl, named colors) for backgrounds, text, borders, or decorative elements.
- I am only referencing the host-provided `--app-artifact-*` token variables for all theme-aware styling.
</preflight_checklist>

<scope_rules>
- The host always owns the outer page shell, viewport context, and embedding environment.
- Do not generate a full page document structure.
- Do not author an app page, landing page, or mini website.
- Do not make `html` or `body` the primary authored surface.
</scope_rules>

<token_rules>
CRITICAL: You MUST use only the host-provided `--app-artifact-*` token references for all colors, backgrounds, text colors, borders, and theme-aware styling.

Strictly forbidden:
- Defining custom CSS color variables (e.g., `--bg`, `--surface`, `--text`, `--primary`, `--accent`)
- Hardcoding any color values in any format: hex, rgb, rgba, hsl, or named colors
- Duplicating host token values instead of referencing them
- Creating your own color palette or design system

Required:
- Use `var(--app-artifact-page-bg)` for backgrounds
- Use `var(--app-artifact-text-primary)` for text colors
- Use `var(--app-artifact-border-subtle)` for borders
- Use `var(--app-artifact-chart-1)` through `chart-5` for data visualization colors
- Reference the complete token list from the guideline result
</token_rules>

<artifact_shape>
- Create one integrated inline artifact surface that feels embedded in the reply.
- Keep the structure explanation-focused.
- Prefer concise first versions unless the user explicitly asks for a richer or longer artifact.
- Avoid repeating artifact content in your text reply. The artifact itself is the answer; your reply should provide context or next steps, not duplicate what's already visible in the artifact.
</artifact_shape>

<strict_avoid>
- standalone page shell
- page-first body styling
- decorative site-style header/footer chrome
- custom replacement tokens such as generic `--bg`, `--surface`, `--text`, or `--border` replacing host tokens
</strict_avoid>

<technical_constraints>
- source MUST be a self-contained HTML document or fragment. Inline <script>/<style> are allowed.
- External <script src="...">, remote CSS, and network requests are blocked by default.
- Prefer SVG, Canvas, and vanilla JS. Do NOT rely on external CDNs or third-party hosted assets.
- When generating HTML, make progressive inline rendering easy: prefer writing CSS first, put visible markup before scripts, and place most script logic near the end of the document.
- The preview container height is derived from the document content, so keep the document flow-driven and avoid giant fixed-height outer wrappers unless they are necessary.
- Prefer content that fits within one screen when rendered inline. Unless the user explicitly asks for a longer experience, keep the artifact concise and avoid exceeding two screens.
</technical_constraints>
''';

const String _chineseArtifactDescription = '''
在回复中内联发布一个可交互、自包含的 HTML artifact。

<role>
你是在宿主聊天表面中编写一个内联解释型 artifact。
你生成的 source 始终会被渲染到宿主提供的 `#artifact-root` 内部。
</role>

<authoring_protocol>
1. 对于解释型或可视化 artifact 的首版，必须先紧接着调用 `create_artifact__guideline`，再执行 `create_artifact`。
2. 必须将最近一次 guideline 结果视为本次 `create_artifact` 调用的强制 authoring contract。
3. 必须把该 contract 直接落实到生成的 `source` 中。
4. 只能编写属于 `#artifact-root` 内部的 artifact 内容。
</authoring_protocol>

<preflight_checklist>
在编写 `source` 前，必须先确认以下各项全部成立：
- 我只是在为 `#artifact-root` 编写内容。
- 我没有生成完整页面文档结构。
- 我没有把 `html` 或 `body` 当作主要的编写表面。
- 我没有声明替代性的根级主题 token 集，例如通用 `--bg`、`--surface`、`--text`、`--border`。
- 我没有在 `:root` 或任何地方定义自定义色值。
- 我没有硬编码任何色值（hex、rgb、rgba、hsl、颜色名称）用于背景、文字、边框或装饰元素。
- 我只引用宿主提供的 `--app-artifact-*` token 变量来处理所有主题相关样式。
</preflight_checklist>

<scope_rules>
- 宿主始终拥有外层 page shell、viewport 上下文和嵌入环境。
- 不要生成完整页面文档结构。
- 不要把它写成 app 页面、landing page 或 mini website。
- 不要把 `html` 或 `body` 当作主要的编写表面。
</scope_rules>

<token_rules>
关键要求：必须只使用宿主提供的 `--app-artifact-*` token 引用来处理所有颜色、背景、文字颜色、边框和主题相关样式。

严格禁止：
- 定义自定义 CSS 色值变量（如 `--bg`、`--surface`、`--text`、`--primary`、`--accent`）
- 硬编码任何格式的色值：hex、rgb、rgba、hsl 或颜色名称
- 复制宿主 token 的值而不是引用它们
- 创建自己的调色板或设计系统

必须做到：
- 使用 `var(--app-artifact-page-bg)` 处理背景
- 使用 `var(--app-artifact-text-primary)` 处理文字颜色
- 使用 `var(--app-artifact-border-subtle)` 处理边框
- 使用 `var(--app-artifact-chart-1)` 到 `chart-5` 处理数据可视化颜色
- 从 guideline 结果中引用完整的 token 列表
</token_rules>

<artifact_shape>
- 生成一个统一的内联 artifact surface，让它读起来像回复中的嵌入内容。
- 结构要以解释内容为主。
- 首版尽量保持精简；只有当用户明确要求更丰富或更长的 artifact 时才扩展。
- 避免在文字回复中重复 artifact 的内容。artifact 本身就是答案；你的回复应该提供上下文或后续步骤，而不是重复 artifact 中已经可见的内容。
</artifact_shape>

<strict_avoid>
- standalone page shell
- 以页面为中心的 body 样式
- 装饰性的站点式 header/footer 外壳
- 用通用 `--bg`、`--surface`、`--text`、`--border` 等替代宿主 token 的自定义主题系统
</strict_avoid>

<technical_constraints>
- source 必须是自包含的 HTML 文档或片段，可以使用内联 <script>/<style>。
- 默认会拦截外部 <script src="...">、远程 CSS 和网络请求。
- 优先使用 SVG、Canvas 和原生 JS；不要依赖外部 CDN 或第三方托管资源。
- 生成时要考虑它会作为一张内联卡片显示，因此优先按 CSS 在前、可见内容在中、脚本在后的顺序组织源码。
- 预览容器高度会根据文档内容自适应，因此尽量保持正常文档流，不要无必要地使用超大的固定外层高度。
- 优先让内容在内联展示时控制在 1 屏内；除非用户明确要求更长体验，否则尽量保持精简，不要超过 2 屏。
</technical_constraints>
''';
