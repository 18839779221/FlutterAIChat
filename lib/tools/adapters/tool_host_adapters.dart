/// Groups host/platform adapter dependencies required by tool handlers.
///
/// The first phase of the runtime refactor only needs a lightweight container
/// so handlers can receive shared host capabilities through execution context
/// without directly depending on service-layer classes.
class ToolHostAdapters {
  const ToolHostAdapters();
}
