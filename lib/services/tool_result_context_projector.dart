import '../models/tool/tool_result.dart';
import '../models/skill/invoked_skill_context.dart';
import 'skills/invoked_skill_reminder_builder.dart';

/// Projects structured tool results into planner-visible context text.
/// The transcript payload remains the semantic source; summary text is UI-only.
class ToolResultContextProjector {
  const ToolResultContextProjector({
    InvokedSkillReminderBuilder invokedSkillReminderBuilder =
        const InvokedSkillReminderBuilder(),
  }) : _invokedSkillReminderBuilder = invokedSkillReminderBuilder;

  final InvokedSkillReminderBuilder _invokedSkillReminderBuilder;

  String? projectToContextText(ToolResult result) {
    final projected = switch (result.toolName.trim()) {
      'web_search' => _projectWebSearch(result),
      'generate_image' => _projectGenerateImage(result),
      'search_chat_history' => _projectSearchChatHistory(result),
      'fetch_webpage' => _projectFetchWebpage(result),
      'LS' || 'Glob' || 'Grep' => _projectDiscoveryResult(result),
      'Read' ||
      'Write' ||
      'Edit' ||
      'create_artifact' =>
        _projectFileResult(result),
      'skill' => _projectSkillResult(result),
      'create_reminder' ||
      'create_calendar_event' ||
      'share_result' =>
        _projectActionResult(result),
      _ => null,
    };
    if (projected != null && projected.trim().isNotEmpty) {
      return projected.trim();
    }
    return _projectFallback(result);
  }

  String? _projectGenerateImage(ToolResult result) {
    final prompt = result.data['prompt']?.toString().trim();
    final model = result.data['model']?.toString().trim();
    final rawImages = result.data['generatedImages'];
    final imageCount = rawImages is List ? rawImages.length : 0;
    if (imageCount == 0) {
      return null;
    }

    final noun = imageCount == 1 ? 'image' : 'images';
    final lines = <String>[
      'generate_image generated $imageCount $noun',
    ];
    if (model != null && model.isNotEmpty) {
      lines.add('model: $model');
    }
    if (prompt != null && prompt.isNotEmpty) {
      lines.add('prompt: $prompt');
    }
    return lines.join('\n');
  }

  String? _projectWebSearch(ToolResult result) {
    final query = result.data['query']?.toString().trim();
    final rawResults = result.data['results'];
    final results = rawResults is List ? rawResults : const [];
    if (query == null || query.isEmpty || results.isEmpty) {
      return null;
    }
    final lines = <String>['web_search query: $query'];
    for (var i = 0; i < results.length && i < 5; i++) {
      final item = results[i];
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final title = map['title']?.toString().trim();
      final url = map['url']?.toString().trim();
      final snippet = map['snippet']?.toString().trim();
      final parts = <String>[];
      if (title != null && title.isNotEmpty) {
        parts.add(title);
      }
      if (url != null && url.isNotEmpty) {
        parts.add(url);
      }
      if (parts.isEmpty) {
        continue;
      }
      lines.add('${i + 1}. ${parts.join(' - ')}');
      if (snippet != null && snippet.isNotEmpty) {
        lines.add('snippet: $snippet');
      }
    }
    return lines.length > 1 ? lines.join('\n') : null;
  }

