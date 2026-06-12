import 'package:flutter/widgets.dart';

/// Keeps an artifact row's element subtree alive when it scrolls past the
/// sliver cache extent, so the embedded WebView state survives instead of
/// being disposed and rebuilt on every scroll-back.
///
/// Unlike `StableArtifactBlock` this wrapper performs no subtree caching —
/// streaming source updates must keep flowing through to the preview surface.
/// The native WebView budget is governed separately by
/// `ArtifactWebViewLeaseCoordinator`.
class ArtifactKeepAlive extends StatefulWidget {
  const ArtifactKeepAlive({super.key, required this.child});

  final Widget child;

  @override
  State<ArtifactKeepAlive> createState() => _ArtifactKeepAliveState();
}

class _ArtifactKeepAliveState extends State<ArtifactKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
