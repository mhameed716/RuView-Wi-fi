#!/usr/bin/env node
/**
 * مختبر الراوتر: يبني راوترات ونقاط اتصال هاتف افتراضية، ثم يشغّل **نفس**
 * خوارزمية الاكتشاف المستخدمة في التطبيق (منسوخة في tools/lan_scan_mirror.mjs)
 * ويتحقّق من:
 *   1. العثور على البوابة تلقائيًا بلا أي إدخال يدوي.
 *   2. فتح WebSocket على /ws/sensing واستقبال إطارات sensing_update فعلية.
 *   3. العمل على بادئات مختلفة: 192.168.1.x، 192.168.43.x، 172.20.10.x، 10.x.
 *   4. النجاة من عزل العملاء (TCP مسدود) عبر بثّ UDP على 5005.
 *   5. عدم الانخداع بأي منفذ HTTP مفتوح ليس RuView.
 *   6. تعدد الواجهات (واي فاي + نقطة اتصال في الوقت نفسه).
 *
 * القيود المعلومة: الحاوية بلا CAP_NET_ADMIN، لذلك تُستخدم عناوين 127.x بدل
 * عناوين LAN الحقيقية؛ كل منطق البادئات والبوابات والبثّ والترتيب مطابق للـ Dart.
 *
 * التشغيل: node tools/router_lab.mjs
 */
import { startGateway, startPlainServer } from './router_sim.mjs';
import {
  connectAndReceive,
  contextFromAddresses,
  hostsFor,
  scan,
} from './lan_scan_mirror.mjs';

const DISCOVERY_PORT = 5005;
const results = [];

