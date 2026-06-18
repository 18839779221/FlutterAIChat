import 'package:ai_chat/constants/route_constant.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_chat/main.dart' as app;

void main() {
  test('resolve initial route prefers a valid browser route', () {
    expect(
      app.debugResolveInitialRouteForTest(RouteConstant.settingsPage),
      RouteConstant.settingsPage,
    );
    expect(
      app.debugResolveInitialRouteForTest(RouteConstant.chatPage),
      RouteConstant.chatPage,
    );
  });

  test('resolve initial route falls back to chat page for unknown route', () {
    expect(
      app.debugResolveInitialRouteForTest('/unknown'),
      RouteConstant.chatPage,
    );
    expect(
      app.debugResolveInitialRouteForTest(null),
      RouteConstant.chatPage,
    );
  });

  test('resolve initial route prefers Uri path and fragment when provided', () {
    expect(
      app.debugResolveInitialRouteFromUriForTest(
        Uri.parse('http://127.0.0.1:7357/settings'),
      ),
      RouteConstant.settingsPage,
    );
    expect(
      app.debugResolveInitialRouteFromUriForTest(
        Uri.parse('http://127.0.0.1:7357/#/settings'),
      ),
      RouteConstant.settingsPage,
    );
  });
}
