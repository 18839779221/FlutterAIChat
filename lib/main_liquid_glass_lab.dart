import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/liquid_glass_lab_page.dart';
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

  runApp(const LiquidGlassLabApp());
}

class LiquidGlassLabApp extends StatelessWidget {
  const LiquidGlassLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeSpec = AppThemeSpec.claude();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Liquid Glass Lab',
      theme: AppTheme.fromSpec(themeSpec),
      home: const LiquidGlassLabPage(),
    );
  }
}
