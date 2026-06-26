import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_spec.dart';
import '../../theme/app_typography.dart';

/// Shared settings-domain text field shell for compact configuration forms.
class SettingsTextInputField extends StatelessWidget {
  const SettingsTextInputField({
    super.key,
    required this.label,
    required this.hintText,
    required this.controller,
    this.inputKey,
    this.focusNode,
    this.validator,
    this.onChanged,
    this.keyboardType,
    this.textInputAction,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final Key? inputKey;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final palette = _SettingsFormControlPalette.resolve(context);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.uiStyle(
            color: palette.label,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        SizedBox(height: spacing.sm),
        TextFormField(
          key: inputKey,
          controller: controller,
          focusNode: focusNode,
          validator: validator,
          onChanged: onChanged,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          style: AppTypography.uiStyle(
            color: palette.text,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppTypography.uiStyle(
              color: palette.placeholder,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.2,
            ),
            filled: true,
            fillColor: palette.fill,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radius.md),
              borderSide: BorderSide(color: palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radius.md),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radius.md),
              borderSide: BorderSide(color: palette.focusBorder),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radius.md),
              borderSide: BorderSide(color: palette.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radius.md),
              borderSide: BorderSide(color: palette.error),
            ),
            errorStyle: AppTypography.uiStyle(
              color: palette.error,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared settings-domain picker shell that mirrors the input field skeleton.
class SettingsSelectField extends StatelessWidget {
  const SettingsSelectField({
    super.key,
    required this.label,
    required this.placeholder,
    required this.onTap,
    this.valueText,
    this.enabled = true,
  });

  final String label;
  final String placeholder;
  final VoidCallback onTap;
  final String? valueText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = _SettingsFormControlPalette.resolve(context);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final hasValue = (valueText ?? '').trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.uiStyle(
            color: palette.label,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        SizedBox(height: spacing.sm),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(radius.md),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: enabled ? palette.fill : palette.disabledFill,
                borderRadius: BorderRadius.circular(radius.md),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasValue ? valueText! : placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.uiStyle(
                        color: enabled
                            ? (hasValue ? palette.text : palette.placeholder)
                            : palette.disabledText,
                        fontSize: 14,
                        fontWeight:
                            hasValue ? FontWeight.w500 : FontWeight.w400,
                        height: 1.2,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 17,
                    color: enabled ? palette.icon : palette.disabledText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsFormControlPalette {
  const _SettingsFormControlPalette({
    required this.fill,
    required this.border,
    required this.focusBorder,
    required this.text,
    required this.placeholder,
    required this.disabledText,
    required this.disabledFill,
    required this.error,
    required this.icon,
    required this.label,
  });

  final Color fill;
  final Color border;
  final Color focusBorder;
  final Color text;
  final Color placeholder;
  final Color disabledText;
  final Color disabledFill;
  final Color error;
  final Color icon;
  final Color label;

  factory _SettingsFormControlPalette.resolve(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    return _SettingsFormControlPalette(
      fill: colors.chatBackground.withValues(alpha: 0.96),
      border: colors.semantic.interaction.subtleBorder,
      focusBorder: colors.semantic.state.running,
      text: colors.primaryText,
      placeholder: colors.secondaryText.withValues(alpha: 0.72),
      disabledText: colors.secondaryText.withValues(alpha: 0.48),
      disabledFill: colors.structuredSurface.withValues(alpha: 0.62),
      error: colors.semantic.state.error,
      icon: colors.secondaryText,
      label: colors.primaryText,
    );
  }
}
