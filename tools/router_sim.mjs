#!/usr/bin/env node
/**
 * راوتر RuView الافتراضي (Router / Hotspot Lab) — نسخة Node بلا أي حزم خارجية.
 *
 * يحاكي البوابة التي يتوقّعها التطبيق على أي شبكة محلية:
 *   • HTTP  على /health و/api/v1/status   → يعرّف نفسه بـ "ruview"
 *   • WebSocket على /ws/sensing           → يبثّ إطارات sensing_update
 *   • UDP   على المنفذ 5005               → يردّ على بثّ الاكتشاف
 *     {"type":"ruview_discovery","magic":"RUVIEW_DISCOVERY_V1"} ← التطبيق
 *     {"type":"ruview_gateway","host":...,"port":...}          → البوابة
 *
 * لماذا: التطبيق يجب أن يعمل على كل راوتر وكل نقطة اتصال هاتف. هذه البوابة
 * تسمح باختبار الاكتشاف والاتصال فعليًا على هذا الجهاز (عناوين 127.x بدل
 * عناوين LAN لأن الحاوية لا تملك CAP_NET_ADMIN لإنشاء واجهة شبكة حقيقية).
 *
 * التشغيل اليدوي:
 *   node tools/router_sim.mjs --host 127.0.1.1 --port 8765
 *   node tools/router_sim.mjs --host 127.0.1.1 --port 8765 --once
 */
import http from 'node:http';
import crypto from 'node:crypto';
import dgram from 'node:dgram';

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/** إطار sensing_update بأصغر حقول يفهمها التطبيق. */
export function buildFrame(sequence = 0, now = Date.now()) {
  const phase = (now % 8000) / 8000;
  const moving = phase < 0.55;
  const motion = moving ? 0.35 + 0.5 * Math.abs(Math.sin(phase * 7)) : 0.05;
  return {
    type: 'sensing_update',
    timestamp: now,
    sequence,
    gateway: { name: 'ruview-lab', source: 'router_sim' },
    nodes: [
      {
        node_id: 1,
        role: 'tx',
        rssi: -44 - Math.round(4 * Math.sin(phase * 5)),
        position: { x: 0, y: 0, z: 0 },
      },
      {
        node_id: 2,
        role: 'rx',
        rssi: -51 - Math.round(3 * Math.cos(phase * 4)),
        position: { x: 3.2, y: 0, z: 1.1 },
      },
    ],
    features: {
      mean_rssi: -47.5,
      variance: 1.2 + motion * 2.4,
      motion_band_power: Number(motion.toFixed(3)),
      breathing_band_power: 0.18 + 0.05 * Math.sin(phase * 3),
      dominant_freq_hz: moving ? 1.4 + motion : 0.28,
      change_points: moving ? 6 : 1,
      spectral_power: 0.4 + motion,
    },
    classification: {
      motion_level: moving ? 'present_moving' : 'present_still',
      presence: true,
      confidence: moving ? 0.88 : 0.71,
    },
    vitals: { breathing_bpm: 14.5 + Math.sin(phase) * 1.5, heart_bpm: 68 },
    signal_field: { rows: 8, cols: 8 },
  };
}

function wsFrame(text) {
  const payload = Buffer.from(text, 'utf8');
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.from([0x81, len]);
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payload]);
}

/** يقرأ إطارات العميل (مقنّعة) للتعرّف على الإغلاق فقط. */
function reader(socket, onClose) {
  let buffer = Buffer.alloc(0);
  socket.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (buffer.length >= 2) {
      const opcode = buffer[0] & 0x0f;
      const masked = (buffer[1] & 0x80) === 0x80;
      let length = buffer[1] & 0x7f;
      let offset = 2;
      if (length === 126) {
        if (buffer.length < 4) return;
        length = buffer.readUInt16BE(2);
        offset = 4;
      } else if (length === 127) {
        if (buffer.length < 10) return;
        length = Number(buffer.readBigUInt64BE(2));
        offset = 10;
      }
      const maskOffset = offset;
      if (masked) offset += 4;
      if (buffer.length < offset + length) return;
      const payload = buffer.subarray(offset, offset + length);
      if (masked) {
        const mask = buffer.subarray(maskOffset, maskOffset + 4);
        for (let i = 0; i < payload.length; i += 1) payload[i] ^= mask[i % 4];
      }
      buffer = buffer.subarray(offset + length);
      if (opcode === 0x8) onClose();
      if (opcode === 0x9) socket.write(Buffer.from([0x8a, 0x00]));
    }
  });
}

/**
 * يشغّل بوابة RuView افتراضية.
 * @returns {Promise<{host:string, port:number, httpUrl:string, wsUrl:string, stats:object, close:Function}>}
 */
