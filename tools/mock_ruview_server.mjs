#!/usr/bin/env node
/**
 * بوابة RuView محاكية — بلا أي تبعيات (Node.js فقط).
 *
 * الهدف: تمكين تطبيق RuView Wi-Fi من العمل والتجربة قبل توفّر أجهزة ESP32،
 * عبر بث رسائل `sensing_update` بنفس بنية خادم RuView الرسمي.
 *
 * تُقدّم:
 *   • WebSocket على  ws://<host>:<port>/ws/sensing   (بث JSON حي 10 هرتز)
 *   • REST متوافق:  /health، /api/v1/info، /api/v1/nodes،
 *                   /api/v1/sensing/latest، /api/v1/vital-signs
 *   • خدمة ملفات المعاينة من مجلّد preview/ على نفس المنفذ.
 *
 * التشغيل:
 *   node tools/mock_ruview_server.mjs --port 8080
 *   node tools/mock_ruview_server.mjs --port 8080 --token سرّي --seed-cycle
 *
 * الخيارات:
 *   --port <n>      منفذ الاستماع (افتراضي 8080)
 *   --host <addr>   عنوان الاستماع (افتراضي 0.0.0.0)
 *   --tick <ms>     فاصل البث (افتراضي 100)
 *   --token <str>   طلب  Authorization: Bearer <str> على WS و REST
 *   --once          إرسال إطار واحد وطباعته ثم الخروج (للتحقق السريع)
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PREVIEW_DIR = path.join(ROOT, 'preview');
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

// ── إعدادات ────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
function flag(name, fallback) {
  const i = args.indexOf(`--${name}`);
  if (i === -1) return fallback;
  const value = args[i + 1];
  return value === undefined || value.startsWith('--') ? true : value;
}

const PORT = Number(flag('port', process.env.PORT || 8080));
const HOST = String(flag('host', '0.0.0.0'));
const TICK_MS = Number(flag('tick', 100));
const TOKEN = flag('token', process.env.RUVIEW_API_TOKEN || '');
const SINGLE_FRAME = Boolean(flag('once', false));

// ── محاكاة الاستشعار ──────────────────────────────────────────────────────
const NODES = [
  { node_id: 1, position: [0, 0, 0], baseRssi: -42 },
  { node_id: 2, position: [4.5, 0, 2.5], baseRssi: -55 },
];

/** دورة سيناريو قصيرة: فارغة → دخول → جلوس → حركة → جلوس → مغادرة. */
const PHASES = [
  { name: 'empty', ms: 6000 },
  { name: 'enter', ms: 3500 },
  { name: 'still', ms: 14000 },
  { name: 'moving', ms: 9000 },
  { name: 'still', ms: 12000 },
  { name: 'leave', ms: 4500 },
];
const CYCLE_MS = PHASES.reduce((sum, phase) => sum + phase.ms, 0);

const state = {
  tick: 0,
  startedAt: Date.now(),
  breathPhase: 0,
};

function phaseAt(elapsed) {
  let cursor = elapsed % CYCLE_MS;
  for (const phase of PHASES) {
    if (cursor < phase.ms) return phase.name;
    cursor -= phase.ms;
  }
  return PHASES[0].name;
}

function noise(scale = 1) {
  return (Math.random() - 0.5) * 2 * scale;
}

function round(value, digits = 3) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

