/// أوامر جاهزة لتشغيل بوابة RuView على الهاتف نفسه عبر Termux.
///
/// الفائدة: حين لا توجد بوابة في الشبكة (الحالة الشائعة)، يستطيع المستخدم
/// تشغيل **عملية بوابة فعلية** داخل هاتفه خلال دقيقة — بلا حاسوب ولا إعدادات
/// راوتر — للتأكد أن مسار WebSocket ← التطبيق سليم.
///
/// الأوامر هنا **مُختبَرة فعليًا**: خادم HTTP + WebSocket يخدم `/ws/sensing`
/// و`/health` ويبثّ إطارات `sensing_update` كل 200 مللي ثانية.
///
/// **حدّ صريح:** إطارات هذه البوابة مولّدة تجريبيًا؛ الاستشعار الحقيقي يتطلب
/// عُقد ESP32 CSI على الشبكة. الواجهة تنصّ على ذلك في بطاقة الإرشاد.
abstract final class TermuxGuide {
  /// الخطوات المعروضة في بطاقة الإرشاد (نص + أمر جاهز للنسخ).
  static const List<TermuxStep> steps = <TermuxStep>[
    TermuxStep(
      title: '١. ثبّت Node داخل Termux',
      command: 'pkg install nodejs -y',
    ),
    TermuxStep(
      title: '٢. أنشئ ملف البوابة',
      command: _gatewayFile,
    ),
    TermuxStep(
      title: '٣. شغّل البوابة',
      command: 'node gateway.js 8080',
    ),
    TermuxStep(
      title: '٤. تحقّق قبل فتح التطبيق',
      command: 'curl -s http://127.0.0.1:8080/health',
    ),
  ];

  /// كل الأوامر في نص واحد (زر «نسخ الأوامر»).
  static String get script =>
      steps.map((TermuxStep step) => step.command).join('\n');

  static const String expectedHealth =
      '{"status":"ok","service":"ruview-gateway","sensing_path":"/ws/sensing"}';

  static const String _gatewayFile = r'''cat > gateway.js <<'EOF'
const http = require('http'), crypto = require('crypto'), os = require('os');
const PORT = Number(process.argv[2]) || 8080;
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const NAMES = ['nose','left_eye','right_eye','left_ear','right_ear','left_shoulder','right_shoulder','left_elbow','right_elbow','left_wrist','right_wrist','left_hip','right_hip','left_knee','right_knee','left_ankle','right_ankle'];
const PTS = [[0.5,0.10],[0.47,0.08],[0.53,0.08],[0.46,0.09],[0.54,0.09],[0.42,0.24],[0.58,0.24],[0.40,0.36],[0.60,0.36],[0.39,0.46],[0.61,0.46],[0.45,0.52],[0.55,0.52],[0.46,0.72],[0.54,0.72],[0.47,0.92],[0.53,0.92]];
let tick = 0;
function frame() {
  const moving = Math.floor(tick / 25) % 2 === 0;
  const sway = Math.sin(tick / 18) * 0.015;
  return {
    type: 'sensing_update', timestamp: Date.now() / 1000, tick: tick,
    nodes: [{ node_id: 1, role: 'tx', rssi: -44 }, { node_id: 2, role: 'rx', rssi: -52 }],
    features: { mean_rssi: -48, variance: 1.6, motion_band_power: moving ? 0.9 : 0.2, breathing_band_power: 0.18, dominant_freq_hz: moving ? 1.4 : 0.28, change_points: moving ? 6 : 1, spectral_power: 0.7 },
    classification: { motion_level: moving ? 'present_moving' : 'present_still', presence: true, confidence: 0.9 },
    persons: [{ id: 1, confidence: 0.9, zone: 'living', position: [3, 0, 3], motion_score: moving ? 62 : 14, pose: moving ? 'walking' : 'standing',
      keypoints: PTS.map(([x, y], i) => ({ name: NAMES[i], x: x + sway, y: y, z: 0, confidence: 0.9 })) }],
    vital_signs: { breathing_bpm: 15, heart_bpm: 68 }
  };
}
function enc(text) {
  const p = Buffer.from(text), n = p.length; let h;
  if (n < 126) h = Buffer.from([0x81, n]);
  else if (n < 65536) { h = Buffer.alloc(4); h[0] = 0x81; h[1] = 126; h.writeUInt16BE(n, 2); }
  else { h = Buffer.alloc(10); h[0] = 0x81; h[1] = 127; h.writeBigUInt64BE(BigInt(n), 2); }
  return Buffer.concat([h, p]);
}
const clients = new Set();
http.createServer((req, res) => {
  if (req.url.startsWith('/health')) { res.writeHead(200, { 'content-type': 'application/json' }); return res.end(JSON.stringify({ status: 'ok', service: 'ruview-gateway', sensing_path: '/ws/sensing' })); }
  if (req.url.startsWith('/api/v1/sensing/latest')) { res.writeHead(200, { 'content-type': 'application/json' }); return res.end(JSON.stringify(frame())); }
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); res.end('<h1>RuView gateway</h1>');
}).on('upgrade', (req, sock) => {
  const key = req.headers['sec-websocket-key'];
  if (!key) { sock.destroy(); return; }
  const acc = crypto.createHash('sha1').update(key + GUID).digest('base64');
  sock.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + acc + '\r\n\r\n');
  clients.add(sock); sock.on('close', () => clients.delete(sock)); sock.on('error', () => clients.delete(sock));
  sock.write(enc(JSON.stringify(frame())));
}).listen(PORT, '0.0.0.0', () => {
  console.log('بوابة RuView تعمل على المنفذ ' + PORT);
  console.log('من الهاتف نفسه: ws://127.0.0.1:' + PORT + '/ws/sensing');
  Object.values(os.networkInterfaces()).flat().filter(i => i.family === 'IPv4' && !i.internal)
    .forEach(i => console.log('من جهاز آخر: ws://' + i.address + ':' + PORT + '/ws/sensing'));
});
setInterval(() => { const s = JSON.stringify(frame()); tick++; for (const c of clients) { if (!c.destroyed) { try { c.write(enc(s)); } catch { clients.delete(c); } } } }, 200);
EOF''';
}

/// خطوة واحدة في دليل التشغيل.
class TermuxStep {
  const TermuxStep({required this.title, required this.command});

  final String title;
  final String command;
}
