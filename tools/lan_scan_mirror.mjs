/**
 * نسخة JavaScript مطابقة لمنطق `lib/data/services/lan_scanner.dart`
 * (تُستخدم فقط في مختبر الراوتر لأن Dart غير متاح في بيئة التطوير هنا).
 *
 * كل دالة هنا تقابل دالة Dart بالاسم والسلوك:
 *   prefixOf / contextFromAddresses / hostsFor / scoreCandidate / ranked
 *   candidateFromDiscovery / probe / broadcastProbe / scan
 *
 * الثوابت مطابقة حرفيًا للتطبيق:
 *   المنافذ 8765, 8080, 3000, 3001 — مهلة 220ms — تزامن 96 — ميزانية 9s
 *   UDP Discovery على 5005 — السلسلة RUVIEW_DISCOVERY_V1 — أسماء المضيفين.
 */
import net from 'node:net';
import dgram from 'node:dgram';
import crypto from 'node:crypto';

export const PORTS = [8765, 3000, 3001, 8000, 8080];
export const HOSTNAMES = ['ruview.local', 'ruview', 'ruview-gateway.local'];
export const DISCOVERY_MAGIC = 'RUVIEW_DISCOVERY_V1';
export const DISCOVERY_PORT = 5005;
export const CONNECT_TIMEOUT_MS = 220;
export const CONCURRENCY = 96;
export const MAX_SCAN_MS = 9000;

export function prefixOf(ip) {
  const parts = String(ip).split('.');
  if (parts.length < 3) return String(ip);
  return `${parts[0]}.${parts[1]}.${parts[2]}`;
}

export function isPrivate(ip) {
  const parts = String(ip).split('.');
  if (parts.length !== 4) return false;
  const a = Number(parts[0]);
  const b = Number(parts[1]);
  if (!Number.isFinite(a) || !Number.isFinite(b)) return false;
  if (a === 10) return true;
  if (a === 192 && b === 168) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 100 && b >= 64 && b <= 127) return true;
  return false;
}

/**
 * بناء سياق شبكة. في المختبر نسمح بعناوين 127.x لأن الحاوية لا تستطيع إنشاء
 * واجهة LAN حقيقية؛ باقي المنطق (البادئة، البوابة، البصمة) مطابق للتطبيق.
 */
export function contextFromAddresses(addresses, { allowLoopback = false } = {}) {
  const local = [];
  const prefixes = [];
  for (const raw of addresses) {
    const ip = String(raw).trim();
    if (!ip || local.includes(ip)) continue;
    const loopback = ip.startsWith('127.');
    if (!isPrivate(ip) && !(allowLoopback && loopback)) continue;
    if (ip.startsWith('169.254.')) continue;
    local.push(ip);
    const prefix = prefixOf(ip);
    if (!prefixes.includes(prefix)) prefixes.push(prefix);
  }
  if (local.length === 0) {
    return { localAddresses: [], prefixes: [], fingerprint: 'offline' };
  }
  const sorted = [...new Set(prefixes)].sort();
  return {
    localAddresses: local,
    prefixes,
    fingerprint: sorted.join('|'),
  };
}

export function gatewayHosts(context) {
  return context.prefixes.map((prefix) => `${prefix}.1`);
}

export function hostsFor(context, { deep = false, extra = [] } = {}) {
  if (!context || context.prefixes.length === 0 || context.localAddresses.length === 0) {
    return [...extra];
  }
  const hosts = [];
  const add = (host) => {
    if (!host || hosts.includes(host)) return;
    hosts.push(host);
  };
  for (const saved of extra) add(saved);
  for (const gateway of gatewayHosts(context)) add(gateway);
  for (const local of context.localAddresses) add(local);
  for (const prefix of context.prefixes) {
    add(`${prefix}.254`);
    add(`${prefix}.2`);
    add(`${prefix}.100`);
  }
  // خادم RuView يعمل على الهاتف نفسه (نقطة اتصال + خادم على الجهاز ذاته).
  add('127.0.0.1');
  for (const hostname of HOSTNAMES) add(hostname);
  if (deep) {
    for (const prefix of context.prefixes) {
      for (let i = 1; i <= 254; i += 1) add(`${prefix}.${i}`);
    }
  }
  return hosts;
}

export function scoreCandidate(candidate) {
  let score = 0;
  if (candidate.looksLikeRuView) score += 100;
  if (candidate.isSaved) score += 45;
  if (candidate.isGateway) score += 18;
  if ((candidate.transport || 'webSocket') === 'webSocket') score += 10;
  if (candidate.port === 8765) score += 6;
  const penalty = Math.min(20, Math.max(0, Math.round((candidate.latencyMs || 0) / 25)));
  return score - penalty;
}

export function ranked(candidates) {
  return [...candidates].sort((a, b) => {
    const byScore = scoreCandidate(b) - scoreCandidate(a);
    if (byScore !== 0) return byScore;
    return (a.latencyMs || 0) - (b.latencyMs || 0);
  });
}

