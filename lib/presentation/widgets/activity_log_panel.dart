import 'package:flutter/material.dart';

import '../../core/l10n/ar_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/activity_event.dart';
import 'neon_card.dart';
import 'neon_button.dart';

/// بطاقة سجل الأنشطة الحية أسفل لوحة الرصد.
class ActivityLogPanel extends StatelessWidget {
  const ActivityLogPanel({
    super.key,
    required this.events,
    required this.onClear,
    this.maxItems = 14,
  });

  final List<ActivityEvent> events;
  final VoidCallback onClear;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final List<ActivityEvent> visible =
        events.length > maxItems ? events.sublist(0, maxItems) : events;

    return NeonCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: ArStrings.activityLog,
            subtitle: events.isEmpty ? null : '${events.length} حدث مسجّل',
            icon: Icons.notifications_active_outlined,
            trailing: events.isEmpty
                ? null
                : NeonIconButton(
                    icon: Icons.delete_sweep_outlined,
                    tooltip: ArStrings.clearLog,
                    size: 34,
                    onPressed: onClear,
                  ),
          ),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26, horizontal: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.hourglass_empty_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ArStrings.noEvents,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: <Widget>[
                for (int i = 0; i < visible.length; i++)
                  _EventRow(
                    event: visible[i],
                    isFirst: i == 0,
                    isLast: i == visible.length - 1,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  final ActivityEvent event;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.statusColor(event.tone);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 30,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 6),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color.withAlpha(24),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withAlpha(90)),
                  ),
                  child: Icon(_iconFor(event.kind), size: 11.5, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 5, bottom: isLast ? 12 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          event.title,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isFirst ? FontWeight.w700 : FontWeight.w600,
                            color: isFirst
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        event.relativeTimeLabel(DateTime.now()),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (event.detail != null && event.detail!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        event.detail!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.4,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(ActivityKind kind) => switch (kind) {
        ActivityKind.connection => Icons.wifi_rounded,
        ActivityKind.presence => Icons.person_search_rounded,
        ActivityKind.motion => Icons.directions_run_rounded,
        ActivityKind.breathing => Icons.air_rounded,
        ActivityKind.signal => Icons.signal_cellular_alt_rounded,
        ActivityKind.system => Icons.memory_rounded,
      };
}
