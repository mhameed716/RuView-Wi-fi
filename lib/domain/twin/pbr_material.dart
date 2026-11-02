/// خامة PBR مبسّطة تُلبَس على قطع الأثاث والجدران في مسح الغرفة.
///
/// الهدف: أن تظهر الغرفة بخامات واقعية (كتان، خشب، حجر، رخام) بدل ألوان
/// عشوائية، مع فارق واضح في اللمعان والخشونة بين الخامات.
class PbrMaterial {
  const PbrMaterial({
    required this.id,
    required this.arabicName,
    required this.albedo,
    required this.roughness,
    required this.metallic,
  });

  final String id;
  final String arabicName;

  /// لون أساسي بصيغة ARGB.
  final int albedo;

  /// خشونة السطح (0 = مرآة، 1 = مطفي).
  final double roughness;

  /// معدنية السطح (0 = عازل، 1 = معدن).
  final double metallic;

  String get label =>
      '$arabicName · خشونة ${(roughness * 100).round()}%';

  @override
  String toString() => 'PbrMaterial($id)';
}

/// مكتبة الخامات المحلية (بلا صور خارجية — ألوان + معاملات فقط).
class MaterialLibrary {
  const MaterialLibrary._();

  static const PbrMaterial fabric = PbrMaterial(
    id: 'fabric',
    arabicName: 'قماش كتان',
    albedo: 0xFF3F5F76,
    roughness: 0.88,
    metallic: 0,
  );

  static const PbrMaterial oak = PbrMaterial(
    id: 'oak',
    arabicName: 'خشب بلوط',
    albedo: 0xFF9A6A3C,
    roughness: 0.62,
    metallic: 0,
  );

  static const PbrMaterial walnut = PbrMaterial(
    id: 'walnut',
    arabicName: 'خشب جوز داكن',
    albedo: 0xFF5B3A25,
    roughness: 0.55,
    metallic: 0,
  );

  static const PbrMaterial stone = PbrMaterial(
    id: 'stone',
    arabicName: 'حجر طبيعي',
    albedo: 0xFF6E7378,
    roughness: 0.94,
    metallic: 0,
  );

  static const PbrMaterial marble = PbrMaterial(
    id: 'marble',
    arabicName: 'رخام فاتح',
    albedo: 0xFFC2C9CE,
    roughness: 0.28,
    metallic: 0.05,
  );

  static const PbrMaterial metal = PbrMaterial(
    id: 'metal',
    arabicName: 'معدن مصقول',
    albedo: 0xFF97A3AD,
    roughness: 0.22,
    metallic: 0.85,
  );

  static const PbrMaterial leather = PbrMaterial(
    id: 'leather',
    arabicName: 'جلد طبيعي',
    albedo: 0xFF4A2F2A,
    roughness: 0.66,
    metallic: 0,
  );

  static const PbrMaterial linen = PbrMaterial(
    id: 'linen',
    arabicName: 'كتان فاتح',
    albedo: 0xFFB9B2A2,
    roughness: 0.9,
    metallic: 0,
  );

  static const PbrMaterial ceramic = PbrMaterial(
    id: 'ceramic',
    arabicName: 'سيراميك',
    albedo: 0xFF8FA9B4,
    roughness: 0.34,
    metallic: 0.1,
  );

  static const List<PbrMaterial> all = <PbrMaterial>[
    fabric,
    oak,
    walnut,
    stone,
    marble,
    metal,
    leather,
    linen,
    ceramic,
  ];

  static PbrMaterial byId(String id) {
    for (final PbrMaterial material in all) {
      if (material.id == id) return material;
    }
    return stone;
  }
}