  String? _projectFetchWebpage(ToolResult result) {
    final url = result.data['url']?.toString().trim();
    final title = result.data['title']?.toString().trim();
    final processed = result.data['processedContent']?.toString().trim();
    final chunks = result.data['chunks'];
    final lines = <String>[];
    if (url != null && url.isNotEmpty) {
      lines.add('fetch_webpage url: $url');
    }
    if (title != null && title.isNotEmpty) {
      lines.add('title: $title');
    }
    if (processed != null && processed.isNotEmpty) {
      lines.add(processed);
    } else if (chunks is List && chunks.isNotEmpty) {
      final chunk = chunks.first;
      if (chunk is Map) {
        final text = chunk['text']?.toString().trim();
        if (text != null && text.isNotEmpty) {
          lines.add(text);
        }
      }
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  String? _projectSearchChatHistory(ToolResult result) {
    final query = result.data['query']?.toString().trim();
    final rawMatches = result.data['matches'];
    final matches = rawMatches is List ? rawMatches : const [];
    final lines = <String>[];
    if (query != null && query.isNotEmpty) {
      lines.add('search_chat_history query: $query');
    }
    for (var i = 0; i < matches.length && i < 5; i++) {
      final item = matches[i];
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final text = map['text']?.toString().trim();
      if (text != null && text.isNotEmpty) {
        lines.add('${i + 1}. $text');
      }
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  String? _projectFileResult(ToolResult result) {
    final path = result.data['filePath']?.toString().trim() ??
        result.data['path']?.toString().trim() ??
        result.data['sourcePath']?.toString().trim();
    final message = result.data['message']?.toString().trim();
    final lines = <String>[];
    if (path != null && path.isNotEmpty) {
      lines.add('${result.toolName} path: $path');
    }
    if (message != null && message.isNotEmpty) {
      lines.add(message);
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  String? _projectDiscoveryResult(ToolResult result) {
    final lines = <String>[];
    final path = result.data['path']?.toString().trim();
    final pattern = result.data['pattern']?.toString().trim();
    if (path != null && path.isNotEmpty) {
      lines.add('${result.toolName} path: $path');
    }
    if (pattern != null && pattern.isNotEmpty) {
      lines.add('pattern: $pattern');
    }

    final entries = result.data['entries'];
    if (entries is List) {
      if (entries.isEmpty) {
        lines.add('entries: empty');
      } else {
        for (var i = 0; i < entries.length && i < 5; i++) {
          final item = entries[i];
          if (item is! Map) {
            continue;
          }
          final map = Map<String, dynamic>.from(item);
          final entryPath = map['path']?.toString().trim();
          final entryType = map['entryType']?.toString().trim() ??
              map['type']?.toString().trim();
          if (entryPath == null || entryPath.isEmpty) {
            continue;
          }
          lines.add(
            entryType == null || entryType.isEmpty
                ? entryPath
                : '$entryType: $entryPath',
          );
        }
      }
    }

    final matches = result.data['matches'];
    if (matches is List) {
      if (matches.isEmpty) {
        lines.add('matches: empty');
      } else {
        for (var i = 0; i < matches.length && i < 5; i++) {
          final item = matches[i];
          if (item is! Map) {
            continue;
          }
          final map = Map<String, dynamic>.from(item);
          final matchPath = map['path']?.toString().trim();
          final lineText = map['lineText']?.toString().trim() ??
              map['text']?.toString().trim();
          if (matchPath != null && matchPath.isNotEmpty) {
            lines.add(matchPath);
          }
          if (lineText != null && lineText.isNotEmpty) {
            lines.add(lineText);
          }
        }
      }
    }

    final message = result.data['message']?.toString().trim();
    if (message != null && message.isNotEmpty) {
      lines.add(message);
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  String? _projectActionResult(ToolResult result) {
    final title = result.data['title']?.toString().trim();
    final scheduledAt = result.data['scheduledAt']?.toString().trim() ??
        result.data['dueAt']?.toString().trim() ??
        result.data['startAt']?.toString().trim();
    final id = result.data['reminderId']?.toString().trim() ??
        result.data['eventId']?.toString().trim();
    final lines = <String>['${result.toolName} status: ${result.status.name}'];
    if (title != null && title.isNotEmpty) {
      lines.add('title: $title');
    }
    if (scheduledAt != null && scheduledAt.isNotEmpty) {
      lines.add('scheduledAt: $scheduledAt');
    }
    if (id != null && id.isNotEmpty) {
      lines.add('id: $id');
    }
    return lines.join('\n');
  }

  String? _projectSkillResult(ToolResult result) {
    final name = result.data['name']?.toString().trim();
    final qualifiedPath = result.data['qualifiedPath']?.toString().trim();
    final baseDirectory = result.data['baseDirectory']?.toString().trim();
    final instructionBody = result.data['instructionBody']?.toString().trim();

    if (name == null ||
        name.isEmpty ||
        qualifiedPath == null ||
        qualifiedPath.isEmpty ||
        baseDirectory == null ||
        baseDirectory.isEmpty ||
        instructionBody == null ||
        instructionBody.isEmpty) {
      return null;
    }

    return _invokedSkillReminderBuilder.build(
      InvokedSkillContext(
        skillId: result.data['skillId']?.toString().trim() ?? '',
        name: name,
        qualifiedPath: qualifiedPath,
        baseDirectory: baseDirectory,
        instructionBody: instructionBody,
        instructionBodyTruncated:
            result.data['instructionBodyTruncated'] == true,
        originalInstructionLength:
            result.data['originalInstructionLength'] is int
                ? result.data['originalInstructionLength'] as int
                : int.tryParse(
                    result.data['originalInstructionLength']?.toString() ?? '',
                  ),
      ),
    );
  }

  String? _projectFallback(ToolResult result) {
    if (result.status == ToolExecutionStatus.failure) {
      final error = result.errorMessage?.trim();
      if (error != null && error.isNotEmpty) {
        return '${result.toolName} failed: $error';
      }
      return '${result.toolName} failed';
    }
    if (result.data.isNotEmpty) {
      return '${result.toolName} returned structured result';
    }
    return null;
  }
}
