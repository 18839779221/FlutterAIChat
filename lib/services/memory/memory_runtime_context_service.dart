import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:path/path.dart' as p;

typedef MemoryFileReader = Future<String?> Function(String agentPath);

typedef MemoryTopicSelector = Future<List<String>> Function({
  required String userInput,
  required List<MemoryTopicCandidate> candidates,
  LLMConfig? sideRuntimeConfigOverride,
  MemorySideTaskRunner? sideTaskRunner,
});

typedef MemorySideTaskRunner = Future<String> Function(
  List<ChatMessage> messages, {
  required ChatConfig config,
  required String requestLabel,
  Duration? timeout,
});

class MemoryTopicCandidate {
  final String title;
  final String hook;
  final String agentPath;
  final String name;
  final String? description;
  final String? type;

  const MemoryTopicCandidate({
    required this.title,
    required this.hook,
    required this.agentPath,
    required this.name,
    this.description,
    this.type,
  });
}

class MemoryRuntimeContextService {
  MemoryRuntimeContextService({
    required MemoryFileReader readFile,
    MemoryTopicSelector? selectRelevantTopics,
    this.maxIndexLines = 200,
    this.maxRecalledMemories = 5,
    this.maxTopicChars = 3000,
    this.maxTotalTopicChars = 10000,
  })  : _readFile = readFile,
        _selectRelevantTopics = selectRelevantTopics ?? _defaultSelector;

  final MemoryFileReader _readFile;
  final MemoryTopicSelector _selectRelevantTopics;
  final int maxIndexLines;
  final int maxRecalledMemories;
  final int maxTopicChars;
  final int maxTotalTopicChars;

  Future<String> buildContextSection({
    String? userInput,
    LLMConfig? sideRuntimeConfigOverride,
    MemorySideTaskRunner? sideTaskRunner,
  }) async {
    if (_shouldIgnoreMemory(userInput)) {
      return '';
    }

    final indexText = await _readMemoryIndex();
    if (indexText == null || indexText.trim().isEmpty) {
      return '';
    }

    final parsedIndex = _parseIndex(indexText);
    if (parsedIndex.candidates.isEmpty) {
      return _buildIndexSection(parsedIndex.indexText);
    }

    final enrichedCandidates = await _enrichCandidates(parsedIndex.candidates);
    final byPath = {
      for (final candidate in enrichedCandidates) candidate.agentPath: candidate,
    };

    final selectedPaths = await _selectRelevantTopics(
      userInput: userInput ?? '',
      candidates: enrichedCandidates,
      sideRuntimeConfigOverride: sideRuntimeConfigOverride,
      sideTaskRunner: sideTaskRunner,
    );
    final selected = <MemoryTopicCandidate>[];
    final seen = <String>{};
    for (final path in selectedPaths) {
      final normalized = _normalizeAgentPath(path);
      if (normalized == null || !seen.add(normalized)) {
        continue;
      }
      final candidate = byPath[normalized];
      if (candidate != null) {
        selected.add(candidate);
      }
      if (selected.length >= maxRecalledMemories) {
        break;
      }
    }

    if (selected.isEmpty) {
      return _buildIndexSection(parsedIndex.indexText);
    }

    final sections = <String>[
      _buildIndexSection(parsedIndex.indexText),
      await _buildRecalledMemoriesSection(selected),
    ];
    return sections.join('\n\n').trim();
  }

  Future<String?> _readMemoryIndex() {
    return _readFile('/memories/MEMORY.md');
  }

  _ParsedMemoryIndex _parseIndex(String text) {
    final lines = text.split('\n');
    final limitedLines = lines.take(maxIndexLines).toList(growable: false);
    final indexLines = <String>[];
    final candidates = <MemoryTopicCandidate>[];
    final byPath = <String, MemoryTopicCandidate>{};

    for (final line in limitedLines) {
      final parsed = _parseIndexLine(line);
      if (parsed == null) {
        indexLines.add(line);
        continue;
      }
      indexLines.add(parsed.originalLine);
      candidates.add(parsed.candidate);
      byPath[parsed.candidate.agentPath] = parsed.candidate;
    }

    return _ParsedMemoryIndex(
      indexText: indexLines.join('\n').trimRight(),
      candidates: candidates,
      byPath: byPath,
    );
  }

