import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:flutter/material.dart';

/// 调试功能中心页面
class DebugHubPage extends StatelessWidget {
  const DebugHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('调试中心'),
      ),
      body: ListView(
        padding: EdgeInsets.all(spacing.lg),
        children: [
          _DebugFeatureCard(
            icon: Icons.article_outlined,
            title: '文档排版调试',
            description: '测试 Markdown 渲染效果，验证文档排版的稳定性',
            colors: colors,
            spacing: spacing,
            radius: radius,
            onTap: () => Navigator.pushNamed(
              context,
              RouteConstant.layoutDebugPage,
            ),
          ),
          SizedBox(height: spacing.md),
          _DebugFeatureCard(
            icon: Icons.web_outlined,
            title: 'WebView 动态加载调试',
            description: '测试 artifact 预览的渐进渲染效果和性能表现',
            colors: colors,
            spacing: spacing,
            radius: radius,
            onTap: () => Navigator.pushNamed(
              context,
              RouteConstant.webviewDebugPage,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final AppThemeSpec colors;
  final AppSpacing spacing;
  final AppRadius radius;
  final VoidCallback onTap;

  const _DebugFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.colors,
    required this.spacing,
    required this.radius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.assistantSurface,
      borderRadius: BorderRadius.circular(radius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.lg),
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.md),
                decoration: BoxDecoration(
                  color: colors.structuredSurface,
                  borderRadius: BorderRadius.circular(radius.md),
                ),
                child: Icon(
                  icon,
                  color: colors.primaryText,
                  size: 28,
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                          ),
                    ),
                    SizedBox(height: spacing.xxs),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.secondaryText,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colors.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