export function candidateFromDiscovery(payload, fallbackHost) {
  const text = String(payload || '').trim();
  if (!text || !text.toLowerCase().includes('ruview')) return null;
  try {
    const decoded = JSON.parse(text);
    if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) {
      const port = typeof decoded.port === 'number' ? Math.trunc(decoded.port) : 3000;
      const host =
        typeof decoded.host === 'string' && decoded.host.length > 0
          ? decoded.host
          : fallbackHost;
      if (!host || port <= 0 || port > 65535) return null;
      return {
        host,
        port,
        latencyMs: 0,
        looksLikeRuView: true,
        isGateway: false,
        isSaved: false,
        transport: 'webSocket',
        source: 'بثّ',
      };
    }
  } catch {
    // ردّ نصّي يذكر RuView — نقبله على المنفذ الافتراضي.
  }
  return {
    host: fallbackHost,
    port: 3000,
    latencyMs: 0,
    looksLikeRuView: true,
    isGateway: false,
    isSaved: false,
    transport: 'webSocket',
    source: 'بثّ',
  };
}

/**
 * بصمة خادم RuView من جسم الرد — مطابقة لدالة `_looksLikeRuViewBody` في Dart.
 * لا يكفي ردّ 200 ولا ورود كلمة sensing في صفحة HTML.
 */
export function looksLikeRuViewBody(text) {
  if (text.includes('sensing_update')) return true;
  if (text.includes('subcarrier')) return true;
  if (text.includes('101 switching protocols')) return true;
  if (text.includes('"ruview')) return true;
  if (text.includes('sensing_path')) return true;
  if (text.includes('ws/sensing')) return true;
  return false;
}

/** فحص منفذ واحد: TCP + طلب /health + مطابقة بصمة RuView. */
export function probe(host, port, { isGateway = false, isSaved = false } = {}) {
  const started = Date.now();
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };
    const socket = net.connect({ host, port });
    socket.setNoDelay(true);

    const timer = setTimeout(() => {
      socket.destroy();
      finish(null);
    }, CONNECT_TIMEOUT_MS + 600);

    socket.once('connect', () => {
      const latencyMs = Date.now() - started;
      let buffer = Buffer.alloc(0);
      const readTimer = setTimeout(() => {
        socket.destroy();
        finish({
          host,
          port,
          latencyMs,
          looksLikeRuView: false,
          isGateway,
          isSaved,
          transport: 'webSocket',
          source: isSaved ? 'محفوظ' : isGateway ? 'بوابة' : 'مسح',
        });
      }, 450);

      socket.write(
        `GET /health HTTP/1.1\r\nHost: ${host}:${port}\r\n` +
          'User-Agent: RuView-WiFi/1.3\r\nConnection: close\r\n\r\n',
      );
      socket.on('data', (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);
        const text = buffer.subarray(0, 2048).toString('utf8').toLowerCase();
        const looksLikeRuView = looksLikeRuViewBody(text);
        if (looksLikeRuView) {
          clearTimeout(readTimer);
          socket.destroy();
          finish({
            host,
            port,
            latencyMs,
            looksLikeRuView: true,
            isGateway,
            isSaved,
            transport: 'webSocket',
            source: isSaved ? 'محفوظ' : isGateway ? 'بوابة' : 'مسح',
          });
        }
      });
      socket.on('end', () => {
        clearTimeout(readTimer);
        const text = buffer.toString('utf8').toLowerCase();
        finish({
          host,
          port,
          latencyMs,
          looksLikeRuView: looksLikeRuViewBody(text),
          isGateway,
          isSaved,
          transport: 'webSocket',
          source: isSaved ? 'محفوظ' : isGateway ? 'بوابة' : 'مسح',
        });
      });
    });

    socket.on('error', () => {
      clearTimeout(timer);
      socket.destroy();
      finish(null);
    });
    socket.on('close', () => clearTimeout(timer));
  });
}

/** بثّ UDP للاكتشاف؛ يجمع كل الردود حتى انتهاء المهلة. */
export function broadcastProbe(
  context,
  { timeoutMs = 900, discoveryPort = DISCOVERY_PORT } = {},
) {
  if (!context || context.prefixes.length === 0) return Promise.resolve([]);
  return new Promise((resolve) => {
    const found = [];
    const seen = new Set();
    let socket;
    try {
      socket = dgram.createSocket({ type: 'udp4', reuseAddr: true });
      socket.bind(0, '0.0.0.0', () => {
        try {
          socket.setBroadcast(true);
        } catch {
          // بعض الشبكات تمنع البث المُوجّه.
        }
        const payload = Buffer.from(
          JSON.stringify({
            type: 'ruview_discovery',
            magic: DISCOVERY_MAGIC,
            app: 'ruview-wifi',
          }),
        );
        const targets = new Set([
          '255.255.255.255',
          ...context.prefixes.map((prefix) => `${prefix}.255`),
        ]);
        for (const target of targets) {
          try {
            socket.send(payload, discoveryPort, target, () => {});
          } catch {
            // نتجاهل الفشل ونتابع بقية الأهداف.
          }
        }
      });

      socket.on('message', (message, rinfo) => {
        const candidate = candidateFromDiscovery(
          message.toString('utf8'),
          rinfo.address,
        );
        if (!candidate) return;
        const key = `${candidate.host}:${candidate.port}`;
        if (seen.has(key)) return;
        seen.add(key);
        found.push(candidate);
      });
      socket.on('error', () => {});
    } catch {
      resolve([]);
      return;
    }

    const done = () => {
      try {
        socket.close();
      } catch {
        // أُغلق مسبقًا.
      }
      resolve(ranked(found));
    };
    setTimeout(done, timeoutMs);
  });
}

