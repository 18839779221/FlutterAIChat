import 'dart:async';

import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/pages/provider_form_page.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/llm_model_discovery_service.dart';
import 'package:ai_chat/services/llm_model_test_service.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('provider form page uses immersive editor header', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-floating-header')),
      findsOneWidget,
    );
    expect(find.text('新增 Provider'), findsWidgets);
  });

  testWidgets(
      'provider form shows speed test in connection section and model actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('连接与鉴权'), findsOneWidget);
    expect(find.text('模型目录'), findsOneWidget);
    expect(find.text('测速'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    expect(find.text('探测模型'), findsOneWidget);
    expect(find.text('Ping'), findsNothing);
    expect(find.text('Pong'), findsNothing);

    expect(find.text('用于展示（例如：OpenAI）'), findsOneWidget);
  });

  testWidgets('provider form removes decorative hero and uses grouped editor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('配置新的模型连接'), findsNothing);
    expect(find.text('新增 Provider'), findsOneWidget);
    expect(find.text('连接与鉴权'), findsOneWidget);
    expect(find.text('模型目录'), findsOneWidget);
    expect(find.text('高级运行时'), findsNothing);
  });

  testWidgets('saving with empty model list auto-discovers and runs speed test',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();
    final discoveryService = _FakeDiscoveryService(
      models: const [
        LlmProviderModel(id: 'gpt-4o-mini', name: ''),
        LlmProviderModel(id: 'gpt-4.1', name: ''),
      ],
    );
    final testService = _FakeModelTestService();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          repository: repository,
          discoveryService: discoveryService,
          testService: testService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Provider 名称'),
      'OpenAI',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Base URL'),
      'https://api.openai.com/v1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'API Key'),
      'test-key',
    );

    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(discoveryService.callCount, 1);
    expect(testService.speedTestCallCount, 1);
    expect(testService.lastSpeedModelId, 'gpt-4o-mini');

    final providers = await repository.getProviders();
    final selection = await repository.getSelectionState();
    expect(providers, hasLength(1));
    expect(providers.single.models.map((item) => item.id), [
      'gpt-4o-mini',
      'gpt-4.1',
    ]);
    expect(providers.single.models.map((item) => item.name), [
      'gpt-4o-mini',
      'gpt-4.1',
    ]);
    expect(providers.single.apiKey, 'test-key');
    expect(selection.selectedModelId, 'gpt-4o-mini');
  });

  testWidgets('saving with existing models skips auto-discovery',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();
    final discoveryService = _FakeDiscoveryService(
      models: const [LlmProviderModel(id: 'should-not-run', name: '')],
    );
    final testService = _FakeModelTestService();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          initialProvider: const LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'test-key',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o-mini', name: ''),
            ],
          ),
          repository: repository,
          discoveryService: discoveryService,
          testService: testService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(discoveryService.callCount, 0);
    expect(testService.speedTestCallCount, 0);

    final providers = await repository.getProviders();
    expect(providers.single.models.map((item) => item.id), ['gpt-4o-mini']);
    expect(providers.single.models.map((item) => item.name), ['gpt-4o-mini']);
  });

  testWidgets('speed test feedback avoids exposing ping pong wording',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          initialProvider: const LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'test-key',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o-mini', name: ''),
            ],
          ),
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('测速'));
    await tester.tap(find.text('测速'));
    await tester.pump();

    expect(find.textContaining('测速完成，连接正常：首次响应 120ms · 再次响应 180ms'),
        findsOneWidget);
    expect(find.textContaining('Ping'), findsNothing);
    expect(find.textContaining('Pong'), findsNothing);
  });

  testWidgets('api key masks when unfocused and reveals full value on focus',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          initialProvider: const LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'abcd1234wxyz',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o-mini', name: ''),
            ],
          ),
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('abcd*****wxyz'), findsOneWidget);
    expect(find.text('abcd1234wxyz'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(TextFormField, 'API Key'));
    await tester.tap(find.widgetWithText(TextFormField, 'API Key'));
    await tester.pumpAndSettle();

    expect(find.text('abcd1234wxyz'), findsOneWidget);
    expect(find.text('abcd*****wxyz'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Provider 名称'));
    await tester.tap(find.widgetWithText(TextFormField, 'Provider 名称'));
    await tester.pumpAndSettle();

    expect(find.text('abcd*****wxyz'), findsOneWidget);
  });

  testWidgets('model name defaults to model id for manual rows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('手动新增模型'));
    await tester.tap(find.text('手动新增模型'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '模型 ID'),
      'gpt-4o-mini',
    );
    await tester.pumpAndSettle();

    final modelNameField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, '模型名称 1'),
    );
    expect(modelNameField.controller?.text, 'gpt-4o-mini');
  });

  testWidgets('model row saves image generation capability checkbox',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Provider 名称'),
      'Beehears',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Base URL'),
      'https://ai.beehears.com/v1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'API Key'),
      'image-key',
    );
    await tester.ensureVisible(find.text('手动新增模型'));
    await tester.tap(find.text('手动新增模型'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '模型 ID'),
      'gpt-image-2',
    );
    await tester.ensureVisible(find.text('支持生图'));
    await tester.tap(find.text('支持生图'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final providers = await repository.getProviders();
    expect(providers.single.models.single.supportsImageGeneration, isTrue);
  });

  testWidgets('image generation test requires confirmation and debounces taps',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();
    final testService = _FakeModelTestService();
    final imageTestCompleter = testService.holdNextImageGenerationTest();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          initialProvider: const LlmProviderConfig(
            id: 'beehears',
            name: 'Beehears',
            apiKey: 'image-key',
            baseUrl: 'https://ai.beehears.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-image-2', name: 'GPT Image 2'),
            ],
          ),
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: testService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('测试生图'));
    await tester.tap(find.text('测试生图'));
    await tester.pumpAndSettle();
    expect(find.textContaining('可能较慢且产生费用'), findsOneWidget);

    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(testService.imageGenerationTestCallCount, 0);

    await tester.ensureVisible(find.text('测试生图'));
    await tester.tap(find.text('测试生图'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认测试'));
    await tester.tap(find.text('确认测试'));
    await tester.pump();
    expect(testService.imageGenerationTestCallCount, 1);

    await tester.ensureVisible(find.text('测试中'));
    await tester.tap(find.text('测试中'));
    await tester.pump();
    expect(testService.imageGenerationTestCallCount, 1);

    imageTestCompleter.complete(
      const LlmImageGenerationProbeResult(
        modelId: 'gpt-image-2',
        latency: Duration(milliseconds: 900),
      ),
    );
    await tester.pumpAndSettle();

    expect(testService.imageGenerationTestCallCount, 1);
    expect(find.text('支持生图'), findsOneWidget);
    final additionalConfig = await repository.getAdditionalConfig();
    expect(
      additionalConfig['image_generation.default_provider_id'],
      'beehears',
    );
    expect(
      additionalConfig['image_generation.default_model_id'],
      'gpt-image-2',
    );
  });

  testWidgets('set as global image generation model persists independent config',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          initialProvider: const LlmProviderConfig(
            id: 'beehears',
            name: 'Beehears',
            apiKey: 'image-key',
            baseUrl: 'https://ai.beehears.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-image-2', name: 'GPT Image 2'),
            ],
          ),
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('设为全局生图模型'));
    await tester.tap(find.text('设为全局生图模型'));
    await tester.pumpAndSettle();

    final providers = await repository.getProviders();
    expect(providers.single.models.single.supportsImageGeneration, isTrue);
    final additionalConfig = await repository.getAdditionalConfig();
    expect(
      additionalConfig['image_generation.default_provider_id'],
      'beehears',
    );
    expect(
      additionalConfig['image_generation.default_model_id'],
      'gpt-image-2',
    );
  });

  testWidgets('base url with explicit endpoint auto-selects matching api style',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Base URL'),
      'https://api.example.com/v1/messages',
    );
    await tester.pumpAndSettle();

    expect(find.text('API Style'), findsOneWidget);
    expect(find.text('Anthropic Messages'), findsOneWidget);
  });

  testWidgets('api style picker uses product titles and protocol subtitles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          initialProvider: const LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'test-key',
            baseUrl: 'https://api.openai.com/v1/responses',
            models: [
              LlmProviderModel(id: 'gpt-4o-mini', name: ''),
            ],
          ),
          repository: repository,
          discoveryService: _FakeDiscoveryService(),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('API Style'), findsOneWidget);
    expect(find.text('如果粘贴了完整 endpoint，会自动识别；也可以手动切换。'), findsNothing);

    await tester.ensureVisible(find.text('OpenAI Responses'));
    await tester.tap(find.text('OpenAI Responses'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI Responses'), findsWidgets);
    expect(find.text('OpenAI Chat Completions'), findsOneWidget);
    expect(find.text('Anthropic Messages'), findsOneWidget);
    expect(find.text('responses'), findsOneWidget);
    expect(find.text('chat_completions'), findsOneWidget);
    expect(find.text('anthropic_messages'), findsOneWidget);
    expect(find.text('Responses API'), findsNothing);
    expect(find.text('Chat Completions'), findsNothing);
    expect(find.text('适合 OpenAI Responses 兼容接口。'), findsNothing);
  });

  testWidgets('manual api style selection rewrites base url before save',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = await _createRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProviderFormPage(
          repository: repository,
          discoveryService: _FakeDiscoveryService(
            models: const [LlmProviderModel(id: 'gpt-4o-mini', name: '')],
          ),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Provider 名称'),
      'Example',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Base URL'),
      'https://api.example.com/v1/messages',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'API Key'),
      'test-key',
    );

    await tester.ensureVisible(find.text('Anthropic Messages'));
    await tester.tap(find.text('Anthropic Messages'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('OpenAI Responses').last);
    await tester.tap(find.text('OpenAI Responses').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final providers = await repository.getProviders();
    expect(providers.single.baseUrl, 'https://api.example.com/v1/responses');
  });
}

