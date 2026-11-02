import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/ar_strings.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/num_utils.dart';
import '../app_scope.dart';
import '../viewmodels/connection_view_model.dart';
import '../viewmodels/sensing_view_model.dart';
import '../widgets/app_background.dart';
import '../widgets/auto_connect_card.dart';
import '../widgets/connection_settings_card.dart';
import '../widgets/neon_button.dart';
import '../widgets/monitoring_dialogs.dart';
import '../widgets/neon_card.dart';
import '../widgets/posture_status_card.dart';
import '../widgets/security_mode_card.dart';
import '../widgets/status_pill.dart';
import '../widgets/summary_tile.dart';

/// الشاشة الأولى: لوحة التحكم وإعدادات الاتصال وملخّص سريع.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final ConnectionViewModel connection = scope.connectionViewModel;
    final SensingViewModel sensing = scope.sensingViewModel;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[connection, sensing]),
            builder: (BuildContext context, Widget? child) {
              if (!connection.isInitialized) {
                return const _DashboardLoading();
              }

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    BrandHeader(
                      trailing: StatusPill(
                        label: connection.statusLabel,
                        color: _statusColor(connection),
                        pulsing: connection.isBusy ||
                            (connection.isConnected && !connection.isDataStale),
                        compact: true,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ConnectionSettingsCard(viewModel: connection),
                    const SizedBox(height: 14),
                    AutoConnectCard(viewModel: connection),
                    const SizedBox(height: 14),
                    SecurityModeCard(
                      armed: sensing.intrusionArmed,
                      lastIntrusionAt: sensing.lastIntrusionAt,
                      incidentCount: sensing.securityIncidentCount,
                      emergencyNumber: sensing.emergencyNumber,
                      intrusionAlert: sensing.intrusionAlert,
                      onDismissAlert: sensing.acknowledgeIntrusion,
                      onArmedChanged: (bool value) =>
                          unawaited(sensing.setIntrusionArmed(value)),
                      onEditNumber: () =>
                          unawaited(editEmergencyNumber(context, sensing)),
                      onCallEmergency: () =>
                          unawaited(callEmergency(context, sensing)),
                    ),
                    const SizedBox(height: 20),
                    const SectionHeader(
                      title: 'ملخص سريع',
                      subtitle: 'قراءة لحظية من بوابة RuView',
                      icon: Icons.insights_rounded,
                    ),
                    _SummaryGrid(connection: connection, sensing: sensing),
                    const SizedBox(height: 16),
                    if (!connection.isConnected) ...<Widget>[
                      _NoticeBanner(
                        icon: Icons.info_outline_rounded,
                        color: AppColors.warning,
                        message: ArStrings.simulationNotice,
                      ),
                      const SizedBox(height: 16),
                    ],
                    const _MonitorCallToAction(),
                    const SizedBox(height: 18),
                    const _PrivacyFooter(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static Color _statusColor(ConnectionViewModel vm) {
    if (vm.isConnected && vm.isDataStale) return AppColors.warning;
    if (vm.isConnected) return AppColors.emerald;
    if (vm.isBusy) return AppColors.cyan;
    if (vm.status.hasError) return AppColors.danger;
    return AppColors.idle;
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.connection, required this.sensing});

  final ConnectionViewModel connection;
  final SensingViewModel sensing;

  @override
  Widget build(BuildContext context) {
    final bool online = connection.isConnected;
    final double quality = sensing.signalQuality;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = 10;
        final double itemWidth = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            SizedBox(
              width: itemWidth,
              child: SummaryTile(
                icon: Icons.memory_rounded,
                label: ArStrings.systemStatus,
                value: connection.statusLabel,
                tone: online
                    ? (connection.isDataStale ? AppColors.warning : AppColors.emerald)
                    : (connection.status.hasError ? AppColors.danger : AppColors.idle),
                caption: online
                    ? '${ArStrings.uptime}: ${Formatters.duration(connection.uptime)}'
                    : ArStrings.noDataYet,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: SummaryTile(
                icon: Icons.router_outlined,
                label: ArStrings.activeNodes,
                value: sensing.nodeCount == 0
                    ? '0'
                    : '${sensing.nodeCount}',
                tone: AppColors.cyan,
                caption: sensing.nodeCount == 0
                    ? 'لا توجد عقد متصلة'
                    : '${ArStrings.nodesUnit} في الشبكة المحلية',
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: SummaryTile(
                icon: sensing.hasPresence
                    ? Icons.person_search_rounded
                    : Icons.person_off_outlined,
                label: ArStrings.presenceNow,
                value: !sensing.hasData
                    ? '—'
                    : (sensing.hasPresence
                        ? (sensing.personCount > 1
                            ? '${sensing.personCount} أشخاص'
                            : ArStrings.personDetected)
                        : ArStrings.noPerson),
                tone: sensing.hasPresence ? AppColors.emerald : AppColors.idle,
                caption: sensing.hasData
                    ? 'شدة الحركة: ${NumUtils.percent(sensing.motionIntensity)}'
                    : ArStrings.noDataYet,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: SummaryTile(
                icon: PostureStatusCard.iconFor(sensing.posture),
                label: 'الوضعية الحالية',
                value: sensing.hasData
                    ? sensing.posture.arabicLabel
                    : '—',
                tone: PostureStatusCard.colorFor(sensing.posture),
                caption: sensing.hasData
                    ? 'المصدر: ${sensing.postureSource.arabicLabel}'
                    : ArStrings.noDataYet,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: SummaryTile(
                icon: Icons.signal_cellular_alt_rounded,
                label: ArStrings.signalQuality,
                value: sensing.hasData ? NumUtils.percent(quality) : '—',
                tone: quality >= 0.6
                    ? AppColors.emerald
                    : (quality >= 0.35 ? AppColors.warning : AppColors.danger),
                caption: sensing.hasData
                    ? Formatters.rssi(sensing.averageRssi)
                    : ArStrings.noDataYet,
                progress: sensing.hasData ? quality : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// زر بارز للانتقال إلى لوحة الرصد.
class _MonitorCallToAction extends StatelessWidget {
  const _MonitorCallToAction();

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      glowColor: AppColors.emerald,
      borderColor: AppColors.emeraldDim.withAlpha(120),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AppColors.emerald.withAlpha(26),
                  border: Border.all(color: AppColors.emerald.withAlpha(110)),
                ),
                child: const Icon(Icons.radar_rounded,
                    color: AppColors.emerald, size: 23),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      ArStrings.monitorTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      ArStrings.openMonitorHint,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded,
                  color: AppColors.textMuted, size: 22),
            ],
          ),
          const SizedBox(height: 14),
          NeonButton(
            label: ArStrings.openMonitor,
            icon: Icons.sensors_rounded,
            onPressed: () => AppRoutes.openMonitor(context),
          ),
        ],
      ),
    );
  }
}

/// شريط ملاحظة/تنبيه.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.lock_outline_rounded,
                size: 13, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'البيانات تبقى داخل شبكتك المحلية — بدون كاميرات أو سحابة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.6,
                  color: AppColors.textMuted.withAlpha(230),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'RuView Wi-Fi · الإصدار 1.0.0',
          style: TextStyle(fontSize: 9.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          SizedBox(height: 14),
          Text(
            'جارٍ تحضير لوحة التحكم...',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
