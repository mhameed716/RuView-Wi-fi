/* ═══════════════════════════════════════════════════════════════════════
   RuView Wi-Fi — منطق معاينة الواجهة
   • تتصل فعليًا بـ ws://<host>/ws/sensing (بوابة المحاكاة أو بوابة RuView)
   • تعرض نفس قواعد الأحداث والشاشات الموجودة في تطبيق Flutter
   • عند تعذّر الاتصال تتحوّل إلى محاكاة محلية حتى تبقى المعاينة حيّة
   ═══════════════════════════════════════════════════════════════════════ */

(() => {
  'use strict';

  const T = {
    connected: 'متصل',
    connecting: 'جاري الاتصال...',
    reconnecting: 'إعادة محاولة الاتصال...',
    disconnected: 'غير متصل',
    error: 'فشل الاتصال',
    demo: 'محاكاة محلية',
    stale: 'لا تصل بيانات حديثة',
    udpInBrowser:
      'منفذ UDP غير متاح في المتصفح — استخدم تطبيق أندرويد لهذا الوضع. تم استخدام WebSocket بدلًا منه.',
  };

  const els = {
    dashboard: document.getElementById('screen-dashboard'),
    monitor: document.getElementById('screen-monitor'),
    host: document.getElementById('input-host'),
    port: document.getElementById('input-port'),
    token: document.getElementById('input-token'),
    secure: document.getElementById('input-secure'),
    formError: document.getElementById('form-error'),
    connectBtn: document.getElementById('connect-button'),
    connectLabel: document.getElementById('connect-button-label'),
    alertBox: document.getElementById('connection-alert'),
    alertText: document.getElementById('connection-alert-text'),
    advancedToggle: document.getElementById('advanced-toggle'),
    advancedPanel: document.getElementById('advanced-panel'),
    statusPillDash: document.getElementById('status-pill-dashboard'),
    statusTextDash: document.getElementById('status-text-dashboard'),
    statusPillMon: document.getElementById('status-pill-monitor'),
    statusTextMon: document.getElementById('status-text-monitor'),
    chipTarget: document.getElementById('chip-target'),
    chipUptime: document.getElementById('chip-uptime'),
    uptime: document.getElementById('uptime-value'),
    chipRate: document.getElementById('chip-rate'),
    rate: document.getElementById('rate-value'),
    tileSystem: document.getElementById('tile-system'),
    tileSystemValue: document.getElementById('tile-system-value'),
    tileSystemCaption: document.getElementById('tile-system-caption'),
    tileNodesValue: document.getElementById('tile-nodes-value'),
    tileNodesCaption: document.getElementById('tile-nodes-caption'),
    tilePresence: document.getElementById('tile-presence'),
    tilePresenceValue: document.getElementById('tile-presence-value'),
    tilePresenceCaption: document.getElementById('tile-presence-caption'),
    tileQualityValue: document.getElementById('tile-quality-value'),
    tileQualityCaption: document.getElementById('tile-quality-caption'),
    tileQualityBar: document.getElementById('tile-quality-bar'),
    radarCanvas: document.getElementById('radar-canvas'),
    radarCaption: document.getElementById('radar-caption'),
    radarCaptionValue: document.getElementById('radar-caption-value'),
    radarCaptionTitle: document.getElementById('radar-caption-title'),
    radarCaptionNote: document.getElementById('radar-caption-note'),
    chipPersons: document.getElementById('chip-persons'),
    chipQuality: document.getElementById('chip-quality'),
    chipRssi: document.getElementById('chip-rssi'),
    chipSource: document.getElementById('chip-source'),
    breathingPill: document.getElementById('breathing-pill'),
    breathingPillText: document.getElementById('breathing-pill-text'),
    gaugeValue: document.getElementById('gauge-value'),
    breathingValue: document.getElementById('breathing-value'),
    breathingStatus: document.getElementById('breathing-status'),
    breathingSparkLine: document.getElementById('breathing-spark-line'),
    breathingSparkFill: document.getElementById('breathing-spark-fill'),
    confidence: document.getElementById('confidence-value'),
    heart: document.getElementById('heart-value'),
    motionValue: document.getElementById('motion-value'),
    motionState: document.getElementById('motion-state'),
    motionBar: document.getElementById('motion-bar'),
    eventsList: document.getElementById('events-list'),
    eventsEmpty: document.getElementById('events-empty'),
    eventsCaption: document.getElementById('events-caption'),
    clearEvents: document.getElementById('clear-events'),
    monitorEndpoint: document.getElementById('monitor-endpoint'),
    monitorFootnote: document.getElementById('monitor-footnote'),
    back: document.getElementById('back-button'),
    openMonitor: document.getElementById('open-monitor'),
  };

  const GAUGE_CIRCUMFERENCE = 2 * Math.PI * 52; // r = 52
  const GAUGE_ARC = 0.75; // 270°

  const state = {
    settings: {
      host: location.hostname || '192.168.1.100',
      port: location.port || (location.protocol === 'file:' ? '8765' : '8080'),
      transport: 'websocket',
      token: '',
      secure: location.protocol === 'https:',
    },
    status: 'disconnected',
    socket: null,
    manualClose: false,
    frame: null,
    prevFrame: null,
    lastFrameAt: 0,
    connectedAt: 0,
    frameRate: 0,
    events: [],
    nextEventId: 1,
    cooldowns: {},
    breathingHistory: [],
    breathingSmooth: null,
    demoTimer: null,
    radarBlips: [],
    mode: 'idle', // idle | live | demo
    autoConnect: false,
  };

  // ── أدوات ───────────────────────────────────────────────────────────────
  const clamp01 = (v) => (Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0);
  const pct = (v) => `${Math.round(clamp01(v) * 100)}%`;
  const oneDecimal = (v) =>
    Number.isFinite(v) ? Number(v).toFixed(1) : '—';

  function nowMs() {
    return Date.now();
  }

  function cooldownPass(key, ms) {
    const last = state.cooldowns[key] || 0;
    if (nowMs() - last < ms) return false;
    state.cooldowns[key] = nowMs();
    return true;
  }

  function relativeTime(ts) {
    const diff = Math.round((nowMs() - ts) / 1000);
    if (diff < 3) return 'الآن';
    if (diff < 60) return `${diff} ث`;
    if (diff < 3600) return `${Math.floor(diff / 60)} د`;
    if (diff < 86400) return `${Math.floor(diff / 3600)} س`;
    return `${Math.floor(diff / 86400)} ي`;
  }

  function formatDuration(ms) {
    const total = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    const pad = (n) => String(n).padStart(2, '0');
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
  }

  // ── قواعد الأحداث (مطابقة لـ ActivityRules في Flutter) ──────────────────
  function addEvent({ kind, title, detail = null, tone = 'idle' }) {
    state.events.unshift({
      id: state.nextEventId++,
      kind,
      title,
      detail,
      tone,
      ts: nowMs(),
    });
    if (state.events.length > 20) state.events.length = 20;
    renderEvents();
  }

  const EVENT_ICONS = {
    connection:
      'M12 20a2 2 0 1 0 0-4 2 2 0 0 0 0 4Zm-4.2-6.2 1.4 1.4a4 4 0 0 1 5.6 0l1.4-1.4a6 6 0 0 0-8.4 0Zm-3-3 1.4 1.4a8.2 8.2 0 0 1 11.6 0L19.2 9.4a10.2 10.2 0 0 0-14.4 0Z',
    presence:
      'M12 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8Zm-8 16c0-3.3 3.6-6 8-6s8 2.7 8 6H4Z',
    motion: 'M13 2 4 14h6l-1 8 9-12h-6l1-8Z',
    breathing:
      'M4 12h3l2-5 3 10 2-5h6v2h-5l-3 7-3-10-1 3H4v-2Z',
    signal: 'M4 18V9h3v9H4Zm5 0V4h3v14H9Zm5 0v-6h3v6h-3Z',
    system:
      'M9 2h6v2h-1v2.2a6 6 0 0 1 3 5.2V20h2v2H5v-2h2v-8.6a6 6 0 0 1 3-5.2V4H9V2Z',
  };

  const TONE_COLORS = {
    ok: 'var(--emerald)',
    active: 'var(--cyan)',
    warning: 'var(--warning)',
    danger: 'var(--danger)',
    idle: 'var(--idle)',
  };

  function renderEvents() {
    els.eventsList.innerHTML = state.events
      .slice(0, 14)
      .map((event, index) => {
        const color = TONE_COLORS[event.tone] || TONE_COLORS.idle;
        return `
        <li>
          <span class="event__marker">
            <span class="event__dot" style="color:${color};background:color-mix(in srgb, ${color} 12%, transparent);border:1px solid color-mix(in srgb, ${color} 40%, transparent)">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="${EVENT_ICONS[event.kind] || EVENT_ICONS.system}"/></svg>
            </span>
            <span class="event__line"></span>
          </span>
          <div class="event__body">
            <div class="event__row">
              <span class="event__title" style="${index === 0 ? '' : ''}">${event.title}</span>
              <span class="event__time">${relativeTime(event.ts)}</span>
            </div>
            ${event.detail ? `<p class="event__detail">${event.detail}</p>` : ''}
          </div>
        </li>`;
      })
      .join('');

    els.eventsEmpty.hidden = state.events.length > 0;
    els.eventsCaption.textContent = state.events.length
      ? `${state.events.length} حدث مسجّل`
      : 'لا أحداث بعد';
  }

  // ── حالة الاتصال ────────────────────────────────────────────────────────
  function setStatus(status, message) {
    state.status = status;
    const tone =
      status === 'connected'
        ? state.frame && nowMs() - state.lastFrameAt > 8000
          ? 'warning'
          : 'ok'
        : status === 'connecting' || status === 'reconnecting'
          ? 'active'
          : status === 'error'
            ? 'danger'
            : status === 'demo'
              ? 'active'
              : 'idle';

    const label =
      status === 'demo'
        ? T.demo
        : status === 'connected' && nowMs() - state.lastFrameAt > 8000
          ? T.stale
          : T[status] || T.disconnected;

    for (const [pill, text] of [
      [els.statusPillDash, els.statusTextDash],
      [els.statusPillMon, els.statusTextMon],
    ]) {
      pill.dataset.tone = tone;
      pill.dataset.pulsing = String(
        status === 'connected' || status === 'connecting' || status === 'reconnecting' || status === 'demo',
      );
      text.textContent = label;
    }

    const busy = status === 'connecting' || status === 'reconnecting';
    const live = status === 'connected' || status === 'demo';

    els.connectBtn.classList.toggle('btn--primary', !live && !busy);
    els.connectBtn.classList.toggle('btn--danger', live || busy);
    if (busy) {
      els.connectBtn.innerHTML = `<span class="btn__spinner"></span><span>${T.connecting}</span>`;
    } else {
      els.connectBtn.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${
        live || busy
          ? 'M4 4h16v16H4z'
          : 'M12 20a2 2 0 1 0 0-4 2 2 0 0 0 0 4Zm-4.2-6.2 1.4 1.4a4 4 0 0 1 5.6 0l1.4-1.4a6 6 0 0 0-8.4 0Zm-3-3 1.4 1.4a8.2 8.2 0 0 1 11.6 0l1.4-1.4a10.2 10.2 0 0 0-14.4 0Z'
      }"/></svg><span>${live || busy ? 'قطع الاتصال' : 'اتصال'}</span>`;
    }

    if (status === 'error' && message) {
      els.alertText.textContent = message;
      els.alertBox.hidden = false;
    } else if (status === 'connected' || status === 'demo') {
      els.alertBox.hidden = true;
    }

    updatePreviewBadge();
  }

  function updatePreviewBadge() {
    let badge = document.querySelector('.preview-badge');
    if (!badge) {
      badge = document.createElement('div');
      badge.className = 'preview-badge';
      document.body.appendChild(badge);
    }
    const mode =
      state.mode === 'live'
        ? 'متصل بالبوابة'
        : state.mode === 'demo'
          ? 'محاكاة محلية'
          : 'غير متصل';
    badge.innerHTML = `معاينة تصميم · <b>${mode}</b>`;
  }

  // ── الاتصال ─────────────────────────────────────────────────────────────
  function validate() {
    const host = els.host.value.trim();
    const port = Number(els.port.value.trim());
    if (!host || /[\s/]/.test(host)) {
      return { ok: false, message: 'أدخل عنوان IP أو اسم مضيف صالحًا' };
    }
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      return { ok: false, message: 'أدخل رقم منفذ بين 1 و 65535' };
    }
    return { ok: true, host, port };
  }

  function connect({ auto = false } = {}) {
    state.autoConnect = auto;
    const result = validate();
    if (!result.ok) {
      els.formError.textContent = result.message;
      els.formError.hidden = false;
      els.host.setAttribute('aria-invalid', String(!result.host));
      els.port.setAttribute('aria-invalid', String(!result.port));
      return;
    }
    els.formError.hidden = true;
    els.host.removeAttribute('aria-invalid');
    els.port.removeAttribute('aria-invalid');

    if (state.settings.transport === 'udp') {
      els.alertText.textContent = T.udpInBrowser;
      els.alertBox.hidden = false;
    }

    stopDemo();
    closeSocket(true);
    state.manualClose = false;
    state.settings.host = result.host;
    state.settings.port = result.port;
    state.settings.token = els.token.value.trim();
    state.settings.secure = els.secure.checked;

    const scheme = state.settings.secure ? 'wss' : 'ws';
    const tokenQuery = state.settings.token
      ? `?token=${encodeURIComponent(state.settings.token)}`
      : '';
    // عند مخاطبة نفس أصل الصفحة (مثلًا عبر وكيل معاينة) لا نضيف منفذًا صريحًا
    // حتى يعمل الترقية عبر HTTPS/WSS على المنفذ الافتراضي.
    const sameOrigin =
      result.host === location.hostname &&
      (location.port === '' || String(result.port) === location.port);
    const authority = sameOrigin ? location.host : `${result.host}:${result.port}`;
    const url = `${scheme}://${authority}/ws/sensing${tokenQuery}`;

    setStatus('connecting');
    let socket;
    try {
      socket = new WebSocket(url);
    } catch (error) {
      handleConnectFailure(`تعذّر إنشاء اتصال: ${error.message}`);
      return;
    }

    state.socket = socket;
    const connectTimeout = setTimeout(() => {
      if (socket.readyState !== WebSocket.OPEN) {
        try {
          socket.close();
        } catch {
          /* ignore */
        }
        handleConnectFailure('انتهت مهلة الاتصال (8 ث)');
      }
    }, 8000);

    socket.onopen = () => {
      clearTimeout(connectTimeout);
      state.autoConnect = false;
      state.connectedAt = nowMs();
      state.mode = 'live';
      setStatus('connected');
      elementsToggleConnectingState(false);
      addEvent({ kind: 'connection', title: 'تم الاتصال بالبوابة', tone: 'ok', detail: url });
    };

    socket.onmessage = (event) => {
      try {
        const payload = JSON.parse(event.data);
        handleFrame(payload);
      } catch {
        /* رسالة غير JSON */
      }
    };

    socket.onerror = () => {
      clearTimeout(connectTimeout);
      if (!state.manualClose) {
        handleConnectFailure('تعذّر الوصول إلى الخادم، تحقّق من العنوان والشبكة');
      }
    };

    socket.onclose = () => {
      clearTimeout(connectTimeout);
      if (state.manualClose) return;
      if (state.mode === 'live') {
        addEvent({ kind: 'connection', title: 'تم قطع الاتصال', tone: 'idle' });
      }
      state.mode = 'idle';
      setStatus('disconnected');
    };
  }

  function elementsToggleConnectingState() {
    /* الحالة تُدار داخل setStatus */
  }

  function handleConnectFailure(message) {
    if (state.manualClose) return;
    const wasAuto = state.autoConnect;
    state.autoConnect = false;
    state.mode = 'idle';
    setStatus('error', message);

    // محاولة تلقائية عند فتح الصفحة: لا نُقلق الزائر برسالة خطأ،
    // ننتقل مباشرة إلى محاكاة محلية تُظهر الواجهة كاملة.
    if (!wasAuto) {
      addEvent({
        kind: 'connection',
        title: 'تعذّر الاتصال بالبوابة',
        detail: message,
        tone: 'danger',
      });
    }
    startDemo();
  }

  function closeSocket(silent) {
    const socket = state.socket;
    state.socket = null;
    if (!socket) return;
    try {
      socket.onclose = null;
      socket.onerror = null;
      socket.onmessage = null;
      socket.close();
    } catch {
      /* ignore */
    }
    if (!silent) {
      state.mode = 'idle';
      setStatus('disconnected');
    }
  }

  function disconnect() {
    state.manualClose = true;
    stopDemo();
    closeSocket(true);
    state.mode = 'idle';
    setStatus('disconnected');
    addEvent({ kind: 'connection', title: 'تم قطع الاتصال', tone: 'idle' });
  }

  // ── محاكاة محلية (تعمل حتى بدون خادم) ──────────────────────────────────
  function startDemo() {
    stopDemo();
    state.mode = 'demo';
    state.connectedAt = nowMs();
    setStatus('demo');
    addEvent({
      kind: 'system',
      title: 'بدأت المحاكاة المحلية للمعاينة',
      detail: 'شغّل tools/mock_ruview_server.mjs لعرض بيانات حيّة',
      tone: 'warning',
    });

    let tick = 0;
    state.demoTimer = setInterval(() => {
      tick += 1;
      handleFrame(buildDemoFrame(tick));
    }, 100);
  }

  function stopDemo() {
    if (state.demoTimer) {
      clearInterval(state.demoTimer);
      state.demoTimer = null;
    }
  }

  function buildDemoFrame(tick) {
    const cycle = tick % 380;
    const presence = cycle > 30 && cycle < 350;
    const moving = (cycle > 60 && cycle < 130) || (cycle > 230 && cycle < 290);
    const breathe = 14.5 + Math.sin(tick / 40) * 1.8 + (Math.random() - 0.5) * 0.4;
    const motionPower = moving ? 0.9 + Math.random() * 0.5 : presence ? 0.14 + Math.random() * 0.08 : 0.02;

    return {
      type: 'sensing_update',
      timestamp: nowMs() / 1000,
      source: 'simulation',
      tick,
      nodes: [
        { node_id: 1, rssi_dbm: -41 - Math.random() * 4, position: [0, 0, 0], amplitude: [], subcarrier_count: 64 },
        { node_id: 2, rssi_dbm: -54 - Math.random() * 5, position: [4.5, 0, 2.5], amplitude: [], subcarrier_count: 64 },
      ],
      features: {
        mean_rssi: -48,
        variance: presence ? 2.3 : 0.5,
        motion_band_power: motionPower,
        breathing_band_power: presence ? 0.35 : 0.03,
        dominant_freq_hz: 0.24,
        change_points: moving ? 3 : 0,
        spectral_power: motionPower * 1.8,
      },
      classification: {
        motion_level: !presence ? 'absent' : moving ? 'present_moving' : 'present_still',
        presence,
        confidence: presence ? 0.86 : 0.12,
      },
      signal_field: { grid_size: [0, 0, 0], values: [] },
      vital_signs: presence
        ? {
            breathing_rate_bpm: Number(breathe.toFixed(1)),
            heart_rate_bpm: Number((67 + Math.sin(tick / 30) * 3).toFixed(1)),
            breathing_confidence: 0.74,
            heartbeat_confidence: 0.58,
            signal_quality: 0.78,
          }
        : undefined,
      signal_quality_score: 0.78,
      estimated_persons: presence ? 1 : 0,
      persons: presence
        ? [
            {
              id: 1,
              confidence: 0.9,
              position: [2.6 + Math.sin(tick / 45) * 1.2, 0, 3 + Math.cos(tick / 60) * 1.2],
              motion_score: moving ? 68 : 14,
              keypoints: [],
            },
          ]
        : [],
    };
  }

  // ── معالجة الإطارات ────────────────────────────────────────────────────
  function handleFrame(payload) {
    if (!payload || typeof payload !== 'object') return;
    const classification = payload.classification || {};
    const frame = {
      type: payload.type || 'sensing_update',
      source: payload.source || 'unknown',
      nodes: Array.isArray(payload.nodes) ? payload.nodes : [],
      features: payload.features || {},
      classification: {
        motion_level: classification.motion_level || 'unknown',
        presence: Boolean(classification.presence),
        confidence: Number(classification.confidence || 0),
      },
      vitalSigns: payload.vital_signs || null,
      persons: Array.isArray(payload.persons) ? payload.persons : [],
      estimatedPersons:
        payload.estimated_persons === undefined ? null : Number(payload.estimated_persons),
      signalQualityScore:
        payload.signal_quality_score === undefined ? null : Number(payload.signal_quality_score),
    };

    state.prevFrame = state.frame;
    state.frame = frame;
    const now = nowMs();

    if (state.lastFrameAt) {
      const delta = (now - state.lastFrameAt) / 1000;
      if (delta > 0) {
        const instant = 1 / delta;
        state.frameRate = state.frameRate ? state.frameRate * 0.85 + instant * 0.15 : instant;
      }
    }
    state.lastFrameAt = now;

    const bpm = frame.vitalSigns ? Number(frame.vitalSigns.breathing_rate_bpm) : NaN;
    if (Number.isFinite(bpm) && bpm > 0) {
      state.breathingSmooth = state.breathingSmooth
        ? state.breathingSmooth * 0.78 + bpm * 0.22
        : bpm;
      state.breathingHistory.push(bpm);
      if (state.breathingHistory.length > 48) state.breathingHistory.shift();
    }

    evaluateRules(state.prevFrame, frame);
    render();
  }

  function evaluateRules(prev, frame) {
    if (!prev) {
      addEvent({
        kind: 'system',
        title: 'بدأ استقبال بيانات الاستشعار',
        detail: frame.source,
        tone: 'ok',
      });
      return;
    }

    const wasPresence = prev.classification.presence || prev.persons.length > 0;
    const hasPresence = frame.classification.presence || frame.persons.length > 0;
    if (wasPresence !== hasPresence) {
      addEvent(
        hasPresence
          ? { kind: 'presence', title: 'تم رصد حضور في المنطقة', tone: 'ok' }
          : { kind: 'presence', title: 'غادر الشخص المنطقة', tone: 'idle' },
      );
    }

    const wasMoving = /moving|active/.test(prev.classification.motion_level);
    const isMoving = /moving|active/.test(frame.classification.motion_level);
    if (wasMoving !== isMoving && cooldownPass('motion', 6000)) {
      addEvent(
        isMoving
          ? { kind: 'motion', title: 'تم رصد حركة', tone: 'active', detail: 'شدة الحركة: ' + pct(motionIntensity(frame)) }
          : { kind: 'motion', title: 'توقفت الحركة', tone: 'ok' },
      );
    }

    const status = breathingStatusOf(frame);
    const prevStatus = breathingStatusOf(prev);
    if (status && status !== prevStatus && cooldownPass('breathing', 25000)) {
      const bpm = Number(frame.vitalSigns.breathing_rate_bpm);
      addEvent({
        kind: 'breathing',
        title:
          status === 'normal'
            ? 'تنفس طبيعي'
            : status === 'fast'
              ? 'تنفس سريع'
              : 'تنفس بطيء',
        detail: `${bpm.toFixed(1)} نفس/دقيقة`,
        tone: status === 'normal' ? 'ok' : 'warning',
      });
    }

    const quality = signalQuality(frame);
    const prevQuality = signalQuality(prev);
    if (quality > 0 && prevQuality > 0) {
      const wasWeak = prevQuality < 0.35;
      const isWeak = quality < 0.35;
      if (wasWeak !== isWeak && cooldownPass('signal', 45000)) {
        addEvent({
          kind: 'signal',
          title: isWeak ? 'إشارة ضعيفة' : 'استعادة قوة الإشارة',
          detail: `جودة الإشارة: ${pct(quality)}`,
          tone: isWeak ? 'warning' : 'ok',
        });
      }
    }
  }

  // ── اشتقاقات ────────────────────────────────────────────────────────────
  function motionIntensity(frame) {
    if (!frame) return 0;
    const level = frame.classification.motion_level;
    const byLevel = /moving|active/.test(level)
      ? 0.78
      : level === 'present_still'
        ? 0.26
        : level === 'absent'
          ? 0.04
          : 0.12;
    const byPower = clamp01((Number(frame.features.motion_band_power) || 0) / 2.5);
    return Math.max(byLevel, byPower);
  }

  function signalQuality(frame) {
    if (!frame) return 0;
    const score = frame.signalQualityScore;
    if (score !== null && Number.isFinite(score) && score !== 0) {
      return clamp01(score > 1 ? score / 100 : score);
    }
    if (!frame.nodes.length) {
      const rssi = Number(frame.features.mean_rssi);
      return Number.isFinite(rssi) && rssi < 0 ? clamp01((rssi + 90) / 55) : 0;
    }
    const avg = frame.nodes.reduce((sum, n) => sum + (Number(n.rssi_dbm) || 0), 0) / frame.nodes.length;
    return clamp01((avg + 90) / 55);
  }

  function breathingStatusOf(frame) {
    const bpm = frame && frame.vitalSigns ? Number(frame.vitalSigns.breathing_rate_bpm) : NaN;
    if (!Number.isFinite(bpm) || bpm <= 0) return null;
    if (bpm < 12) return 'slow';
    if (bpm > 20) return 'fast';
    return 'normal';
  }

  const personCount = (frame) => {
    if (!frame) return 0;
    if (frame.estimatedPersons !== null && frame.estimatedPersons >= 0) return frame.estimatedPersons;
    return frame.persons.length;
  };

  const hasPresence = (frame) =>
    Boolean(frame) && (frame.classification.presence || personCount(frame) > 0);

  // ── العرض ───────────────────────────────────────────────────────────────
  function render() {
    const frame = state.frame;
    const target = `${state.settings.host}:${state.settings.port}`;
    els.chipTarget.textContent = target;
    els.monitorEndpoint.textContent = target;

    const live = state.status === 'connected' || state.status === 'demo';
    els.chipUptime.hidden = !live;
    els.chipRate.hidden = !live;
    if (live && state.connectedAt) {
      els.uptime.textContent = formatDuration(nowMs() - state.connectedAt);
    }
    els.rate.textContent = `${state.frameRate.toFixed(1)} Hz`;

    // بطاقات الملخص
    const stale = live && state.lastFrameAt && nowMs() - state.lastFrameAt > 8000;
    els.tileSystemValue.textContent = stale ? T.stale : (T[state.status] || T.disconnected);
    els.tileSystem.dataset.tone = stale
      ? 'warning'
      : state.status === 'connected' || state.status === 'demo'
        ? 'ok'
        : state.status === 'error'
          ? 'danger'
          : 'idle';
    els.tileSystemCaption.textContent = live && state.connectedAt
      ? `مدة الاتصال: ${formatDuration(nowMs() - state.connectedAt)}`
      : 'بانتظار أول حزمة بيانات';

    const nodes = frame ? frame.nodes.length : 0;
    els.tileNodesValue.textContent = String(nodes);
    els.tileNodesCaption.textContent = nodes ? `${nodes} عقدة نشطة في الشبكة المحلية` : 'لا توجد عقد متصلة';

    const presence = hasPresence(frame);
    const people = personCount(frame);
    els.tilePresenceValue.textContent = !frame
      ? '—'
      : presence
        ? people > 1
          ? `${people} أشخاص`
          : 'شخص مرصود'
        : 'لا يوجد أشخاص';
    els.tilePresence.dataset.tone = presence ? 'active' : 'idle';
    els.tilePresenceCaption.textContent = frame
      ? `شدة الحركة: ${pct(motionIntensity(frame))}`
      : 'بانتظار أول حزمة بيانات';

    const quality = signalQuality(frame);
    els.tileQualityValue.textContent = frame ? pct(quality) : '—';
    els.tileQualityCaption.textContent = frame ? `${rssiLabel(frame)}` : 'بانتظار أول حزمة بيانات';
    els.tileQualityBar.style.width = `${Math.round(quality * 100)}%`;
    els.tileQualityBar.parentElement.parentElement.dataset.tone =
      quality >= 0.6 ? 'ok' : quality >= 0.35 ? 'warning' : frame ? 'danger' : 'idle';

    // لوحة الرصد
    const breathing = state.breathingSmooth;
    const breathingStatus = breathingStatusOf(frame);
    const bpmValue = Number.isFinite(breathing) ? breathing : null;

    els.chipPersons.textContent = String(people);
    els.chipQuality.textContent = frame ? pct(quality) : '—';
    els.chipRssi.textContent = frame ? rssiLabel(frame) : '—';
    els.chipSource.textContent = frame ? frame.source : '—';

    // الرادار
    if (!frame) {
      els.radarCaption.dataset.tone = 'idle';
      els.radarCaptionValue.textContent = '—';
      els.radarCaptionTitle.textContent = 'لا توجد بيانات للرصد';
      els.radarCaptionNote.textContent = '';
    } else if (!presence) {
      els.radarCaption.dataset.tone = 'idle';
      els.radarCaptionValue.textContent = '0';
      els.radarCaptionTitle.textContent = 'المنطقة فارغة';
      els.radarCaptionNote.textContent = stale ? T.stale : '';
    } else {
      els.radarCaption.dataset.tone = stale ? 'warning' : 'ok';
      els.radarCaptionValue.textContent = String(Math.max(people, 1));
      els.radarCaptionTitle.textContent = 'تم رصد شخص في المنطقة';
      els.radarCaptionNote.textContent = people > 1 ? 'أشخاص داخل النطاق' : 'شخص داخل النطاق';
    }

    state.radarBlips = buildBlips(frame, presence);

    // العلامات الحيوية
    els.breathingValue.textContent = bpmValue === null ? '—' : oneDecimal(bpmValue);
    const statusLabel =
      breathingStatus === 'normal'
        ? 'تنفس طبيعي'
        : breathingStatus === 'fast'
          ? 'تنفس سريع'
          : breathingStatus === 'slow'
            ? 'تنفس بطيء'
            : 'غير متوفر';
    els.breathingPillText.textContent = statusLabel;
    els.breathingPill.dataset.tone =
      breathingStatus === 'normal' ? 'ok' : breathingStatus ? 'warning' : 'idle';
    els.breathingStatus.textContent = statusLabel;
    els.breathingStatus.style.color =
      breathingStatus === 'normal'
        ? 'var(--emerald)'
        : breathingStatus
          ? 'var(--warning)'
          : 'var(--text-3)';

    const gaugeColor =
      breathingStatus === 'normal'
        ? 'var(--emerald)'
        : breathingStatus === 'fast'
          ? 'var(--warning)'
          : breathingStatus === 'slow'
            ? 'var(--cyan)'
            : 'var(--idle)';
    els.gaugeValue.style.stroke = gaugeColor;
    const ratio = bpmValue === null ? 0 : clamp01((bpmValue - 6) / 24);
    els.gaugeValue.style.strokeDasharray = `${(ratio * GAUGE_CIRCUMFERENCE * GAUGE_ARC).toFixed(1)} ${GAUGE_CIRCUMFERENCE.toFixed(1)}`;

    const vitals = frame && frame.vitalSigns ? frame.vitalSigns : null;
    const confidence = vitals
      ? clamp01(
          [vitals.breathing_confidence, vitals.heartbeat_confidence, vitals.signal_quality]
            .filter((v) => Number.isFinite(Number(v)))
            .reduce((acc, v, _, arr) => acc + Number(v) / arr.length, 0),
        )
      : 0;
    els.confidence.textContent = vitals ? pct(confidence) : '—';
    els.heart.textContent =
      vitals && Number(vitals.heart_rate_bpm) > 0
        ? String(Math.round(Number(vitals.heart_rate_bpm)))
        : '—';

    renderSparkline();

    const motion = motionIntensity(frame);
    els.motionValue.textContent = pct(motion);
    els.motionBar.style.width = `${Math.round(motion * 100)}%`;
    const level = frame ? frame.classification.motion_level : 'unknown';
    els.motionState.textContent =
      level === 'present_still'
        ? 'ساكن'
        : /moving|active/.test(level)
          ? 'متحرك'
          : level === 'absent'
            ? 'غائب'
            : 'غير محدد';

    els.monitorFootnote.textContent = state.lastFrameAt
      ? `آخر تحديث: ${relativeTime(state.lastFrameAt)}`
      : 'آخر تحديث: —';
  }

  function rssiLabel(frame) {
    if (!frame || !frame.nodes.length) return '—';
    const avg = frame.nodes.reduce((sum, n) => sum + (Number(n.rssi_dbm) || 0), 0) / frame.nodes.length;
    return `${Math.round(avg)} dBm`;
  }

  function buildBlips(frame, presence) {
    if (!frame || !presence) return [];
    const blips = frame.persons.map((person, index) => {
      const position = Array.isArray(person.position) ? person.position : [];
      let nx = position.length >= 3 ? Number(position[0]) / 6 : 0;
      let ny = position.length >= 3 ? Number(position[2]) / 6 : 0;
      if (Math.abs(nx) < 0.01 && Math.abs(ny) < 0.01) {
        const angle = 2.399963 * ((Number(person.id) || index) + 1);
        const radius = 0.42 + 0.2 * (1 - clamp01(Number(person.confidence) || 0.5));
        nx = Math.cos(angle) * radius;
        ny = Math.sin(angle) * radius;
      }
      const length = Math.hypot(nx, ny);
      if (length > 0.9) {
        nx = (nx / length) * 0.9;
        ny = (ny / length) * 0.9;
      }
      return { dx: nx, dy: ny, strength: clamp01(Number(person.confidence) || 0.6) };
    });
    if (!blips.length) {
      blips.push({ dx: 0.16, dy: -0.22, strength: 0.6 });
    }
    return blips;
  }

  function renderSparkline() {
    const history = state.breathingHistory;
    if (history.length < 2) {
      els.breathingSparkLine.setAttribute('d', '');
      els.breathingSparkFill.setAttribute('d', '');
      return;
    }
    const width = 200;
    const height = 44;
    const lo = 6;
    const hi = 30;
    const points = history.map((value, index) => {
      const x = (index / (history.length - 1)) * width;
      const normalized = clamp01((value - lo) / (hi - lo));
      const y = height - 3 - normalized * (height - 6);
      return [x, y];
    });
    const line = points
      .map(([x, y], index) => `${index === 0 ? 'M' : 'L'}${x.toFixed(1)} ${y.toFixed(1)}`)
      .join(' ');
    els.breathingSparkLine.setAttribute('d', line);
    els.breathingSparkFill.setAttribute(
      'd',
      `${line} L${width} ${height} L0 ${height} Z`,
    );
  }

  // ── رسم الرادار ─────────────────────────────────────────────────────────
  const canvas = els.radarCanvas;
  const ctx = canvas.getContext('2d');
  let rotation = 0;
  let pulse = 0;

  function resizeCanvas() {
    const rect = canvas.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2.5);
    const size = Math.max(1, Math.round(rect.width * dpr));
    if (canvas.width !== size || canvas.height !== size) {
      canvas.width = size;
      canvas.height = size;
    }
  }

  function drawRadar() {
    resizeCanvas();
    const w = canvas.width;
    const h = canvas.height;
    const cx = w / 2;
    const cy = h / 2;
    const radius = Math.min(w, h) / 2 - 6;
    const frame = state.frame;
    const presence = hasPresence(frame);
    const active = Boolean(frame) && presence && !(state.lastFrameAt && nowMs() - state.lastFrameAt > 8000);
    const accent = active ? '#00f5a0' : '#00e5ff';

    ctx.clearRect(0, 0, w, h);

    // خلفية متدرّجة
    const bg = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius);
    bg.addColorStop(0, active ? 'rgba(0,245,160,0.14)' : 'rgba(0,229,255,0.08)');
    bg.addColorStop(1, 'rgba(5,7,13,0)');
    ctx.fillStyle = bg;
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.fill();

    // الحلقات
    ctx.strokeStyle = 'rgba(0,229,255,0.18)';
    ctx.lineWidth = Math.max(1, w / 400);
    for (let i = 1; i <= 4; i++) {
      ctx.beginPath();
      ctx.arc(cx, cy, (radius * i) / 4, 0, Math.PI * 2);
      ctx.stroke();
    }

    // خطوط التقاطع
    ctx.strokeStyle = 'rgba(0,229,255,0.1)';
    ctx.beginPath();
    ctx.moveTo(cx - radius, cy);
    ctx.lineTo(cx + radius, cy);
    ctx.moveTo(cx, cy - radius);
    ctx.lineTo(cx, cy + radius);
    ctx.stroke();

    // المسح الدوّار
    if (frame) {
      rotation += 0.012;
      const trailing = 0.95;
      if (typeof ctx.createConicGradient === 'function') {
        const grad = ctx.createConicGradient(rotation - trailing, cx, cy);
        grad.addColorStop(0, active ? 'rgba(0,245,160,0.30)' : 'rgba(0,229,255,0.22)');
        grad.addColorStop(0.16, 'rgba(0,229,255,0)');
        grad.addColorStop(1, 'rgba(0,229,255,0)');
        ctx.save();
        ctx.beginPath();
        ctx.arc(cx, cy, radius, 0, Math.PI * 2);
        ctx.clip();
        ctx.fillStyle = grad;
        ctx.fillRect(cx - radius, cy - radius, radius * 2, radius * 2);
        ctx.restore();
      }
      const lx = cx + Math.cos(rotation) * radius;
      const ly = cy + Math.sin(rotation) * radius;
      ctx.strokeStyle = active ? 'rgba(0,245,160,0.65)' : 'rgba(0,229,255,0.5)';
      ctx.lineWidth = Math.max(1.2, w / 300);
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(lx, ly);
      ctx.stroke();
    }

    // الهوائي
    ctx.fillStyle = accent;
    ctx.beginPath();
    ctx.arc(cx, cy, Math.max(2.6, w / 90), 0, Math.PI * 2);
    ctx.fill();

    // النقط
    pulse = (pulse + 0.014) % 1;
    for (const blip of state.radarBlips) {
      const x = cx + blip.dx * radius;
      const y = cy + blip.dy * radius;
      const core = (3.2 + blip.strength * 2.6) * (w / 320);
      const color = active ? '#00f5a0' : '#00e5ff';

      const glow = ctx.createRadialGradient(x, y, 0, x, y, core * 3.4);
      glow.addColorStop(0, active ? 'rgba(0,245,160,0.55)' : 'rgba(0,229,255,0.45)');
      glow.addColorStop(1, 'rgba(0,245,160,0)');
      ctx.fillStyle = glow;
      ctx.beginPath();
      ctx.arc(x, y, core * 3.4, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(x, y, core, 0, Math.PI * 2);
      ctx.fill();

      ctx.strokeStyle = active
        ? `rgba(0,245,160,${(1 - pulse) * 0.6})`
        : `rgba(0,229,255,${(1 - pulse) * 0.5})`;
      ctx.lineWidth = Math.max(1, w / 380);
      ctx.beginPath();
      ctx.arc(x, y, core + 6 + pulse * 16 * blip.strength, 0, Math.PI * 2);
      ctx.stroke();
    }

    // الحلقة الخارجية
    const quality = signalQuality(frame);
    ctx.strokeStyle = active
      ? `rgba(0,245,160,${0.25 + quality * 0.6})`
      : `rgba(0,229,255,${0.2 + quality * 0.5})`;
    ctx.lineWidth = Math.max(1.4, w / 220);
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.stroke();

    requestAnimationFrame(drawRadar);
  }

  // ── التنقل والأحداث ─────────────────────────────────────────────────────
  function showMonitor() {
    els.dashboard.classList.remove('is-active');
    els.monitor.classList.add('is-active');
    window.scrollTo({ top: 0, behavior: 'instant' in window ? 'instant' : 'auto' });
    render();
  }

  function showDashboard() {
    els.monitor.classList.remove('is-active');
    els.dashboard.classList.add('is-active');
    window.scrollTo({ top: 0, behavior: 'auto' });
  }

  els.connectBtn.addEventListener('click', () => {
    if (state.status === 'connected' || state.status === 'demo' || state.status === 'connecting') {
      disconnect();
    } else {
      connect();
    }
  });

  els.host.addEventListener('input', () => {
    els.formError.hidden = true;
    els.host.removeAttribute('aria-invalid');
  });
  els.port.addEventListener('input', () => {
    els.port.value = els.port.value.replace(/[^\d]/g, '').slice(0, 5);
    els.formError.hidden = true;
    els.port.removeAttribute('aria-invalid');
  });
  els.port.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') els.connectBtn.click();
  });
  els.host.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') els.connectBtn.click();
  });

  document.querySelectorAll('[data-transport]').forEach((button) => {
    button.addEventListener('click', () => {
      document
        .querySelectorAll('[data-transport]')
        .forEach((other) => other.classList.remove('is-selected'));
      button.classList.add('is-selected');
      const transport = button.dataset.transport;
      if (state.settings.transport !== transport) {
        state.settings.transport = transport;
        // منفذ UDP الافتراضي لعُقد ESP32 هو 5005.
        if (transport === 'udp' && els.port.value.trim() === '8765') els.port.value = '5005';
        if (transport === 'websocket' && els.port.value.trim() === '5005') els.port.value = '8765';
      }
    });
  });

  els.advancedToggle.addEventListener('click', () => {
    const expanded = els.advancedToggle.getAttribute('aria-expanded') === 'true';
    els.advancedToggle.setAttribute('aria-expanded', String(!expanded));
    els.advancedPanel.hidden = expanded;
  });

  els.openMonitor.addEventListener('click', showMonitor);
  els.back.addEventListener('click', showDashboard);
  els.clearEvents.addEventListener('click', () => {
    state.events = [];
    renderEvents();
  });

  // تحديث نسبي للأوقات وعدّاد المدة
  setInterval(() => {
    if (state.status === 'connected' || state.status === 'demo') {
      if (state.connectedAt) els.uptime.textContent = formatDuration(nowMs() - state.connectedAt);
      els.rate.textContent = `${state.frameRate.toFixed(1)} Hz`;
      if (state.lastFrameAt) {
        els.monitorFootnote.textContent = `آخر تحديث: ${relativeTime(state.lastFrameAt)}`;
      }
      if (state.frame) setStatus(state.status);
    }
    if (state.events.length) renderEvents();
  }, 1000);

  // ── التهيئة ─────────────────────────────────────────────────────────────
  els.host.value = state.settings.host;
  els.port.value = state.settings.port;
  els.secure.checked = state.settings.secure;
  setStatus('disconnected');
  renderEvents();
  render();
  requestAnimationFrame(drawRadar);

  // اتصال تلقائي عندما تُخدم المعاينة من بوابة المحاكاة.
  // على صفحات https يُستخدم wss أولًا (المتصفح يمنع ws غير المشفّر).
  if (location.protocol === 'http:' || location.protocol === 'https:') {
    setTimeout(() => {
      if (state.status === 'disconnected') connect({ auto: true });
    }, 350);
  } else {
    startDemo();
  }
})();
