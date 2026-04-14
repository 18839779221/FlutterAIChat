import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'file_tools/file_tool_budget_service.dart';
import 'file_tools/file_tool_discovery_service.dart';
import 'file_tools/file_tool_host_adapters.dart';
import 'file_tools/file_tool_path_policy.dart';
import 'file_tools/file_tool_read_formatter.dart';
import 'file_tools/file_tool_root_service.dart';
import 'file_tools/file_tool_session_guard.dart';
import 'file_tools/file_tool_write_service.dart';

Future<FileToolHostAdapters?> buildPlatformFileToolHostAdapters() async {
  final appSupportDirectory = await getApplicationSupportDirectory();
  final sandboxRoot = path.join(appSupportDirectory.path, 'agent');
  final rootService = FileToolRootService(
    rootDirectory: Directory(sandboxRoot),
  );
  await rootService.ensureReady();
  await rootService.resolveDirectory('memories').create(recursive: true);
  await rootService.resolveDirectory('artifacts').create(recursive: true);
  await rootService.resolveDirectory('tmp').create(recursive: true);

  final pathPolicy = FileToolPathPolicy(rootService: rootService);
  final sessionGuard = FileToolSessionGuard();
  const budgetService = FileToolBudgetService();
  const readFormatter = FileToolReadFormatter();
  final discoveryService = FileToolDiscoveryService(
    rootService: rootService,
    pathPolicy: pathPolicy,
    budgetService: budgetService,
  );
  final writeService = FileToolWriteService(
    rootService: rootService,
    sessionGuard: sessionGuard,
  );

  return FileToolHostAdapters(
    rootService: rootService,
    pathPolicy: pathPolicy,
    sessionGuard: sessionGuard,
    budgetService: budgetService,
    readFormatter: readFormatter,
    discoveryService: discoveryService,
    writeService: writeService,
  );
}
