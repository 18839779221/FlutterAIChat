import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/home_top_buttons_lab_page.dart';
import 'theme/app_theme.dart';
import 'theme/app_theme_spec.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(const HomeTopButtonsLabApp());
}

class HomeTopButtonsLabApp extends StatelessWidget {
  const HomeTopButtonsLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeSpec = AppThemeSpec.claude();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Home Top Buttons Lab',
      theme: AppTheme.fromSpec(themeSpec),
      home: const HomeTopButtonsLabPage(),
    );
  }
}
