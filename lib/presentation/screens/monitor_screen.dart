import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/ar_strings.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/num_utils.dart';
import '../../data/models/sensing_frame.dart';
import '../app_scope.dart';
import '../viewmodels/connection_view_model.dart';
import '../viewmodels/sensing_view_model.dart';
import '../widgets/activity_log_panel.dart';
import '../widgets/app_background.dart';
import '../widgets/neon_button.dart';
import '../widgets/neon_card.dart';
import '../widgets/presence_radar.dart';
import '../widgets/status_pill.dart';
import '../widgets/vitals_panel.dart';

/// الشاشة الثانية: لوحة الرصد والاستشعار الحية (رادار + علامات حيوية + سجل).
class MonitorScreen extends StatelessWidget {
  const MonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final ConnectionViewModel connection = scope.connectionViewModel;
    final SensingViewModel sensing = scope.sensingViewModel;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppBackground(
        accent: AppColors.emerald,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[connection, sensing]),
            builder: (BuildContext context, Widget? child) {
              final SensingFrame? frame = sensing.latestFrame;

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _MonitorHeader(connection: connection),
                    const SizedBox(height: 16),
                    if (!connection.isConnected) ...<Widget>[
                      _OfflineBanner(onRetry: connection.connect),
                      const SizedBox(height: 14),
                    ],
                    if (connection.isDataStale) ...<Widget>[
                      const _StaleBanner(),
                      const SizedBox(height: 14),
                    ],
                    NeonCard(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                      glowColor: sensing.hasPresence
                          ? AppColors.emerald
                          : AppColors.cyan,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SectionHeader(
                            title: ArStrings.presenceRadar,
                            subtitle: ArStrings.radarHint,
                            icon: Icons.radar_rounded,
                          ),
                          PresenceRadar(
                            hasPresence: sensing.hasPresence,
                            personCount: sensing.personCount,
                            motionIntensity: sensing.motionIntensity,
                            signalQuality: sensing.signalQuality,
                            persons: frame?.persons ?? const <PersonDetection>[],
                            hasData: sensing.hasData,
                            isStale: sensing.isStale,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              InfoChip(
                                icon: Icons.people_alt_outlined,
                                label: 'الأشخاص',
                                value: '${sensing.personCount}',
                                color: sensing.hasPresence
                                    ? AppColors.emerald
                                    : AppColors.textSecondary,
                              ),
                              InfoChip(
                                icon: Icons.signal_cellular_alt_rounded,
                                label: ArStrings.signalQuality,
                                value: sensing.hasData
                                    ? NumUtils.percent(sensing.signalQuality)
                                    : '—',
                                color: AppColors.cyan,
                              ),
                              InfoChip(
                                icon: Icons.wifi_rounded,
                                label: 'RSSI',
                                value: Formatters.rssi(sensing.averageRssi),
                                color: AppColors.textSecondary,
                              ),
                              InfoChip(
                                icon: Icons.memory_rounded,
                                label: ArStrings.source,
                                value: sensing.source,
                                color: AppColors.textMuted,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    VitalsPanel(
                      breathingRate: sensing.breathingRate,
                      breathingStatus: sensing.breathingStatus,
                      breathingRatio: sensing.breathingRatio,
                      motionIntensity: sensing.motionIntensity,
                      motionLevel: sensing.motionLevel,
                      confidence: sensing.confidence,
                      breathingHistory: sensing.breathingHistory,
                      heartRate: sensing.vitalSigns?.hasHeartRate ?? false
                          ? sensing.vitalSigns?.heartRateBpm
                          : null,
                      hasData: sensing.hasData,
                    ),
                    const SizedBox(height: 14),
                    ActivityLogPanel(
                      events: sensing.events,
                      onClear: sensing.clearEvents,
                    ),
                    const SizedBox(height: 16),
                    _MonitorFooter(sensing: sensing),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MonitorHeader extends StatelessWidget {
  const _MonitorHeader({required this.connection});

  final ConnectionViewModel connection;

  @override
  Widget build(BuildContext context) {
    final bool live = connection.isConnected && !connection.isDataStale;
    return Row(
      children: <Widget>[
        NeonIconButton(
          icon: Icons.chevron_right_rounded,
          tooltip: ArStrings.back,
          onPressed: () => AppRoutes.pop(context),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                ArStrings.monitorTitle,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                connection.endpointLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        StatusPill(
          label: connection.statusLabel,
          color: live
              ? AppColors.emerald
              : (connection.isConnected
                  ? AppColors.warning
                  : (connection.status.hasError
                      ? AppColors.danger
                      : AppColors.idle)),
          pulsing: live,
          compact: true,
        ),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});

  final Future<bool> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      glowColor: AppColors.warning,
      borderColor: AppColors.warning.withAlpha(90),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.cloud_off_rounded,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '${ArStrings.statusDisconnected} — ${ArStrings.simulationNotice}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NeonButton(
            label: ArStrings.connect,
            icon: Icons.wifi_tethering_rounded,
            height: 44,
            onPressed: () => unawaitedFuture(onRetry()),
          ),
        ],
      ),
    );
  }
}

/// مساعدة صغيرة لاستدعاء مستقبل دون انتظار مع ابتلاع الأخطاء.
void unawaitedFuture(Future<Object?> future) {
  unawaited(future.then<void>((Object? _) {}).catchError((Object _) {}));
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(18),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.warning.withAlpha(70)),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.hourglass_bottom_rounded, size: 16, color: AppColors.warning),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'الاتصال قائم لكن البيانات متوقفة — تحقّق من البوابة أو العقد',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitorFooter extends StatelessWidget {
  const _MonitorFooter({required this.sensing});

  final SensingViewModel sensing;

  @override
  Widget build(BuildContext context) {
    final DateTime? last = sensing.lastFrameAt;
    return Column(
      children: <Widget>[
        Text(
          last == null
              ? ArStrings.noDataYet
              : 'آخر تحديث: ${Formatters.timeAgo(last)}',
          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          'معدل التنفس والشدة تقديرات استنتاجية من CSI وليست قياسًا طبيًا',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9.5,
            height: 1.6,
            color: AppColors.textMuted.withAlpha(210),
          ),
        ),
      ],
    );
  }
}
