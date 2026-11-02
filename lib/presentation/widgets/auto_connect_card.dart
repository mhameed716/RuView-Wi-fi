import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/lan_scanner.dart';
import '../viewmodels/connection_view_model.dart';
import 'neon_button.dart';
import 'neon_card.dart';
import 'status_pill.dart';

/// بطاقة «الاتصال التلقائي»: تجعل التطبيق يعمل على أي راوتر/شبكة.
///
/// تعرض الشبكة الحالية، المرشّحين المكتشفين، وتتيح إعادة المسح أو الاتصال
/// بمرشّح بضغطة — بينما يبقى الإدخال اليدوي متاحًا في بطاقة الإعدادات.
class AutoConnectCard extends StatelessWidget {
  const AutoConnectCard({super.key, required this.viewModel});

  final ConnectionViewModel viewModel;

  static const String title = 'الاتصال التلقائي';
  static const String subtitle = 'يعمل على أي راوتر أو شبكة — بلا إعداد يدوي';

  @override
  Widget build(BuildContext context) {
    final bool connected = viewModel.isConnected;
    final Color color = connected
        ? AppColors.emerald
        : (viewModel.isDiscovering ? AppColors.cyan : AppColors.idle);
    final List<LanCandidate> candidates =
        viewModel.candidates.take(3).toList(growable: false);

    return NeonCard(
      glowColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withAlpha(24),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withAlpha(70)),
                ),
                child: Icon(
                  Icons.wifi_tethering_rounded,
                  size: 17,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: viewModel.discoveryLabel,
                color: color,
                pulsing: viewModel.isDiscovering,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface.withAlpha(140),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.router_outlined,
                  size: 15,
                  color: AppColors.cyan,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'الشبكة الحالية',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        viewModel.networkLabel,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${viewModel.candidates.length} مرشّح',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (viewModel.autoMessage != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              viewModel.autoMessage!,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (candidates.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Text(
              'مرشّحون مكتشفون (اضغط للاتصال)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            for (final LanCandidate candidate in candidates)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(
                  viewModel.connectToCandidate(candidate),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        candidate.looksLikeRuView
                            ? Icons.verified_rounded
                            : Icons.circle,
                        size: candidate.looksLikeRuView ? 13 : 7,
                        color: candidate.looksLikeRuView
                            ? AppColors.emerald
                            : AppColors.idle,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          candidate.label,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        candidate.sourceLabel,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${candidate.latencyMs}ms',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.idle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'الاتصال تلقائيًا عند الارتباط بالشبكة',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      viewModel.autoConnect
                          ? 'مُفعّل — يبحث ويتصل بمجرّد دخولك الشبكة'
                          : 'متوقف — الاتصال يدوي فقط',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey<String>('auto-connect-toggle'),
                value: viewModel.autoConnect,
                activeColor: AppColors.emerald,
                activeTrackColor: AppColors.emerald.withAlpha(90),
                inactiveThumbColor: AppColors.idle,
                inactiveTrackColor: AppColors.surface,
                onChanged: (bool value) =>
                    unawaited(viewModel.setAutoConnect(value)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NeonButton(
            key: const ValueKey<String>('rescan-button'),
            label: viewModel.isDiscovering ? 'جارٍ المسح…' : 'إعادة مسح الشبكة',
            icon: Icons.refresh_rounded,
            expand: true,
            onPressed: viewModel.isDiscovering
                ? null
                : () => unawaited(viewModel.rescan()),
          ),
        ],
      ),
    );
  }
}
