import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/monitoring/safety_state.dart';
import 'neon_button.dart';

/// لافتة الطوارئ الحمراء أعلى شاشة الرصد عند رصد سقوط.
///
/// تبقى نابضة (توهّج وحدود) ما دام التنبيه غير مُلغى، وتعرض الزرّين
/// المطلوبين: إلغاء الإنذار، والاتصال بالطوارئ.
class EmergencyBanner extends StatefulWidget {
  const EmergencyBanner({
    super.key,
    required this.alert,
    required this.emergencyNumber,
    required this.onDismiss,
    required this.onCall,
  });

  final FallAlert alert;
  final String emergencyNumber;
  final VoidCallback onDismiss;
  final VoidCallback onCall;

  @override
  State<EmergencyBanner> createState() => _EmergencyBannerState();
}

class _EmergencyBannerState extends State<EmergencyBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (BuildContext context, Widget? child) {
        final double t = _pulse.value;
        final double alpha = 0.55 + t * 0.45;

        return Container(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[
                AppColors.danger.withAlpha((38 + t * 26).round()),
                const Color(0xFF19060B),
              ],
            ),
            border: Border.all(
              color: AppColors.danger.withAlpha((140 + t * 90).round()),
              width: 1.4,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.danger.withAlpha((70 + t * 90).round()),
                blurRadius: 26,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.danger.withAlpha(52),
                      border: Border.all(
                        color: AppColors.danger.withAlpha(
                          (150 + t * 80).round(),
                        ),
                      ),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.danger,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Opacity(
                          opacity: alpha,
                          child: const Text(
                            '⚠️ تنبيه طارئ: تم رصد حالة سقوط في الغرفة!',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFFE3E8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${widget.alert.reason} • الثقة '
                          '${widget.alert.confidenceLabel} • '
                          '${Formatters.timeAgo(widget.alert.detectedAt)}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.5,
                            color: Color(0xFFF3A7B5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: <Widget>[
                  Expanded(
                    child: NeonButton(
                      label: 'اتصال بالطوارئ (${widget.emergencyNumber})',
                      icon: Icons.call_rounded,
                      height: 46,
                      variant: NeonButtonVariant.danger,
                      onPressed: widget.onCall,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: NeonButton(
                      label: 'إلغاء الإنذار',
                      icon: Icons.cancel_outlined,
                      height: 46,
                      variant: NeonButtonVariant.outlined,
                      onPressed: widget.onDismiss,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// شريط تسلل مصغّر (تحت بطاقة الحراسة) — يظهر عند رصد حركة في وضع الحراسة.
class IntrusionStrip extends StatelessWidget {
  const IntrusionStrip({
    super.key,
    required this.alert,
    required this.onDismiss,
  });

  final IntrusionAlert alert;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(20),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.warning.withAlpha(90)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.shield_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'حركة مرصودة في وضع الحراسة '
              '(${(alert.motionIntensity * 100).round()}%) — '
              '${Formatters.timeAgo(alert.detectedAt)}',
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