function record(name, ok, detail, ms) {
  results.push({ name, ok, detail, ms });
  const mark = ok ? '✓' : '✗';
  console.log(
    `${mark} ${name}${ms != null ? ` (${ms}ms)` : ''} — ${detail}`,
  );
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

async function withLab(name, setup) {
  const started = Date.now();
  try {
    const detail = await setup();
    record(name, true, detail, Date.now() - started);
  } catch (error) {
    record(name, false, error.message, Date.now() - started);
  }
}

/** 1) راوتر منزلي عادي: بوابة واحدة على .1 و RuView على 8765. */
await withLab('راوتر منزلي 192.168.1.x', async () => {
  const gateway = await startGateway({
    host: '127.0.1.1',
    port: 8765,
    discoveryPort: DISCOVERY_PORT,
    answerDiscovery: true,
  });
  try {
    const context = contextFromAddresses(['127.0.1.42'], {
      allowLoopback: true,
    });
    assert(context.prefixes[0] === '127.0.1', 'بادئة الشبكة غير صحيحة');

    const started = Date.now();
    const found = await scan(context, { savedHosts: [] });
    const elapsed = Date.now() - started;

    assert(found.length > 0, 'لم يُعثر على أي مرشّح');
    const first = found[0];
    assert(
      first.host === '127.0.1.1' && first.port === 8765,
      `أول مرشّح غير متوقّع: ${first.host}:${first.port}`,
    );
    assert(first.looksLikeRuView, 'لم يتعرّف على بصمة RuView');
    assert(first.isGateway, 'لم يميّز البوابة');

    const live = await connectAndReceive('127.0.1.1', 8765);
    assert(live.ok, `فشل الاتصال الحيّ: ${live.error}`);
    assert(live.frames >= 2, 'لم تصل إطارات كافية');
    assert(
      live.first && live.first.type === 'sensing_update',
      'نوع الرسالة غير sensing_update',
    );
    assert(
      live.first.classification && live.first.features,
      'الإطار بلا تصنيف أو ميزات',
    );

    const health = await fetch('http://127.0.1.1:8765/health').then((r) =>
      r.json(),
    );
    assert(health.status === 'ok', 'فحص /health لم يُرجع ok');

    assert(elapsed < 4000, `المسح بطيء جدًا: ${elapsed}ms`);

    // البثّ يجب أن يخرج فعلًا على الشبكة على منفذ 5005 (حتى لو لم ننتظره).
    await sleep(250);
    assert(gateway.stats.udpQueries >= 1, 'لم يصل بثّ الاكتشاف إلى البوابة');
    assert(gateway.stats.health >= 1, 'لم يُطلب /health من البوابة');

    return `وجدت ${first.host}:${first.port} في ${elapsed}ms، واستقبلت ${live.frames} إطارًا، وبثّ UDP وصل`;
  } finally {
    await gateway.close();
    await sleep(60);
  }
});

/** 2) نقطة اتصال هاتف أندرويد: البوابة على 192.168.43.1 والخدمة على 3000. */
await withLab('نقطة اتصال أندرويد 192.168.43.x', async () => {
  const gateway = await startGateway({
    host: '127.0.43.1',
    port: 3000,
    discoveryPort: DISCOVERY_PORT,
    answerDiscovery: true,
    advertisePort: 3000,
  });
  try {
    const context = contextFromAddresses(['127.0.43.129'], {
      allowLoopback: true,
    });
    const found = await scan(context);
    assert(found.length > 0, 'لم يُعثر على خادم نقطة الاتصال');
    const first = found[0];
    assert(
      first.host === '127.0.43.1' && first.port === 3000,
      `مرشّح غير متوقّع: ${first.host}:${first.port}`,
    );
    const live = await connectAndReceive('127.0.43.1', 3000);
    assert(live.ok, `فشل الاتصال: ${live.error}`);
    return `اتصال تلقائي بـ ${first.host}:${first.port} و${live.frames} إطارًا`;
  } finally {
    await gateway.close();
    await sleep(60);
  }
});

/** 3) نقطة اتصال آيفون 172.20.10.x مع بوابة على منفذ 8080 ومسح عميق. */
await withLab('نقطة اتصال آيفون 172.20.10.x', async () => {
  const gateway = await startGateway({
    host: '127.20.10.1',
    port: 8080,
    discoveryPort: DISCOVERY_PORT,
    answerDiscovery: false,
  });
  try {
    const context = contextFromAddresses(['127.20.10.4'], {
      allowLoopback: true,
    });
    const started = Date.now();
    const found = await scan(context, { deep: true });
    const elapsed = Date.now() - started;
    const first = found[0];
    assert(first, 'لم يُعثر على البوابة بالمسح العميق');
    assert(
      first.host === '127.20.10.1' && first.port === 8080,
      `مرشّح غير متوقّع: ${first.host}:${first.port}`,
    );
    const live = await connectAndReceive('127.20.10.1', 8080);
    assert(live.ok, `فشل الاتصال: ${live.error}`);
    return `مسح عميق ${elapsed}ms ثم اتصال على 8080`;
  } finally {
    await gateway.close();
    await sleep(60);
  }
});

/** 4) عزل العملاء: فحص TCP على 8765 لا يكشف الهوية، والبثّ ينقذ الموقف. */
await withLab('عزل العملاء (AP isolation)', async () => {
  const serving = await startGateway({
    host: '127.0.44.1',
    port: 3000,
    discoveryPort: DISCOVERY_PORT,
    answerDiscovery: true,
    advertisePort: 3000,
  });
  const blocked = await startGateway({
    host: '127.0.44.1',
    port: 8765,
    silentTcp: true,
  });
  try {
    const context = contextFromAddresses(['127.0.44.77'], {
      allowLoopback: true,
    });
    const found = await scan(context);
    const silent = found.find((c) => c.port === 8765);
    const announced = found.find((c) => c.port === 3000);
    assert(silent, 'لم يُسجَّل المنفذ المسدود كمرشّح ضعيف');
    assert(!silent.looksLikeRuView, 'اعتُبر المنفذ الصامت خادم RuView');
    assert(announced, 'البثّ لم يعثر على البوابة المعلنة');
    assert(announced.looksLikeRuView, 'ردّ البثّ لم يُعتبر خادم RuView');
    assert(
      found[0].port === 3000,
      `الترتيب خاطئ: أول مرشّح ${found[0].port}`,
    );
    return `تجاهل 8765 الصامت واعتمد إعلان البثّ على 3000`;
  } finally {
    await blocked.close();
    await serving.close();
    await sleep(60);
  }
});

/** 5) واجهتان معًا: واي فاي منزلي (خادم عادي) + نقطة اتصال (RuView). */
await withLab('تعدد الواجهات (واي فاي + نقطة اتصال)', async () => {
  const plain = await startPlainServer({ host: '127.0.1.1', port: 8080 });
  const gateway = await startGateway({
    host: '127.0.43.1',
    port: 3000,
    discoveryPort: DISCOVERY_PORT,
    answerDiscovery: true,
    advertisePort: 3000,
  });
  try {
    const context = contextFromAddresses(['127.0.1.42', '127.0.43.1'], {
      allowLoopback: true,
    });
    assert(context.prefixes.length === 2, 'لم تُكتشف الواجهتان');
    const hosts = hostsFor(context);
    assert(
      hosts.includes('127.0.1.1') && hosts.includes('127.0.43.1'),
      'قائمة الفحص لا تغطّي بوابتي الشبكتين',
    );

    const found = await scan(context);
    const weak = found.find(
      (c) => c.host === '127.0.1.1' && c.port === 8080,
    );
    assert(weak, 'لم يُكتشف منفذ الراوتر العادي');
    assert(
      !weak.looksLikeRuView,
      'اعتُبر خادم HTTP عادي (200) خادم RuView — خطأ في البصمة',
    );
    assert(
      found[0].host === '127.0.43.1' && found[0].port === 3000,
      `الترتيب خاطئ: أول مرشّح ${found[0].host}:${found[0].port}`,
    );
    return 'RuView على شبكة الهاتف تغلّب على لوحة راوتر عادية';
  } finally {
    await gateway.close();
    await plain.close();
    await sleep(60);
  }
});

/** 6) الخادم على حاسوب في منتصف الشبكة (لا البوابة): المسح العميق يجده. */
await withLab('خادم على حاسوب داخل الشبكة (192.168.5.77)', async () => {
  const gateway = await startGateway({
    host: '127.0.5.77',
    port: 3000,
    answerDiscovery: false,
  });
  try {
    const context = contextFromAddresses(['127.0.5.42'], {
      allowLoopback: true,
    });
    const started = Date.now();
    const found = await scan(context, { deep: true });
    const elapsed = Date.now() - started;
    const first = found[0];
    assert(first, 'المسح العميق لم يجد الخادم');
    assert(
      first.host === '127.0.5.77' && first.port === 3000,
      `مرشّح غير متوقّع: ${first.host}:${first.port}`,
    );
    const live = await connectAndReceive('127.0.5.77', 3000);
    assert(live.ok, `فشل الاتصال: ${live.error}`);
    assert(
      live.first.type === 'sensing_update',
      'الإطار المستلم ليس sensing_update',
    );
    assert(elapsed < 9000, `تجاوز الميزانية: ${elapsed}ms`);
    return `وُجد 127.0.5.77:3000 خلال ${elapsed}ms بمسح 254 عنوانًا`;
  } finally {
    await gateway.close();
    await sleep(60);
  }
});

/** 7) لوحة ويب عادية على 8080 بجانب البوابة الحقيقية: لا تتفوّق عليها. */
await withLab('لوحة ويب 8080 لا تُخدع بها بوابة RuView', async () => {
  const plain = await startPlainServer({ host: '127.0.6.1', port: 8080 });
  const gateway = await startGateway({
    host: '127.0.6.1',
    port: 8765,
    answerDiscovery: false,
  });
  try {
    const context = contextFromAddresses(['127.0.6.20'], {
      allowLoopback: true,
    });
    const found = await scan(context);
    const page = found.find((c) => c.port === 8080);
    assert(page, 'لم يُسجَّل منفذ اللوحة كمرشّح');
    assert(
      !page.looksLikeRuView,
      'صفحة HTML فيها كلمة sensing اعتُبرت بوابة RuView',
    );
    assert(
      found[0].port === 8765 && found[0].looksLikeRuView,
      `البوابة الحقيقية لم تتصدّر: ${found[0].host}:${found[0].port}`,
    );
    const live = await connectAndReceive('127.0.6.1', 8765);
    assert(live.ok, `فشل الاتصال: ${live.error}`);
    return 'البوابة على 8765 تقدّمت، واللوحة بقيت مرشّحًا ضعيفًا';
  } finally {
    await gateway.close();
    await plain.close();
    await sleep(60);
  }
});

/** 8) لا خادم على الشبكة: نتيجة فارغة سريعة بلا تعليق. */
await withLab('شبكة بلا خادم RuView', async () => {
  const context = contextFromAddresses(['127.99.0.7'], {
    allowLoopback: true,
  });
  const started = Date.now();
  const found = await scan(context, { deep: true });
  const elapsed = Date.now() - started;
  assert(found.length === 0, `توقّعنا صفرًا لكن وجدنا ${found.length}`);
  assert(elapsed < 9000, `تجاوزت الميزانية: ${elapsed}ms`);
  return `مسح 254 عنوانًا × 4 منافذ في ${elapsed}ms بلا نتائج`;
});

const failed = results.filter((r) => !r.ok);
console.log('');
console.log(
  `نتيجة المختبر: ${results.length - failed.length}/${results.length} ناجح`,
);
if (failed.length > 0) {
  for (const item of failed) console.error(`فشل: ${item.name} — ${item.detail}`);
  process.exit(1);
}
process.exit(0);
