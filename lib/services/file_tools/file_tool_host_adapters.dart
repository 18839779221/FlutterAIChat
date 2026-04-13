import 'file_tool_path_policy.dart';
import 'file_tool_budget_service.dart';
import 'file_tool_discovery_service.dart';
import 'file_tool_read_formatter.dart';
import 'file_tool_root_service.dart';
import 'file_tool_session_guard.dart';
import 'file_tool_write_service.dart';

class FileToolHostAdapters {
  const FileToolHostAdapters({
    required this.rootService,
    required this.pathPolicy,
    required this.sessionGuard,
    required this.budgetService,
    required this.readFormatter,
    required this.discoveryService,
    this.writeService,
  });

  final FileToolRootService rootService;
  final FileToolPathPolicy pathPolicy;
  final FileToolSessionGuard sessionGuard;
  final FileToolBudgetService budgetService;
  final FileToolReadFormatter readFormatter;
  final FileToolDiscoveryService discoveryService;
  final FileToolWriteService? writeService;
}