/** بناء رسالة sensing_update مطابقة لبنية SensingUpdate الرسمية. */
function buildSensingUpdate() {
  const elapsed = Date.now() - state.startedAt;
  const phase = phaseAt(elapsed);
  const presence = phase !== 'empty' && phase !== 'leave';
  const moving = phase === 'moving' || phase === 'enter';
  const motionLevel = !presence ? 'absent' : moving ? 'present_moving' : 'present_still';

  state.breathPhase += TICK_MS / 1000;
  const breathingRate = 14.5 + Math.sin(state.breathPhase / 9) * 1.6 + noise(0.25);
  const heartRate = 66 + Math.sin(state.breathPhase / 5) * 3 + noise(0.6);

  const motionPower = moving
    ? 0.9 + Math.abs(noise(0.55))
    : presence
      ? 0.12 + Math.abs(noise(0.07))
      : 0.02 + Math.abs(noise(0.01));

  const nodes = NODES.map((node) => {
    const rssi = node.baseRssi + noise(2.2) - (moving ? 1.5 : 0);
    const subcarriers = 64;
    const amplitude = Array.from({ length: subcarriers }, (_, i) => {
      const ripple = Math.sin((i / subcarriers) * Math.PI * 2 + state.tick / 9);
      return round(
        12 + ripple * (presence ? 2.4 : 0.7) + motionPower * 1.8 + noise(0.6),
        2,
      );
    });
    return {
      node_id: node.node_id,
      rssi_dbm: round(rssi, 1),
      position: node.position,
      amplitude,
      subcarrier_count: subcarriers,
      frame_rate_hz: round(10 + noise(0.4), 2),
      stale: false,
    };
  });

  const meanRssi = nodes.reduce((sum, node) => sum + node.rssi_dbm, 0) / nodes.length;
  const signalQuality = Math.max(
    0,
    Math.min(1, (meanRssi + 90) / 55 + noise(0.03)),
  );

  // شبكة مجال إشارة 20×20 على الأرضية — تُستخدم لخريطة الحضور.
  const grid = 20;
  const values = new Array(grid * grid);
  const blips = presence
    ? [{ x: 9 + Math.sin(state.tick / 40) * 3, z: 10 + Math.cos(state.tick / 55) * 3 }]
    : [];
  for (let z = 0; z < grid; z++) {
    for (let x = 0; x < grid; x++) {
      let value = 0.02 + Math.abs(noise(0.02));
      for (const blip of blips) {
        const d = Math.hypot(x - blip.x, z - blip.z);
        value += Math.exp(-(d * d) / (moving ? 18 : 9)) * (moving ? 1.4 : 0.8);
      }
      values[z * grid + x] = round(value, 3);
    }
  }

  // الوضعية الحالية للنموذج + مفاصل COCO 17 لاختبار رسم الهيكل والتقدير.
  const posture = !presence ? 'unknown' : moving ? 'walking' : 'sitting';
  const sway = Math.sin(state.tick / 18) * 0.015;
  const SKELETONS = {
    standing: [[0.5, 0.1], [0.47, 0.08], [0.53, 0.08], [0.46, 0.09], [0.54, 0.09], [0.42, 0.24], [0.58, 0.24], [0.4, 0.36], [0.6, 0.36], [0.39, 0.46], [0.61, 0.46], [0.45, 0.52], [0.55, 0.52], [0.46, 0.72], [0.54, 0.72], [0.47, 0.92], [0.53, 0.92]],
    walking: [[0.5, 0.1], [0.47, 0.08], [0.53, 0.08], [0.46, 0.09], [0.54, 0.09], [0.42, 0.24], [0.58, 0.24], [0.4, 0.34], [0.6, 0.36], [0.38, 0.44], [0.62, 0.46], [0.45, 0.52], [0.55, 0.52], [0.4, 0.72], [0.6, 0.7], [0.36, 0.92], [0.64, 0.9]],
    sitting: [[0.5, 0.16], [0.47, 0.14], [0.53, 0.14], [0.46, 0.15], [0.54, 0.15], [0.43, 0.3], [0.57, 0.3], [0.41, 0.42], [0.59, 0.42], [0.44, 0.52], [0.56, 0.52], [0.45, 0.6], [0.55, 0.6], [0.46, 0.66], [0.54, 0.66], [0.48, 0.86], [0.52, 0.86]],
    lying: [[0.14, 0.58], [0.15, 0.56], [0.15, 0.6], [0.13, 0.58], [0.13, 0.6], [0.32, 0.6], [0.32, 0.64], [0.46, 0.6], [0.46, 0.65], [0.52, 0.6], [0.52, 0.65], [0.62, 0.61], [0.62, 0.66], [0.78, 0.61], [0.78, 0.67], [0.92, 0.61], [0.92, 0.68]],
  };
  const JOINT_NAMES = ['nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear', 'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow', 'left_wrist', 'right_wrist', 'left_hip', 'right_hip', 'left_knee', 'right_knee', 'left_ankle', 'right_ankle'];
  const keypoints =
    posture === 'unknown'
      ? []
      : SKELETONS[posture].map(([x, y], index) => ({
          name: JOINT_NAMES[index],
          x: round(x + sway, 3),
          y: round(y, 3),
          z: 0,
          confidence: round(Math.min(0.99, 0.88 + noise(0.05)), 2),
        }));

  const persons = presence
    ? [
        {
          id: 1,
          confidence: round(Math.min(0.98, 0.72 + noise(0.08)), 2),
          bbox: { x: 0.38, y: 0.22, width: 0.24, height: 0.55 },
          zone: 'zone_living_room',
          position: [
            round(2.9 + Math.sin(state.tick / 40) * 1.1, 2),
            0,
            round(3.1 + Math.cos(state.tick / 55) * 1.1, 2),
          ],
          motion_score: round(moving ? 62 + noise(12) : 14 + noise(5), 1),
          pose: posture,
          keypoints,
        },
      ]
    : [];

  const update = {
    type: 'sensing_update',
    timestamp: Date.now() / 1000,
    source: 'mock-ruview',
    tick: state.tick++,
    nodes,
    features: {
      mean_rssi: round(meanRssi, 2),
      variance: round(presence ? 2.4 + noise(0.4) : 0.5 + noise(0.2), 3),
      motion_band_power: round(motionPower, 3),
      breathing_band_power: round(presence ? 0.35 + noise(0.05) : 0.03, 3),
      dominant_freq_hz: round(0.24 + noise(0.01), 3),
      change_points: moving ? 3 : 0,
      spectral_power: round(motionPower * 1.8, 3),
    },
    classification: {
      motion_level: motionLevel,
      presence,
      confidence: round(presence ? 0.86 + noise(0.05) : 0.12 + noise(0.04), 2),
    },
    signal_field: { grid_size: [grid, 1, grid], values },
    vital_signs: presence
      ? {
          breathing_rate_bpm: round(breathingRate, 1),
          heart_rate_bpm: round(heartRate, 1),
          breathing_confidence: round(0.72 + noise(0.06), 2),
          heartbeat_confidence: round(0.55 + noise(0.08), 2),
          signal_quality: round(signalQuality, 2),
        }
      : undefined,
    enhanced_motion: { phase, presence, moving },
    posture: posture === 'unknown' ? undefined : posture,
    signal_quality_score: round(signalQuality, 2),
    quality_verdict: signalQuality > 0.6 ? 'good' : signalQuality > 0.35 ? 'fair' : 'poor',
    estimated_persons: presence ? 1 : 0,
    persons,
  };

  return update;
}

