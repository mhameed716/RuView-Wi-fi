import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/ar_strings.dart';
import '../../core/l10n/termux_guide.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../viewmodels/connection_view_model.dart';
import 'neon_button.dart';
import 'neon_card.dart';

/// بطاقة إنقاذ تظهر حين لا توجد بوابة في الشبكة.
///
/// تعطي المستخدم مخرجين فوريين بدل شاشة فارغة:
///  1) الوضع التجريبي (محاكاة داخلية) — يملأ الواجهة ببيانات معلنة كمحاكاة.
///  2) دليل Termux — أوامر جاهزة للنسخ تُشغّل بوابة RuView حقيقية على الهاتف.
class GatewayHelpCard extends StatefulWidget {
  const GatewayHelpCard({super.key, required this.viewModel});

  final ConnectionViewModel viewModel;

  @override
  State<GatewayHelpCard> createState() => _GatewayHelpCardState();
}

class _GatewayHelpCardState extends State<GatewayHelpCard> {
  bool _stepsOpen = false;

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          ArStrings.commandsCopied,
          textDirection: TextDirection.rtl,
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      glowColor: AppColors.warning,
      borderColor: AppColors.warning.withAlpha(90),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            title: ArStrings.gatewayHelpTitle,
            subtitle: ArStrings.gatewayHelpBody,
            icon: Icons.router_outlined,
          ),
          const SizedBox(height: 14),
          NeonButton(
            key: const ValueKey<String>('start-simulator-button'),
            label: ArStrings.simulatorStart,
            icon: Icons.play_circle_outline_rounded,
            variant: NeonButtonVariant.outlined,
            height: 46,
            onPressed: () => unawaited(widget.viewModel.startSimulator()),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton.icon(
                  onPressed: () => unawaited(_copy(TermuxGuide.script)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.cyan,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 38),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.copy_all_rounded, size: 17),
                  label: const Text(
                    ArStrings.copyCommands,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _stepsOpen = !_stepsOpen),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  _stepsOpen
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  _stepsOpen ? ArStrings.hideSteps : ArStrings.showSteps,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (_stepsOpen) ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              ArStrings.termuxTitle,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              ArStrings.termuxSubtitle,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            for (final TermuxStep step in TermuxGuide.steps) ...<Widget>[
              _StepTile(
                step: step,
                onCopy: () => unawaited(_copy(step.command)),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 2),
            const Text(
              ArStrings.termuxAfterRunHint,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.6,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// خطوة واحدة: العنوان + زر نسخ + الأمر نفسه (يُعرض عند الفتح).
class _StepTile extends StatelessWidget {
  const _StepTile({required this.step, required this.onCopy});

  final TermuxStep step;
  final VoidCallback onCopy;

  /// معاينة أول ستة أسطر؛ النص الكامل يُؤخذ بزر «نسخ».
  String get _preview {
    final List<String> lines = step.command.split('\n');
    if (lines.length <= 6) return step.command;
    return '${lines.take(6).join('\n')}\n…';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  step.title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onCopy,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  ArStrings.copyStep,
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 128),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  _preview,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
