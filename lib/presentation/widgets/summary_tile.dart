import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'neon_card.dart';

/// بطاقة ملخص صغيرة (قيمة كبيرة + وصف + أيقونة).
class SummaryTile extends StatelessWidget {
  const SummaryTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    this.caption,
    this.progress,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final String? caption;

  /// شريط تقدّم اختياري 0..1.
  final double? progress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      borderRadius: AppTheme.radiusMedium,
      glowColor: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tone.withAlpha(24),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: tone.withAlpha(70)),
                ),
                child: Icon(icon, size: 15, color: tone),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: tone,
              height: 1.1,
            ),
          ),
          if (caption != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
                height: 1.3,
              ),
            ),
          ],
          if (progress != null) ...<Widget>[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0).toDouble(),
                minHeight: 4,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