  _ParsedIndexLine? _parseIndexLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final match = RegExp(r'^\s*-\s*\[([^\]]+)\]\(([^)]+)\)\s*[—-]?\s*(.*)$')
        .firstMatch(line);
    if (match == null) {
      return null;
    }
    final title = match.group(1)?.trim() ?? '';
    final rawPath = match.group(2)?.trim() ?? '';
    final hook = match.group(3)?.trim() ?? '';
    final agentPath = _normalizeAgentPath(rawPath);
    if (title.isEmpty || agentPath == null) {
      return null;
    }
    final topicPath = agentPath == '/memories/MEMORY.md'
        ? null
        : agentPath;
    if (topicPath == null) {
      return null;
    }
    return _ParsedIndexLine(
      originalLine: line,
      candidate: MemoryTopicCandidate(
        title: title,
        hook: hook,
        agentPath: topicPath,
        name: title,
      ),
    );
  }

  Future<String> _buildRecalledMemoriesSection(
    List<MemoryTopicCandidate> selected,
  ) async {
    final buffers = <String>[
      '# recalledMemories',
      'Memory records are context clues, not current truth. If a recalled memory names a file path, function, flag, or current repo state, verify the current state before recommending action based on it. If memory conflicts with current files or tool results, trust the current observation.',
    ];
    var totalChars = 0;
    for (final candidate in selected) {
      final text = await _readFile(candidate.agentPath);
      if (text == null || text.trim().isEmpty) {
        continue;
      }
      final trimmed = _truncateText(text.trim(), maxTopicChars);
      final section = StringBuffer()
        ..writeln('## ${candidate.agentPath}')
        ..writeln('---')
        ..writeln('name: ${candidate.name}');
      if (candidate.description != null && candidate.description!.isNotEmpty) {
        section.writeln('description: ${candidate.description!.trim()}');
      }
      section
        ..writeln('type: ${candidate.type ?? 'unknown'}')
        ..writeln('---')
        ..writeln()
        ..writeln(trimmed);
      final rendered = section.toString().trimRight();
      totalChars += rendered.length;
      if (totalChars > maxTotalTopicChars) {
        break;
      }
      buffers.add(rendered);
    }
    return buffers.join('\n\n').trim();
  }

  String _buildIndexSection(String indexText) {
    return [
      '# memoryIndex',
      'MEMORY.md is always loaded into your conversation context. Use it as an index, not as complete memory content.',
      indexText.trim(),
    ].where((section) => section.trim().isNotEmpty).join('\n');
  }

  bool _shouldIgnoreMemory(String? userInput) {
    final normalized = (userInput ?? '').toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    const patterns = <String>[
      'ignore memory',
      'do not use memory',
      "don't use memory",
      '不要使用记忆',
      '忽略记忆',
      '别参考记忆',
    ];
    return patterns.any(normalized.contains);
  }

  String? _normalizeAgentPath(String rawPath) {
    final trimmed = rawPath.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) {
      return null;
    }
    final absolute = trimmed.startsWith('/memories/')
        ? trimmed
        : p.posix.normalize('/memories/${trimmed.replaceFirst(RegExp(r'^/+'), '')}');
    final normalized = p.posix.normalize(absolute);
    if (normalized == '/memories' || normalized == '/memories/MEMORY.md') {
      return null;
    }
    if (!normalized.startsWith('/memories/')) {
      return null;
    }
    if (normalized.contains('../')) {
      return null;
    }
    return normalized;
  }

  String _truncateText(String text, int maxChars) {
    if (text.length <= maxChars) {
      return text;
    }
    return '${text.substring(0, maxChars).trimRight()}\n[memory truncated]';
  }

  Future<MemoryTopicCandidate> _enrichCandidate(MemoryTopicCandidate candidate) async {
    final topicText = await _readFile(candidate.agentPath);
    if (topicText == null || topicText.trim().isEmpty) {
      return candidate;
    }
    final parsed = _parseFrontmatter(topicText);
    if (parsed == null) {
      return candidate;
    }
    return MemoryTopicCandidate(
      title: candidate.title,
      hook: candidate.hook,
      agentPath: candidate.agentPath,
      name: parsed['name'] ?? candidate.name,
      description: parsed['description'] ?? candidate.description,
      type: parsed['type'] ?? candidate.type,
    );
  }

  Future<List<MemoryTopicCandidate>> _enrichCandidates(
    List<MemoryTopicCandidate> candidates,
  ) async {
    final enriched = <MemoryTopicCandidate>[];
    for (final candidate in candidates) {
      enriched.add(await _enrichCandidate(candidate));
    }
    return enriched;
  }

  Map<String, String>? _parseFrontmatter(String text) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('---')) {
      return null;
    }
    final lines = trimmed.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') {
      return null;
    }
    final values = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trimRight();
      if (line.trim() == '---') {
        return values;
      }
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        values[key] = value;
      }
    }
    return values;
  }

  static Future<List<String>> _defaultSelector({
    required String userInput,
    required List<MemoryTopicCandidate> candidates,
    LLMConfig? sideRuntimeConfigOverride,
    MemorySideTaskRunner? sideTaskRunner,
  }) async {
    final runner = sideTaskRunner;
    if (runner == null || candidates.isEmpty) {
      return const [];
    }
    final prompt = StringBuffer()
      ..writeln(
        'You are selecting long-term memory topics for the current turn.',
      )
      ..writeln(
        'Return only JSON array of memory paths that are clearly relevant.',
      )
      ..writeln(
        'Choose at most 5 items. Prefer explicit relevance over guesswork.',
      );
    if (userInput.trim().isNotEmpty) {
      prompt
        ..writeln()
        ..writeln('User input:')
        ..writeln(userInput.trim());
    }
    prompt
      ..writeln()
      ..writeln('Candidates:')
      ..writeln(_buildCandidateManifest(candidates));

    final response = await runner(
      [
        ChatMessage(
          text: prompt.toString().trim(),
          role: MessageRole.user,
        ),
      ],
      config: ChatConfig(
        systemPrompt: '',
        runtimeConfigOverride: sideRuntimeConfigOverride,
      ),
      requestLabel: 'memory_side_selector',
    );
    return _parseSelectedPaths(response);
  }

  static String _buildCandidateManifest(List<MemoryTopicCandidate> candidates) {
    return candidates
        .map(
          (candidate) => [
            '- path: ${candidate.agentPath}',
            '  title: ${candidate.title}',
            if (candidate.hook.isNotEmpty) '  hook: ${candidate.hook}',
            if ((candidate.description ?? '').trim().isNotEmpty)
              '  description: ${candidate.description!.trim()}',
            if ((candidate.type ?? '').trim().isNotEmpty)
              '  type: ${candidate.type!.trim()}',
          ].join('\n'),
        )
        .join('\n');
  }

  static List<String> _parseSelectedPaths(String response) {
    final trimmed = response.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final paths = <String>[];
    final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(trimmed);
    final source = jsonMatch?.group(0) ?? trimmed;
    for (final match in RegExp(r'"([^"]+)"').allMatches(source)) {
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        paths.add(value);
      }
    }
    if (paths.isNotEmpty) {
      return paths;
    }
    for (final line in trimmed.split('\n')) {
      final value = line.trim().replaceAll(RegExp(r'^[-*\d.\s]+'), '');
      if (value.isNotEmpty) {
        paths.add(value);
      }
    }
    return paths;
  }
}

class _ParsedMemoryIndex {
  final String indexText;
  final List<MemoryTopicCandidate> candidates;
  final Map<String, MemoryTopicCandidate> byPath;

  const _ParsedMemoryIndex({
    required this.indexText,
    required this.candidates,
    required this.byPath,
  });
}

class _ParsedIndexLine {
  final String originalLine;
  final MemoryTopicCandidate candidate;

  const _ParsedIndexLine({
    required this.originalLine,
    required this.candidate,
  });
}