// ── WebSocket (تنفيذ مصغّر) ────────────────────────────────────────────────
const clients = new Set();

function encodeFrame(payload, opcode = 0x1) {
  const data = Buffer.isBuffer(payload) ? payload : Buffer.from(payload, 'utf8');
  const length = data.length;
  let header;
  if (length < 126) {
    header = Buffer.alloc(2);
    header[1] = length;
  } else if (length < 65536) {
    header = Buffer.alloc(4);
    header[1] = 126;
    header.writeUInt16BE(length, 2);
  } else {
    header = Buffer.alloc(10);
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(length), 2);
  }
  header[0] = 0x80 | opcode;
  return Buffer.concat([header, data]);
}

function send(socket, text) {
  if (socket.destroyed) return;
  try {
    socket.write(encodeFrame(text));
  } catch {
    clients.delete(socket);
  }
}

/** تحليل حزم العميل (مقنّعة) للتعامل مع close/ping فقط. */
function handleClientData(socket, buffer) {
  let offset = 0;
  while (offset + 2 <= buffer.length) {
    const opcode = buffer[offset] & 0x0f;
    const masked = (buffer[offset + 1] & 0x80) !== 0;
    let length = buffer[offset + 1] & 0x7f;
    let cursor = offset + 2;
    if (length === 126) {
      if (cursor + 2 > buffer.length) return;
      length = buffer.readUInt16BE(cursor);
      cursor += 2;
    } else if (length === 127) {
      if (cursor + 8 > buffer.length) return;
      length = Number(buffer.readBigUInt64BE(cursor));
      cursor += 8;
    }
    const maskKey = masked ? buffer.subarray(cursor, cursor + 4) : null;
    if (masked) cursor += 4;
    if (cursor + length > buffer.length) return;
    const payload = Buffer.from(buffer.subarray(cursor, cursor + length));
    if (maskKey) {
      for (let i = 0; i < payload.length; i++) payload[i] ^= maskKey[i % 4];
    }
    offset = cursor + length;

    if (opcode === 0x8) {
      clients.delete(socket);
      socket.end(encodeFrame(Buffer.alloc(0), 0x8));
      return;
    }
    if (opcode === 0x9) {
      socket.write(encodeFrame(payload, 0xa));
    }
  }
}

function authorized(req, url) {
  if (!TOKEN) return true;
  const header = req.headers['authorization'] || '';
  if (header === `Bearer ${TOKEN}`) return true;
  return url.searchParams.get('token') === TOKEN || url.searchParams.get('ticket') === TOKEN;
}

// ── HTTP ──────────────────────────────────────────────────────────────────
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json',
};

