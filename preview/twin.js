/* معاينة الويب لـ«التوأم الراديوي» — نفس منطق التطبيق مبسّطًا على Canvas.
   لا تعتمد على أي مكتبة، وتعمل بمفردها لعرض الشكل النهائي في المتصفح. */
(() => {
  'use strict';
  if (typeof document === 'undefined') return;

  const TAU = Math.PI * 2;
  const clamp01 = (v) => Math.min(1, Math.max(0, v));
  const lerp = (a, b, t) => a + (b - a) * t;

  // ── نموذج الشكل البارامتري (SMPL مصغّر) ────────────────────────────────
  const MATERIALS = {
    fabric: { name: 'قماش كتان', color: '#3f5f76', top: '#4f7692', side: '#2c465c' },
    oak: { name: 'خشب بلوط', color: '#9a6a3c', top: '#b07f4c', side: '#6f4a28' },
    walnut: { name: 'خشب جوز', color: '#5b3a25', top: '#6f4a30', side: '#40281a' },
    stone: { name: 'حجر طبيعي', color: '#6e7378', top: '#82878c', side: '#4f5357' },
    marble: { name: 'رخام', color: '#c2c9ce', top: '#d6dde1', side: '#96a0a6' },
    ceramic: { name: 'سيراميك', color: '#8fa9b4', top: '#a5bcc6', side: '#6c8794' },
  };

  const BODY_PRESET = {
    height: 1.76,
    shoulder: 0.44,
    chest: 1.0,
    waist: 0.84,
    hip: 0.97,
    arm: 0.63,
    leg: 0.83,
    muscle: 0.55,
  };

  function measurements(shape) {
    return [
      ['الطول', `${Math.round(shape.height * 100)} سم`],
      ['عرض الكتفين', `${Math.round(shape.shoulder * 100)} سم`],
      ['محيط الصدر', `${Math.round(shape.chest * 100)} سم`],
      ['محيط الخصر', `${Math.round(shape.waist * 100)} سم`],
      ['محيط الحوض', `${Math.round(shape.hip * 100)} سم`],
      ['الكتلة التقديرية', `${Math.round(estimateMass(shape))} كجم`],
    ];
  }

  function estimateMass(shape) {
    return 55 + (shape.height - 1.55) * 62 + (shape.chest - 0.92) * 34 + shape.muscle * 7;
  }

  function betaLabel(shape) {
    const ref = { height: 1.72, shoulder: 0.42, chest: 0.98, waist: 0.82, hip: 0.96 };
    const scale = { height: 0.09, shoulder: 0.03, chest: 0.06, waist: 0.06, hip: 0.05 };
    return ['β', ...['height', 'shoulder', 'chest', 'waist', 'hip'].map((key) => {
      const value = (shape[key] - ref[key]) / scale[key];
      return (value >= 0 ? '+' : '−') + Math.abs(value).toFixed(1);
    })].join(' ');
  }

  // ── هيكل ثلاثي الأبعاد مبسّط + دوراة + إسقاط ───────────────────────────
  function jointsFor(shape, phase) {
    const h = shape.height;
    const walking = Math.sin(phase) * 0.06;
    const shoulderY = h * 0.82;
    const hipY = h * 0.52;
    const halfShoulder = shape.shoulder / 2;
    const halfHip = shape.hip / (TAU) * 0.44;
    const swing = Math.sin(phase) * shape.leg * 0.16;
    const armSwing = Math.sin(phase + Math.PI) * shape.arm * 0.14;

    const p = (x, y, z) => ({ x, y, z });
    return {
      pelvis: p(0, hipY + 0.03, 0),
      neck: p(0, shoulderY + 0.07, 0),
      nose: p(0, h * 0.93, 0.03),
      leftShoulder: p(halfShoulder, shoulderY, 0),
      rightShoulder: p(-halfShoulder, shoulderY, 0),
      leftElbow: p(halfShoulder + 0.04, shoulderY - shape.arm * 0.3, armSwing),
      rightElbow: p(-halfShoulder - 0.04, shoulderY - shape.arm * 0.3, -armSwing),
      leftWrist: p(halfShoulder + 0.05, shoulderY - shape.arm * 0.58, armSwing * 1.6),
      rightWrist: p(-halfShoulder - 0.05, shoulderY - shape.arm * 0.58, -armSwing * 1.6),
      leftHip: p(halfHip, hipY, 0),
      rightHip: p(-halfHip, hipY, 0),
      leftKnee: p(halfHip + 0.01, hipY - shape.leg * 0.46, swing),
      rightKnee: p(-halfHip - 0.01, hipY - shape.leg * 0.46, -swing),
      leftAnkle: p(halfHip + 0.02, h * 0.045, swing * 1.8 + walking),
      rightAnkle: p(-halfHip - 0.02, h * 0.045, -swing * 1.8 + walking),
    };
  }

  function project(point, yaw, scale, originX, originY) {
    const cos = Math.cos(yaw);
    const sin = Math.sin(yaw);
    const x = point.x * cos - point.z * sin;
    const z = point.x * sin + point.z * cos;
    const perspective = 1 / (1 + (z + 1.1) * 0.13);
    return {
      x: originX + x * scale * perspective,
      y: originY - point.y * scale * perspective,
      z,
    };
  }

  function capsule(ctx, a, b, radius, color, shade) {
    ctx.strokeStyle = shadeColor(color, shade);
    ctx.lineWidth = Math.max(2, radius * 2);
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.stroke();
  }

  function shadeColor(hex, factor) {
    const value = parseInt(hex.slice(1), 16);
    const r = Math.min(255, Math.round(((value >> 16) & 255) * factor));
    const g = Math.min(255, Math.round(((value >> 8) & 255) * factor));
    const b = Math.min(255, Math.round((value & 255) * factor));
    return `rgb(${r},${g},${b})`;
  }

  // ── قماش Verlet مبسّط ──────────────────────────────────────────────────
  const CLOTH_COLS = 7;
  const CLOTH_ROWS = 5;
  const cloth = { points: [], previous: [], ready: false };

  function resetCloth(joints) {
    cloth.points = [];
    cloth.previous = [];
    for (let r = 0; r < CLOTH_ROWS; r++) {
      for (let c = 0; c < CLOTH_COLS; c++) {
        const t = c / (CLOTH_COLS - 1);
        const point = {
          x: lerp(joints.rightShoulder.x, joints.leftShoulder.x, t),
          y: joints.leftShoulder.y - r * 0.055,
          z: joints.leftShoulder.z + 0.05 + r * 0.012,
        };
        cloth.points.push(point);
        cloth.previous.push({ ...point });
      }
    }
    cloth.ready = true;
  }

  function stepCloth(motion) {
    if (!cloth.ready) return;
    const gravity = 0.00032;
    for (let i = 0; i < cloth.points.length; i++) {
      if (Math.floor(i / CLOTH_COLS) === 0) continue; // الصف العلوي مرتسٍ
      const point = cloth.points[i];
      const prev = cloth.previous[i];
      const vx = (point.x - prev.x) * 0.96;
      const vy = (point.y - prev.y) * 0.96;
      const vz = (point.z - prev.z) * 0.96;
      prev.x = point.x;
      prev.y = point.y;
      prev.z = point.z;
      point.x += vx + motion * 0.0004;
      point.y += vy - gravity;
      point.z += vz + motion * 0.0005;
      point.y = Math.max(0.3, point.y);
    }
  }

  // ── الرسم ─────────────────────────────────────────────────────────────
  function drawBackdrop(ctx, w, h) {
    const gradient = ctx.createLinearGradient(0, 0, 0, h);
    gradient.addColorStop(0, '#0a1420');
    gradient.addColorStop(1, '#070d16');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = 'rgba(34,211,238,0.10)';
    ctx.lineWidth = 1;
    for (let i = 1; i <= 4; i++) {
      const y = h * (0.62 + i * 0.075);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }
  }

  function drawBody(ctx, w, h, shape, phase, yaw) {
    drawBackdrop(ctx, w, h);
    const joints = jointsFor(shape, phase);
    const bodyHeight = shape.height;
    const scale = (h * 0.78) / bodyHeight;
    const originX = w / 2;
    const originY = h * 0.94;
    const p = (point) => project(point, yaw, scale, originX, originY);

    const pelvis = p(joints.pelvis);
    const neck = p(joints.neck);
    const lS = p(joints.leftShoulder);
    const rS = p(joints.rightShoulder);
    const lH = p(joints.leftHip);
    const rH = p(joints.rightHip);
    const lE = p(joints.leftElbow);
    const rE = p(joints.rightElbow);
    const lW = p(joints.leftWrist);
    const rW = p(joints.rightWrist);
    const lK = p(joints.leftKnee);
    const rK = p(joints.rightKnee);
    const lA = p(joints.leftAnkle);
    const rA = p(joints.rightAnkle);

    const shirt = '#1e8fa8';
    const skin = '#e3b08b';
    const pants = '#20313c';

    // الأطراف البعيدة أولًا (خلف الجسم).
    const farLeg = lK.z < rK.z;
    capsule(ctx, farLeg ? lH : rH, farLeg ? lK : rK, shape.leg * 0.05, pants, 0.72);
    capsule(ctx, farLeg ? lK : rK, farLeg ? lA : rA, shape.leg * 0.04, pants, 0.66);
    const farArm = lE.z < rE.z;
    capsule(ctx, farArm ? lS : rS, farArm ? lE : rE, shape.arm * 0.045, shirt, 0.78);
    capsule(ctx, farArm ? lE : rE, farArm ? lW : rW, shape.arm * 0.036, skin, 0.72);

    // الجذع.
    capsule(ctx, pelvis, neck, shape.chest * 0.052, shirt, 1.0);
    capsule(ctx, { x: (lS.x + rS.x) / 2, y: (lS.y + rS.y) / 2, z: lS.z }, pelvis,
      shape.waist * 0.05, shirt, 0.94);

    // الأطراف القريبة.
    capsule(ctx, farLeg ? rH : lH, farLeg ? rK : lK, shape.leg * 0.052, pants, 0.92);
    capsule(ctx, farLeg ? rK : lK, farLeg ? rA : lA, shape.leg * 0.042, pants, 0.86);
    capsule(ctx, farArm ? rS : lS, farArm ? rE : lE, shape.arm * 0.048, shirt, 1.02);
    capsule(ctx, farArm ? rE : lE, farArm ? rW : lW, shape.arm * 0.038, skin, 0.94);

    // الرأس.
    const head = p({ x: 0, y: shape.height * 0.9, z: 0 });
    const headRadius = shape.height * 0.075 * scale;
    const headGradient = ctx.createRadialGradient(
      head.x - headRadius * 0.3, head.y - headRadius * 0.3, headRadius * 0.2,
      head.x, head.y, headRadius,
    );
    headGradient.addColorStop(0, '#f0c7a4');
    headGradient.addColorStop(1, '#b9865f');
    ctx.fillStyle = headGradient;
    ctx.beginPath();
    ctx.arc(head.x, head.y, headRadius, 0, TAU);
    ctx.fill();

    // القماش.
    if (!cloth.ready) resetCloth(joints);
    stepCloth(0.6 + Math.sin(phase * 2) * 0.3);
    ctx.fillStyle = 'rgba(47,126,147,0.55)';
    ctx.strokeStyle = 'rgba(34,211,238,0.45)';
    ctx.lineWidth = 0.8;
    const projected = cloth.points.map((point) => p(point));
    for (let r = 0; r < CLOTH_ROWS - 1; r++) {
      for (let c = 0; c < CLOTH_COLS - 1; c++) {
        const a = projected[r * CLOTH_COLS + c];
        const b = projected[r * CLOTH_COLS + c + 1];
        const d = projected[(r + 1) * CLOTH_COLS + c + 1];
        const e = projected[(r + 1) * CLOTH_COLS + c];
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.lineTo(d.x, d.y);
        ctx.lineTo(e.x, e.y);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
      }
    }

    // مفاصل (طبقة الهيكل).
    ctx.fillStyle = 'rgba(25,227,168,0.85)';
    [lS, rS, lH, rH, lE, rE, lK, rK, lA, rA].forEach((joint) => {
      ctx.beginPath();
      ctx.arc(joint.x, joint.y, 2.2, 0, TAU);
      ctx.fill();
    });

    // مسطرة الطول.
    ctx.strokeStyle = 'rgba(34,211,238,0.35)';
    ctx.beginPath();
    ctx.moveTo(w - 12, h * 0.13);
    ctx.lineTo(w - 12, h * 0.93);
    ctx.stroke();
    ctx.fillStyle = 'rgba(148,163,184,0.9)';
    ctx.font = '11px system-ui, sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText(`${Math.round(shape.height * 100)} سم`, w - 18, h * 0.13 - 6);
    ctx.textAlign = 'right';
    ctx.fillStyle = '#22d3ee';
    ctx.font = 'bold 12px system-ui, sans-serif';
    ctx.fillText(betaLabel(shape), 12, 20);
  }

  // ── خريطة الغرفة (isometric) ───────────────────────────────────────────
  const ROOM = {
    cell: 0.25,
    cols: 24,
    rows: 24,
    objects: [
      { kind: 'كنبة', material: 'fabric', x: 3, z: 4, w: 2.6, d: 1.0, h: 0.85 },
      { kind: 'طاولة', material: 'oak', x: 5.6, z: 4.4, w: 0.9, d: 0.9, h: 0.76 },
      { kind: 'خزانة', material: 'walnut', x: 1.2, z: 1.0, w: 0.6, d: 1.1, h: 1.85 },
      { kind: 'جدار', material: 'stone', x: 0.2, z: 3.0, w: 0.3, d: 5.6, h: 2.55 },
      { kind: 'نبات', material: 'ceramic', x: 5.9, z: 1.2, w: 0.4, d: 0.4, h: 1.05 },
    ],
  };

  function drawRoom(ctx, w, h, phase) {
    drawBackdrop(ctx, w, h);
    const scale = (h * 0.6) / 6.2;
    const kx = Math.cos(Math.PI / 6) * scale;
    const ky = Math.sin(Math.PI / 6) * scale;
    const ox = w / 2;
    const oy = h * 0.34;
    const iso = (x, y, z) => ({ x: ox + (x - z) * kx, y: oy + (x + z) * ky - y * scale });

    // أرضية.
    const a = iso(0, 0, 0);
    const b = iso(6, 0, 0);
    const c = iso(6, 0, 6);
    const d = iso(0, 0, 6);
    ctx.fillStyle = '#0c1724';
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.lineTo(c.x, c.y);
    ctx.lineTo(d.x, d.y);
    ctx.closePath();
    ctx.fill();

    ctx.strokeStyle = 'rgba(34,211,238,0.08)';
    for (let i = 1; i < 6; i++) {
      const t = (i / 6) * 6;
      const p1 = iso(t, 0, 0);
      const p2 = iso(t, 0, 6);
      const p3 = iso(0, 0, t);
      const p4 = iso(6, 0, t);
      ctx.beginPath();
      ctx.moveTo(p1.x, p1.y);
      ctx.lineTo(p2.x, p2.y);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(p3.x, p3.y);
      ctx.lineTo(p4.x, p4.y);
      ctx.stroke();
    }

    ROOM.objects.forEach((object) => {
      const material = MATERIALS[object.material] || MATERIALS.stone;
      const x0 = object.x;
      const z0 = object.z;
      const x1 = object.x + object.w;
      const z1 = object.z + object.d;
      const top = object.h;

      const topFace = [iso(x0, top, z0), iso(x1, top, z0), iso(x1, top, z1), iso(x0, top, z1)];
      const leftFace = [iso(x0, 0, z1), iso(x0, top, z1), iso(x0, top, z0), iso(x0, 0, z0)];
      const rightFace = [iso(x0, 0, z0), iso(x0, top, z0), iso(x1, top, z0), iso(x1, 0, z0)];

      const fill = (points, color) => {
        ctx.fillStyle = color;
        ctx.beginPath();
        points.forEach((point, index) => {
          if (index === 0) ctx.moveTo(point.x, point.y);
          else ctx.lineTo(point.x, point.y);
        });
        ctx.closePath();
        ctx.fill();
      };
      fill(leftFace, material.side);
      fill(rightFace, material.color);
      fill(topFace, material.top);

      const anchor = iso(object.x + object.w / 2, top + 0.12, object.z + object.d / 2);
      ctx.fillStyle = 'rgba(11,22,34,0.9)';
      ctx.font = '10px system-ui, sans-serif';
      const text = `${object.kind} — ${material.name}`;
      const width = ctx.measureText(text).width + 12;
      ctx.beginPath();
      ctx.roundRect
        ? ctx.roundRect(anchor.x - width / 2, anchor.y - 9, width, 16, 6)
        : ctx.rect(anchor.x - width / 2, anchor.y - 9, width, 16);
      ctx.fill();
      ctx.fillStyle = '#e2e8f0';
      ctx.textAlign = 'center';
      ctx.fillText(text, anchor.x, anchor.y + 2);
    });

    // نبضة شخص متحرك.
    const walkX = 3 + Math.cos(phase * 0.8) * 1.2;
    const walkZ = 3 + Math.sin(phase * 0.8) * 1.2;
    const person = iso(walkX, 0.35, walkZ);
    ctx.fillStyle = 'rgba(25,227,168,0.85)';
    ctx.beginPath();
    ctx.arc(person.x, person.y, 5, 0, TAU);
    ctx.fill();
    ctx.fillStyle = 'rgba(148,163,184,0.85)';
    ctx.font = '10px system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('موقع الشخص', person.x, person.y - 10);
  }

  function fitCanvas(canvas) {
    const ratio = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    const width = Math.max(240, rect.width);
    const height = Math.max(180, rect.height);
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    const ctx = canvas.getContext('2d');
    if (!ctx) return null;
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    return { ctx, width, height };
  }

  function start() {
    const bodyCanvas = document.getElementById('twin-canvas');
    const roomCanvas = document.getElementById('room-canvas');
    const list = document.getElementById('twin-measurements');
    const shape = { ...BODY_PRESET };
    let phase = 0;

    if (list) {
      list.innerHTML = measurements(shape)
        .map(
          ([label, value]) =>
            `<li><span>${label}</span><strong>${value}</strong></li>`,
        )
        .join('');
    }

    const frame = () => {
      phase += 0.02;
      if (bodyCanvas) {
        const surface = fitCanvas(bodyCanvas);
        if (surface) {
          drawBody(surface.ctx, surface.width, surface.height, shape, phase, -0.42);
        }
      }
      if (roomCanvas) {
        const surface = fitCanvas(roomCanvas);
        if (surface) {
          drawRoom(surface.ctx, surface.width, surface.height, phase);
        }
      }
    };

    frame();
    window.setInterval(frame, 60);
    window.RuViewTwin = { drawBody, drawRoom, measurements, shape };
  }

  // ── بطاقة الاتصال التلقائي (عرض حالة ثابتة للمعاينة) ──────────────────
  function paintAutoConnect() {
    const status = document.getElementById('auto-net-status');
    const candidates = document.getElementById('auto-candidates');
    const label = document.getElementById('auto-net-label');
    if (label) label.textContent = '192.168.1.42 · بوابة 192.168.1.1';
    if (status) status.textContent = 'متصل تلقائيًا';
    if (candidates) {
      const rows = [
        ['192.168.1.1:8080', 'بوابة الشبكة', '18ms'],
        ['192.168.1.24:8765', 'خادم RuView', '7ms'],
      ];
      candidates.innerHTML = rows
        .map(
          ([host, source, latency]) =>
            `<li><span class="dot"></span><code>${host}</code>` +
            `<em>${source}</em><small>${latency}</small></li>`,
        )
        .join('');
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      paintAutoConnect();
      start();
    });
  } else {
    paintAutoConnect();
    start();
  }
})();
