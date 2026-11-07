import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/ar_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// شريط تحذيري ثابت يعلن أن ما يُعرض الآن بيانات محاكاة داخلية.
///
/// وجوده إلزامي في كل شاشة تُظهر أرقامًا أثناء وضع المحاكاة، حتى لا يُفهم
/// أنها قياسات حقيقية لموجات الواي فاي.
class SimulationBanner extends StatelessWidget {
  const SimulationBanner({super.key, this.onStop, this.compact = false});

  /// إيقاف المحاكاة والعودة لمحاولة الاتصال ببوابة حقيقية.
  final Future<void> Function()? onStop;

  /// نسخة مضغوطة تُستخدم داخل شاشة الرصد.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 13,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(20),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.warning.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.science_rounded,
                size: 17,
                color: AppColors.warning,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      ArStrings.simulatorBadge,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      compact
                          ? 'البيانات المعروضة مولّدة داخل التطبيق وليست استشعارًا حقيقيًا.'
                          : ArStrings.simulatorBanner,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.6,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onStop != null) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => unawaited(onStop!()),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.stop_circle_outlined, size: 17),
                label: const Text(
                  ArStrings.simulatorStop,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