Future<AppSettingsRepository> _createRepository() async {
  SharedPreferences.setMockInitialValues({});
  return AppSettingsRepository(
    await SharedPreferences.getInstance(),
    localDefaultsLoader: () async => null,
  );
}

class _FakeDiscoveryService extends LlmModelDiscoveryService {
  _FakeDiscoveryService({this.models = const []});

  final List<LlmProviderModel> models;
  int callCount = 0;

  @override
  Future<List<LlmProviderModel>> discoverModels({
    required LlmProviderConfig provider,
  }) async {
    callCount += 1;
    return models;
  }
}

class _FakeModelTestService extends LlmModelTestService {
  int speedTestCallCount = 0;
  int imageGenerationTestCallCount = 0;
  String? lastSpeedModelId;
  String? lastImageGenerationModelId;
  final List<LlmModelProbeType> probeCallTypes = <LlmModelProbeType>[];
  final List<String> probeCallModelIds = <String>[];
  Completer<LlmImageGenerationProbeResult>? _heldImageGenerationTest;

  Completer<LlmImageGenerationProbeResult> holdNextImageGenerationTest() {
    final completer = Completer<LlmImageGenerationProbeResult>();
    _heldImageGenerationTest = completer;
    return completer;
  }

  @override
  Future<LlmModelSpeedTestResult> speedTestModel({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
  }) async {
    speedTestCallCount += 1;
    lastSpeedModelId = model.id;
    return LlmModelSpeedTestResult(
      ping: LlmModelProbeResult(
        probeType: LlmModelProbeType.ping,
        modelId: model.id,
        responseText: 'ping',
        latency: const Duration(milliseconds: 120),
      ),
      pong: LlmModelProbeResult(
        probeType: LlmModelProbeType.pong,
        modelId: model.id,
        responseText: 'pong',
        latency: const Duration(milliseconds: 180),
      ),
    );
  }

  @override
  Future<LlmModelProbeResult> probeModel({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
    required LlmModelProbeType probeType,
  }) async {
    probeCallTypes.add(probeType);
    probeCallModelIds.add(model.id);
    return LlmModelProbeResult(
      probeType: probeType,
      modelId: model.id,
      responseText: probeType == LlmModelProbeType.ping ? 'ping' : 'pong',
      latency: const Duration(milliseconds: 90),
    );
  }

  @override
  Future<LlmImageGenerationProbeResult> testImageGenerationModel({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
  }) async {
    imageGenerationTestCallCount += 1;
    lastImageGenerationModelId = model.id;
    final held = _heldImageGenerationTest;
    if (held != null) {
      _heldImageGenerationTest = null;
      return held.future;
    }
    return LlmImageGenerationProbeResult(
      modelId: model.id,
      latency: const Duration(milliseconds: 900),
    );
  }
}