let latest = buildSensingUpdate();

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, corsHeaders());
    res.end();
    return;
  }

  if (url.pathname.startsWith('/api/') || url.pathname === '/health') {
    if (!authorized(req, url)) {
      res.writeHead(401, { 'content-type': 'application/json; charset=utf-8', ...corsHeaders() });
      res.end(JSON.stringify({ error: 'unauthorized' }));
      return;
    }
    json(res, handleApi(url.pathname));
    return;
  }

  serveStatic(url.pathname, res);
});

function corsHeaders() {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
  };
}

function json(res, body) {
  const payload = JSON.stringify(body);
  res.writeHead(200, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    ...corsHeaders(),
  });
  res.end(payload);
}

function handleApi(pathname) {
  switch (pathname) {
    case '/health':
      return { status: 'ok', uptime_s: round((Date.now() - state.startedAt) / 1000, 1) };
    case '/api/v1/info':
      return {
        name: 'mock-ruview',
        version: '1.0.0-mock',
        source: 'mock',
        tick_ms: TICK_MS,
        endpoints: ['/ws/sensing', '/api/v1/sensing/latest', '/api/v1/vital-signs'],
      };
    case '/api/v1/nodes':
      return {
        nodes: latest.nodes.map((node) => ({
          node_id: node.node_id,
          rssi_dbm: node.rssi_dbm,
          frame_rate_hz: node.frame_rate_hz,
          stale: false,
        })),
      };
    case '/api/v1/sensing/latest':
      return latest;
    case '/api/v1/vital-signs':
      return latest.vital_signs ?? { status: 'no_presence' };
    default:
      return { error: 'not_found', path: pathname };
  }
}

function serveStatic(pathname, res) {
  if (pathname === '/' || pathname === '') {
    pathname = '/index.html';
  }
  const safePath = path.normalize(pathname).replace(/^(\.\.[/\\])+/, '');
  const filePath = path.join(PREVIEW_DIR, safePath);

  if (!filePath.startsWith(PREVIEW_DIR)) {
    res.writeHead(403);
    res.end('forbidden');
    return;
  }

  fs.readFile(filePath, (error, data) => {
    if (error) {
      // صفحة معاينة غير موجودة؟ نوضّح ذلك بدل 404 صامت.
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('404 — الملف غير موجود. المعاينة تقرأ من مجلّد preview/');
      return;
    }
    res.writeHead(200, {
      'content-type': MIME[path.extname(filePath)] || 'application/octet-stream',
      'cache-control': 'no-store',
    });
    res.end(data);
  });
}

server.on('upgrade', (req, socket) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (url.pathname !== '/ws/sensing' && url.pathname !== '/api/v1/stream/pose') {
    socket.write('HTTP/1.1 404 Not Found\r\n\r\n');
    socket.destroy();
    return;
  }
  if (!authorized(req, url)) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }

  const key = req.headers['sec-websocket-key'];
  if (!key) {
    socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
    socket.destroy();
    return;
  }

  const accept = crypto
    .createHash('sha1')
    .update(key + WS_GUID)
    .digest('base64');

  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
  );
  socket.setNoDelay(true);
  clients.add(socket);
  send(socket, JSON.stringify(latest));

  socket.on('data', (buffer) => handleClientData(socket, buffer));
  socket.on('close', () => clients.delete(socket));
  socket.on('error', () => clients.delete(socket));
});

// بث دوري لكل العملاء
const broadcastTimer = setInterval(() => {
  latest = buildSensingUpdate();
  if (clients.size === 0) return;
  const payload = JSON.stringify(latest);
  for (const socket of clients) send(socket, payload);
}, TICK_MS);

broadcastTimer.unref?.();

if (SINGLE_FRAME) {
  // نُزيح البداية 12 ثانية كي يقع الإطار في طور "الحضور الساكن"
  // (فيتضمّن vital_signs و persons — مفيد للتحقق وللتوثيق).
  state.startedAt = Date.now() - 12000;
  process.stdout.write(`${JSON.stringify(buildSensingUpdate(), null, 2)}\n`);
  process.exit(0);
}

server.listen(PORT, HOST, () => {
  const address = `http://${HOST === '0.0.0.0' ? 'localhost' : HOST}:${PORT}`;
  console.log('RuView mock gateway يعمل الآن');
  console.log(`  المعاينة : ${address}/`);
  console.log(`  WebSocket: ws://${HOST}:${PORT}/ws/sensing`);
  console.log(`  REST     : ${address}/api/v1/sensing/latest`);
  console.log(`  فاصل البث: ${TICK_MS} ms${TOKEN ? '  (رمز وصول مطلوب)' : ''}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    console.log('\nإيقاف بوابة المحاكاة...');
    clearInterval(broadcastTimer);
    for (const socket of clients) socket.destroy();
    server.close(() => process.exit(0));
  });
}