/** المسح الكامل — يعيد المرشّحين مرتبين بالأفضلية. */
export async function scan(
  context,
  {
    savedHosts = [],
    deep = false,
    ports = PORTS,
    concurrency = CONCURRENCY,
    maxScanMs = MAX_SCAN_MS,
    useBroadcast = true,
  } = {},
) {
  if (!context || context.prefixes.length === 0 || context.localAddresses.length === 0) {
    return [];
  }
  const broadcast = useBroadcast
    ? broadcastProbe(context)
    : Promise.resolve([]);

  const started = Date.now();
  const hosts = hostsFor(context, { deep, extra: savedHosts });
  const gateways = gatewayHosts(context);
  const targets = [];
  for (const host of hosts) {
    for (const port of ports) targets.push({ host, port });
  }

  const found = [];
  for (let index = 0; index < targets.length; index += concurrency) {
    if (Date.now() - started > maxScanMs) break;
    const batch = targets.slice(index, index + concurrency);
    const results = await Promise.all(
      batch.map((target) =>
        probe(target.host, target.port, {
          isGateway: gateways.includes(target.host),
          isSaved: savedHosts.includes(target.host),
        }),
      ),
    );
    for (const candidate of results) {
      if (candidate) found.push(candidate);
    }
    if (found.some((candidate) => candidate.looksLikeRuView)) break;
  }

  const announced = found.some((candidate) => candidate.looksLikeRuView)
    ? []
    : await broadcast;
  const all = [...found];
  for (const candidate of announced) {
    const exists = all.some(
      (other) => other.host === candidate.host && other.port === candidate.port,
    );
    if (!exists) all.push(candidate);
  }
  return ranked(all);
}

/**
 * يتصل فعليًا كالتطبيق: مصافحة WebSocket على /ws/sensing ثم انتظار إطارات.
 * (نفس ما تفعله الطبقة `WebSocketSensingTransport`؛ عميل خام بلا أي حزم.)
 */
export function connectAndReceive(
  host,
  port,
  { path = '/ws/sensing', timeoutMs = 4000 } = {},
) {
  return new Promise((resolve) => {
    const url = `ws://${host}:${port}${path}`;
    const key = crypto.randomBytes(16).toString('base64');
    let socket;
    let buffer = Buffer.alloc(0);
    let handshakeDone = false;
    let frames = 0;
    let first = null;
    let settled = false;

    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try {
        socket?.destroy();
      } catch {
        // تجاهل.
      }
      resolve({ ...result, frames, first, url });
    };
    const timer = setTimeout(
      () => finish({ ok: false, error: 'انتهت المهلة بلا إطارات' }),
      timeoutMs,
    );

    socket = net.connect({ host, port });
    socket.setNoDelay(true);
    socket.on('connect', () => {
      socket.write(
        `GET ${path} HTTP/1.1\r\nHost: ${host}:${port}\r\n` +
          'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
          `Sec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`,
      );
    });
    socket.on('error', (error) => {
      finish({ ok: false, error: `شبكة: ${error.code || error.message}` });
    });
    socket.on('close', () => {
      finish({ ok: frames > 0, error: frames > 0 ? null : 'أُغلق بلا إطارات' });
    });
    socket.on('data', (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      if (!handshakeDone) {
        const end = buffer.indexOf('\r\n\r\n');
        if (end < 0) return;
        const head = buffer.subarray(0, end).toString('utf8');
        if (!/^HTTP\/1\.1 101/.test(head) ||
            !head.toLowerCase().includes('sec-websocket-accept')) {
          finish({ ok: false, error: 'مصافحة WebSocket غير صحيحة' });
          return;
        }
        handshakeDone = true;
        buffer = buffer.subarray(end + 4);
      }
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
        if (masked) offset += 4;
        if (buffer.length < offset + length) return;
        const payload = buffer.subarray(offset, offset + length);
        buffer = buffer.subarray(offset + length);
        if (opcode !== 0x1) continue;
        frames += 1;
        if (!first) {
          try {
            first = JSON.parse(payload.toString('utf8'));
          } catch {
            first = { raw: payload.toString('utf8').slice(0, 120) };
          }
        }
        if (frames >= 2) finish({ ok: true, error: null });
      }
    });
  });
}

/** بصمة SHA-1 مطلوبة لمصافحة WebSocket (للتوافق مع بوابات حقيقية). */
export function acceptKeyFor(secWebSocketKey) {
  return crypto
    .createHash('sha1')
    .update(secWebSocketKey + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
    .digest('base64');
}
