import '../../models/chat_message.dart';
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

class CreateArtifactToolHandler implements ToolHandler {
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
              description: 'Full self-contained artifact source.',
              localizedDescription: LocalizedToolText(
                english: 'Full self-contained artifact source.',
                chinese: '完整自包含的 artifact 源码。',
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
      toolResultText: '已创建 artifact：$artifactId\nsourcePath：${created.sourcePath}',
      data: created.toJson(),
    );
  }

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return const <ChatMessage>[];
  }
}

const String _englishArtifactDescription = '''
Publish an interactive, self-contained HTML artifact inline in your reply.
Use when a chart, calculator, form, visualization, polished table, or small interactive demo would explain the answer better than prose. The artifact is rendered as a content block inside the assistant message, and you can still write normal text before or after it.

Current native surfaces primarily include Android phone, Android tablet, iPhone, iPad, and macOS. Adapt the layout to the active platform and likely viewport. On Android phone, prefer narrow-screen, touch-friendly layouts that remain readable without horizontal scrolling. On tablet or desktop, you may use a wider centered composition, but avoid edge-to-edge text.

Constraints:
- source MUST be a self-contained HTML document or fragment. Inline <script>/<style> are allowed.
- External <script src="...">, remote CSS, and network requests are blocked by default.
- Prefer SVG, Canvas, and vanilla JS. Do NOT rely on external CDNs or third-party hosted assets.
- Design for one inline card that may be re-rendered after later Edit/Write operations on the same sourcePath.
- The artifact itself should read as a single integrated surface inside the chat reply. Favor one coherent outer structure with the main content placed directly inside it, so the result feels embedded in the message rather than presented as a separate page.
- Default the page-level background to transparent, and treat the main content container as the visible surface. Do not rely on the body element to create a full-screen stage unless the user explicitly asks for that effect.
- The preview container height is derived from the document content, so keep the document flow-driven and avoid giant fixed-height outer wrappers unless they are necessary.
- After the first version is created, prefer using Read/Edit/Write on the returned sourcePath to improve the same artifact instead of resending the full source every time.

Design guidelines unless the user asks otherwise:
- Layout and spacing: use generous padding (16-24px), clear hierarchy, max content width around 720px on wide screens, centered layout, and never cram text edge-to-edge.
- Surface structure: keep the outermost artifact surface visually quiet and unified. Let spacing, typography, and content organization create hierarchy before introducing extra framing layers.
- Background treatment: prefer transparent or near-transparent page background, with visual emphasis carried by the main content surface rather than by a surrounding stage.
- Typography: use the system font stack -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif. Titles should usually be 18-22px, body 14-15px, caption 12px, with line-height 1.5 or higher. Limit each section to regular and semibold weights.
- Color: support light and dark appearance with color-scheme: light dark and Canvas/CanvasText-friendly colors. Use one calm accent color by default, such as #3B82F6. For data visualization, prefer a restrained palette like #3B82F6, #10B981, #F59E0B, #EF4444, #8B5CF6 rather than rainbow colors.
- Charts and data visualization: always include axis labels and units where relevant. Use subtle gridlines. Prefer entry animation once on load (roughly 200-400ms ease-out), not on every interaction. Prefer tooltips on hover or tap instead of always-on labels. Prefer SVG for mostly static charts and Canvas for dense or animated plots.
- Interactivity: buttons should have at least 36px tap targets, around 8px radius, and visible hover/active states. Inputs need a clear accent-colored focus ring, inline validation, and reset or clear actions for input-driven views. Empty states should be explicit and friendly, never blank.
- Polish: prefer subtle shadows such as 0 1px 3px rgba(0,0,0,0.08), consistent 6-12px corner radii, and short transitions around 150-250ms. Do not add emoji to data visualizations unless the user explicitly wants that tone.
- Accessibility: maintain WCAG AA contrast, avoid relying on color alone, label visual encodings with text or shapes, and keep interactive controls keyboard-focusable.
''';

const String _chineseArtifactDescription = '''
在回复中内联发布一个可交互、自包含的 HTML artifact。
当图表、计算器、表单、可视化、精致表格或小型交互 demo 比纯文字更能说明问题时使用。artifact 会作为助手消息中的内容卡片渲染，你仍然可以在前后正常写文字说明。

当前原生展示面主要包括 Android 手机、Android 平板、iPhone、iPad 和 macOS。请根据当前平台和可能的视口宽度适配布局。在 Android 手机上，优先窄屏、触控友好、无需横向滚动也能读懂的布局；在平板和桌面上可以适当加宽并居中，但不要做通栏贴边文字。

约束：
- source 必须是自包含的 HTML 文档或片段，可以使用内联 <script>/<style>。
- 默认会拦截外部 <script src="...">、远程 CSS 和网络请求。
- 优先使用 SVG、Canvas 和原生 JS；不要依赖外部 CDN 或第三方托管资源。
- 设计时要考虑它会作为一张内联卡片显示，后续可能通过同一 sourcePath 上的 Edit/Write 重新渲染。
- artifact 自身应呈现为单层、整合的内容表面，让主要内容直接落在统一的外层结构中，使它更像消息中的嵌入式展示，而不是独立页面。
- 默认让页面级背景保持透明，并把主要内容容器作为实际可见表面；除非用户明确要求，否则不要依赖 body 去搭建一个铺满全页的舞台背景。
- 预览容器高度会根据文档内容自适应，因此尽量保持正常文档流，不要无必要地使用超大的固定外层高度。
- 初版创建完成后，如需继续优化同一个 artifact，优先对返回的 sourcePath 使用 Read/Edit/Write，而不是每次都重发完整源码。

默认设计规范（除非用户另有要求）：
- 布局与留白：使用 16-24px 的宽松内边距，层级清晰，宽屏时内容最大宽度约 720px 并居中，避免贴边堆字。
- 表面结构：最外层表面应保持克制、统一，让留白、字体层级和内容组织先承担主要的视觉结构，再谨慎补充必要的表面区分。
- 背景处理：优先使用透明或接近透明的页面背景，让视觉重点落在主内容表面本身，而不是外围舞台式背景。
- 字体：使用系统字体栈 -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif。标题通常 18-22px，正文 14-15px，说明文字 12px，行高至少 1.5。每个区块尽量只使用常规和 semibold 两种字重。
- 色彩：通过 color-scheme: light dark 和兼容 Canvas/CanvasText 的颜色适配浅色/深色。默认使用单一主强调色，例如 #3B82F6。数据可视化优先克制配色，如 #3B82F6、#10B981、#F59E0B、#EF4444、#8B5CF6，不要彩虹色乱铺。
- 图表与可视化：在相关场景中始终补齐坐标轴标签与单位，网格线保持轻量。入场动画只在首次加载时出现，控制在约 200-400ms ease-out，不要每次交互都重播。提示信息优先使用 hover/tap tooltip，不要默认把所有标签一直铺开。静态图优先 SVG，点位多或动画多时再用 Canvas。
- 交互：按钮最小点击区域 36px，圆角约 8px，并提供清晰的 hover/active 状态。输入框需要明显的主色 focus ring、内联校验，以及 reset/clear 操作。任何输入驱动视图都应有友好的空状态，而不是空白画布。
- 质感：优先轻阴影，如 0 1px 3px rgba(0,0,0,0.08)，统一使用 6-12px 圆角，状态变化提供约 150-250ms 的短过渡。除非语境明确需要，否则不要在数据可视化里使用 emoji。
- 可访问性：满足 WCAG AA 对比度；不要只依赖颜色表达含义；用文字或形状辅助编码；可交互控件应支持键盘聚焦。
''';
