class ArtifactHostStyleBuilder {
  const ArtifactHostStyleBuilder();

  String buildStyleBlock(Map<String, String> hostCssVariables) {
    final variableLines = hostCssVariables.entries
        .map((entry) => '        ${entry.key}: ${entry.value};')
        .join('\n');
    final rootBlock = variableLines.isEmpty
        ? ''
        : '''
      :root {
$variableLines
      }
''';
    return '''
<style>
$rootBlock
  html, body {
    margin: 0;
    padding: 0;
    background: var(--app-artifact-page-bg, #ffffff);
    color: var(--app-artifact-text-primary, #1f1f1e);
    font-family: var(--app-artifact-font-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif);
  }

  * {
    box-sizing: border-box;
  }

  #artifact-root {
    width: 100%;
    background: var(--app-artifact-page-bg, #ffffff);
    color: var(--app-artifact-text-primary, #1f1f1e);
  }
</style>
''';
  }
}