export function startGateway({
  host = '127.0.0.1',
  port = 8765,
  discoveryPort = 0,
  tickMs = 120,
  name = 'RuView-Lab',
  answerHttp = true,
  answerWebSocket = true,
  /** يقبل TCP ولا يردّ أبدًا — يحاكي عزل العملاء أو جهازًا لا يتكلّم HTTP. */
  silentTcp = false,
  /** يردّ على بثّ الاكتشاف ويعلن هذا المنفذ. */
  answerDiscovery = false,
  advertisePort = port,
  discoveryHost = host,
} = {}) {
  const stats = {
    http: 0,
    health: 0,
    udpQueries: 0,
    wsClients: 0,
    wsConnections: 0,
    framesSent: 0,
    silentConnections: 0,
  };
  const wsClients = new Set();
  let sequence = 0;

  const server = http.createServer((req, res) => {
    stats.http += 1;
    if (silentTcp) {
      stats.silentConnections += 1;
      return; // نترك الطلب معلّقًا عن قصد
    }
    const url = new URL(req.url || '/', `http://${host}:${port}`);
    const pathname = url.pathname;
    if (!answerHttp) {
      res.writeHead(503, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'gateway busy' }));
      return;
    }
    if (pathname === '/health' || pathname === '/api/v1/health') {
      stats.health += 1;
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(
        JSON.stringify({
          status: 'ok',
          service: 'ruview-gateway',
          name,
          version: '1.4.0',
          transport: ['websocket', 'udp'],
          sensing_path: '/ws/sensing',
        }),
      );
      return;
    }
    if (pathname === '/api/v1/status') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(
        JSON.stringify({
          service: 'ruview sensing gateway',
          up: true,
          clients: wsClients.size,
        }),
      );
      return;
    }
    if (pathname === '/api/v1/sensing/latest') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(buildFrame(sequence++, Date.now())));
      return;
    }
    res.writeHead(404, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'not found', path: pathname }));
  });

  server.on('upgrade', (req, socket) => {
    if (silentTcp || !answerWebSocket) {
      stats.silentConnections += 1;
      return;
    }
    const key = req.headers['sec-websocket-key'];
    if (!key) {
      socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
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
    stats.wsConnections += 1;
    stats.wsClients += 1;
    wsClients.add(socket);

    const send = () => {
      const text = JSON.stringify(buildFrame(sequence++, Date.now()));
      try {
        socket.write(wsFrame(text));
        stats.framesSent += 1;
      } catch {
        wsClients.delete(socket);
      }
    };
    const timer = setInterval(send, Math.max(20, tickMs));
    send();
    const cleanup = () => {
      clearInterval(timer);
      if (wsClients.delete(socket)) stats.wsClients -= 1;
    };
    reader(socket, cleanup);
    socket.on('close', cleanup);
    socket.on('error', cleanup);
  });

  let udp = null;
  let udpPort = 0;

  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.removeListener('error', reject);
      const done = () => {
        const close = async () => {
          for (const client of wsClients) client.destroy();
          wsClients.clear();
          await new Promise((done) => server.close(done));
          if (udp) await new Promise((done) => udp.close(done));
        };
        resolve({
          host,
          port,
          discoveryPort: udpPort,
          httpUrl: `http://${host}:${port}`,
          wsUrl: `ws://${host}:${port}/ws/sensing`,
          stats,
          close,
        });
      };

      if (!answerDiscovery) {
        done();
        return;
      }
      udp = dgram.createSocket({ type: 'udp4', reuseAddr: true });
      udp.on('error', reject);
      udp.on('message', (message, rinfo) => {
        const text = message.toString('utf8');
        if (!text.toLowerCase().includes('ruview')) return;
        stats.udpQueries += 1;
        const reply = JSON.stringify({
          type: 'ruview_gateway',
          host: discoveryHost,
          port: advertisePort,
          name,
        });
        udp.send(Buffer.from(reply), rinfo.port, rinfo.address, () => {});
      });
      udp.bind(discoveryPort || 0, '0.0.0.0', () => {
        udpPort = udp.address().port;
        done();
      });
    });
  });
}

/** خادم HTTP عام (ليس RuView) — لاختبار أن التطبيق لا ينخدع بأي منفذ مفتوح. */
export function startPlainServer({ host = '127.0.0.1', port = 8080 } = {}) {
  const stats = { http: 0 };
  const server = http.createServer((req, res) => {
    stats.http += 1;
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end('<html><title>لوحة الراوتر</title><body>ok</body></html>');
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.removeListener('error', reject);
      resolve({
        host,
        port,
        stats,
        close: () => new Promise((done) => server.close(done)),
      });
    });
  });
}

// ── واجهة سطر الأوامر ────────────────────────────────────────────────────
const isMain = process.argv[1] && process.argv[1].endsWith('router_sim.mjs');
if (isMain) {
  const args = process.argv.slice(2);
  const flag = (name, fallback) => {
    const i = args.indexOf(`--${name}`);
    return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
  };
  const host = flag('host', '127.0.0.1');
  const port = Number(flag('port', 8765));
  const once = args.includes('--once');

  if (once) {
    process.stdout.write(JSON.stringify(buildFrame(0, Date.now())));
    process.exit(0);
  }

  const gateway = await startGateway({
    host,
    port,
    answerDiscovery: true,
    discoveryPort: Number(flag('discovery-port', 5005)),
  });
  console.log(
    JSON.stringify({
      ready: true,
      host: gateway.host,
      port: gateway.port,
      ws: gateway.wsUrl,
      discoveryPort: gateway.discoveryPort,
    }),
  );
  const shutdown = async () => {
    await gateway.close();
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
