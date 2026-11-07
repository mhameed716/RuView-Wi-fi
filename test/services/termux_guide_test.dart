import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/core/l10n/termux_guide.dart';

/// الدليل المدمج يجب أن يحمل بوابة كاملة قابلة للنسخ (لا نصًّا ناقصًا)، لأن
/// المستخدم يعتمد على زر «نسخ» بدل كتابة الأوامر يدويًا.
void main() {
  group('TermuxGuide', () {
    test('أربع خطوات بالترتيب المتوقع', () {
      expect(TermuxGuide.steps.length, 4);
      expect(TermuxGuide.steps.first.command, contains('pkg install nodejs'));
      expect(TermuxGuide.steps.last.command, contains('/health'));
    });

    test('النص المنسوخ يحتوي بوابة WebSocket كاملة', () {
      final String script = TermuxGuide.script;
      expect(script, contains("cat > gateway.js <<'EOF'"));
      expect(script, contains('/ws/sensing'));
      expect(script, contains('Sec-WebSocket-Accept'));
      expect(script, contains('101 Switching Protocols'));
      expect(script, contains('sensing_update'));
      expect(script, contains('node gateway.js 8080'));
      // ملف البوابة يُغلق صحيحًا ثم يُشغَّل بعده.
      expect(script.indexOf('\nEOF'), lessThan(script.indexOf('node gateway.js')));
    });

    test('التحقق المتوقع من /health مطابق لما يُطبعه الخادم', () {
      expect(TermuxGuide.expectedHealth, contains('"service":"ruview-gateway"'));
      expect(TermuxGuide.expectedHealth, contains('/ws/sensing'));
    });
  });
}
