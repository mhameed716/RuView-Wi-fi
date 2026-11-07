import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/twin/pbr_material.dart';
import '../../domain/twin/room_model.dart';
import 'neon_button.dart';
import 'neon_card.dart';
import 'room_map_card.dart';

/// لوحة «إعادة بناء الغرفة»: خريطة RF-SLAM + الأثاث المصنّف بخامات PBR.
class RoomReconstructionPanel extends StatelessWidget {
  const RoomReconstructionPanel({
    super.key,
    required this.room,
    required this.onRescan,
  });

  final RoomModel room;
  final VoidCallback onRescan;

  static const String title = 'إعادة بناء الغرفة (RF-SLAM)';
  static const String subtitle =
      'انعكاسات ثابتة → شبكة إشغال → أثاث وخامات واقعية';

  @override
  Widget build(BuildContext context) {
    final List<FurnitureObject> objects =
        room.objects.take(5).toList(growable: false);

    return NeonCard(
      glowColor: AppColors.emerald,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.emerald.withAlpha(24),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.emerald.withAlpha(70)),
                ),
                child: const Icon(
                  Icons.view_in_ar_rounded,
                  size: 17,
                  color: AppColors.emerald,
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
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF060A12),
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: RoomMapView(room: room, height: 250),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _Stat(
                  label: 'مساحة سالكة',
                  value: room.hasData
                      ? '${room.freeAreaM2.toStringAsFixed(1)} م²'
                      : '—',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'قطع مصنّفة',
                  value: room.hasData ? '${room.objects.length}' : '—',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'إطارات المسح',
                  value: '${room.frames}',
                ),
              ),
            ],
          ),
          if (objects.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Text(
              'الأثاث والخامات المستنتجة',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            for (final FurnitureObject object in objects)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Color(object.material.albedo),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: Colors.white.withAlpha(30),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        object.label,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${(object.confidence * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: NeonButton(
                  key: const ValueKey<String>('room-rescan-button'),
                  label: 'إعادة مسح الغرفة',
                  icon: Icons.autorenew_rounded,
                  height: 44,
                  variant: NeonButtonVariant.outlined,
                  onPressed: onRescan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            room.summary,
            style: const TextStyle(
              fontSize: 9.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// ملخّص الخامات المستخدمة (يُعرض أسفل خريطة الغرفة عند الحاجة).
class MaterialLegend extends StatelessWidget {
  const MaterialLegend({super.key, required this.materials});

  final List<PbrMaterial> materials;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: <Widget>[
        for (final PbrMaterial material in materials)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Color(material.albedo),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                material.arabicName,
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
