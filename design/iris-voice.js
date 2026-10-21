(() => {
  if (customElements.get('iris-voice-orb')) return;
  const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  const DK = { idle: '#C9C3FF', connecting: '#5CC8FF', listening: '#FF8AD8', hearing: '#FF8AD8', thinking: '#9B7BFF', tool: '#FFB547', speaking: '#4FE3C1', muted: '#8A8898', error: '#FF6B6B', needs: '#FF8A5C', offline: '#8A8898' };
  const LT = { idle: '#4F3FCF', connecting: '#0B6FA3', listening: '#B0307F', hearing: '#B0307F', thinking: '#6544D9', tool: '#8A5000', speaking: '#00735E', muted: '#646372', error: '#C0312D', needs: '#B5410F', offline: '#646372' };
  const F = Math.PI * 2, cl = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
  const ALL = new Set(); let on = false, idx = 0, lastVis = -1e9;
  const kick = () => { if (on) return; on = true; requestAnimationFrame(tick); };
  const tick = n => {
    requestAnimationFrame(tick);
    const arr = [...ALL], t0 = performance.now(); if (!arr.length) return;
    if (n - lastVis > 250) { lastVis = n; const W = innerWidth, H = innerHeight; arr.forEach(o => { const r = o.getBoundingClientRect(); o.vis = !(W > 50 && H > 50) || (r.right > -50 && r.left < W + 50 && r.bottom > -50 && r.top < H + 50); }); }
    for (let k = 0; k < arr.length; k++) {
      const o = arr[(idx + k) % arr.length];
      if (!o.vis) { o.last = n; continue; }
      const st = o.getAttribute('still'), gap = st === null ? 33 : st === 'pulse' ? 100 : 1000;
      if (n - o.last < gap) continue;
      o.frame(n);
      if (performance.now() - t0 > 7) { idx = (idx + k + 1) % arr.length; return; }
    }
  };
  class IrisVoiceOrb extends HTMLElement {
    static get observedAttributes() { return ['size']; }
    constructor() {
      super();
      this.c = document.createElement('canvas'); this.c.style.display = 'block'; this.ctx = this.c.getContext('2d');
      this.t = Math.random() * 20; this.ph = Math.random(); this.rot = Math.random() * 6; this.L = 0; this.rgb = null; this.vis = true;
    }
    connectedCallback() {
      this.style.display = 'inline-block'; this.style.flex = 'none';
      if (!this.c.parentNode) this.appendChild(this.c);
      this.resize(); this.last = performance.now();
      this.last = 0; ALL.add(this); kick();
    }
    disconnectedCallback() { ALL.delete(this); this.io && this.io.disconnect(); }
    attributeChangedCallback() { this.resize(); }
    resize() {
      const s = +this.getAttribute('size') || 120, d = s < 60 ? 1 : Math.min(window.devicePixelRatio || 1, 1.5);
      this.s = s; this.d = d; this.c.width = s * d; this.c.height = s * d;
      this.c.style.width = this.c.style.height = s + 'px'; this.style.width = this.style.height = s + 'px';
    }
    frame(now) {
      const dt = Math.min(.05, (now - this.last) / 1000); this.last = now; this.t += dt;
      const g = n => this.getAttribute(n), still = g('still') !== null, pulseOn = g('still') === 'pulse';
      const ctx = this.ctx, s = this.s, d = this.d, cx = s / 2, cy = s / 2, t = still ? 0 : this.t;
      let mode = g('mode') || 'idle', lvl = g('level') !== null ? +g('level') : (mode === 'hearing' ? .6 : mode === 'speaking' ? .6 : 0);
      const hold = g('drive') === 'hold' || still;
      let snap = 0;
      if (mode === 'interrupted') {
        if (still) { mode = 'hearing'; lvl = .5; }
        else { const p = this.t % 3.6; if (p < 1.4) mode = 'speaking'; else { mode = 'hearing'; snap = Math.max(0, 1 - (p - 1.4) / .4); } lvl = Math.max(lvl, .7); }
      }
      const light = g('theme') === 'light', pal = light ? LT : DK, tc = hex(pal[mode] || pal.idle);
      if (!this.rgb) this.rgb = tc.slice();
      const k = Math.min(1, dt * 6); this.rgb = this.rgb.map((v, i) => v + (tc[i] - v) * k);
      // level
      let target = 0;
      if (mode === 'listening') target = hold ? 0 : .035 + .02 * Math.abs(Math.sin(t * 5.3));
      else if (mode === 'hearing' || mode === 'speaking') {
        if (hold) target = lvl;
        else {
          const gate = cl(Math.sin(t * 1.7 + this.ph * 6) * (lvl > .5 ? 1.6 : 2.4) + (lvl > .5 ? 1.1 : .55), 0, 1);
          target = lvl * gate * (.4 + .6 * Math.abs(Math.sin(t * 9.7) * Math.sin(t * 4.1 + 1)));
        }
      } else if (mode === 'needs') target = 0;
      this.L += (target - this.L) * (1 - Math.exp(-dt / (target > this.L ? .06 : .28)));
      const L = still ? target : this.L;
      if (!still) this.rot += dt;
      const rot = still ? 0 : this.rot;
      const [r, gg, b] = this.rgb.map(Math.round);
      let A = 1;
      if (still && pulseOn && ['listening', 'hearing', 'speaking', 'thinking', 'tool', 'needs', 'offline', 'connecting'].includes(mode)) A = .86 + .14 * Math.sin(this.t * F / 3.6);
      if (mode === 'muted' || mode === 'offline') A *= .7;
      const col = a => `rgba(${r},${gg},${b},${a * A})`;
      ctx.setTransform(d, 0, 0, d, 0, 0); ctx.clearRect(0, 0, s, s);
      const sq = 1 - .1 * snap; ctx.translate(cx, cy); ctx.scale(sq, sq); ctx.translate(-cx, -cy);
      let R = s * .27, W = s * (.034 + .02 * L);
      if (mode === 'idle') R *= 1 + .025 * Math.sin(t * F / 4);
      if (mode === 'listening') R *= 1 + .02 * Math.sin(t * F / 5);
      const live = mode === 'hearing' || mode === 'speaking';
      R *= 1 + (mode === 'hearing' ? .08 : mode === 'speaking' ? .07 : 0) * L;
      // glow
      const glowAmt = { idle: .5, connecting: .6, listening: .6, hearing: .7, speaking: .75, thinking: .9, tool: .75, needs: .85, error: .6, muted: 0, offline: 0 }[mode] ?? .5;
      const gl = (glowAmt + (live ? .5 * L : 0)), gr = ctx.createRadialGradient(cx, cy, 0, cx, cy, s * .5);
      gr.addColorStop(0, col(.32 * gl)); gr.addColorStop(.5, col(.1 * gl)); gr.addColorStop(1, col(0)); ctx.fillStyle = gr; ctx.fillRect(0, 0, s, s);
      // speaking bloom
      if (mode === 'speaking') {
        const br = R * (.5 + .45 * L), bg = ctx.createRadialGradient(cx, cy, 0, cx, cy, br);
        bg.addColorStop(0, col(.34 * (.4 + L))); bg.addColorStop(1, col(.06)); ctx.fillStyle = bg; ctx.beginPath(); ctx.arc(cx, cy, br, 0, F); ctx.fill();
      }
      // ripples
      if (live) {
        const q = cl((L - .06) * 4);
        if (still) {
          const n = L < .3 ? 0 : L < .62 ? 1 : 2;
          if (mode === 'hearing') for (let i = 0; i < n; i++) { ctx.setLineDash([s * .012, s * .02]); ctx.lineWidth = W * .6; ctx.strokeStyle = col(.5 - i * .15); ctx.beginPath(); ctx.arc(cx, cy, R * (1.2 + i * .2), 0, F); ctx.stroke(); }
          ctx.setLineDash([]);
        } else if (q > 0) {
          this.ph += dt * (mode === 'hearing' ? .6 + L * 1.2 : .5 + L * .7);
          for (let i = 0; i < 3; i++) {
            const f = (this.ph + i / 3) % 1;
            const rr = mode === 'hearing' ? R * (1.6 - .6 * f) : R * (1 + .6 * f);
            const al = (mode === 'hearing' ? Math.sin(Math.PI * f) : 1 - f) * .55 * q * Math.min(1, L * 2 + .3);
            ctx.lineWidth = W * .55; ctx.strokeStyle = col(al); ctx.beginPath(); ctx.arc(cx, cy, rr, 0, F); ctx.stroke();
          }
        }
      }
      if (snap > 0) { ctx.lineWidth = W * (1 + snap); ctx.strokeStyle = `rgba(255,255,255,${snap * .7})`; ctx.beginPath(); ctx.arc(cx, cy, R * (1.5 - .5 * (1 - snap)), 0, F); ctx.stroke(); }
      if (mode === 'interrupted' || (g('mode') === 'interrupted' && still)) { ctx.lineWidth = W * .7; ctx.strokeStyle = `rgba(${hex(pal.speaking).join(',')},.3)`; ctx.beginPath(); ctx.arc(cx, cy, R * 1.28, 0, F); ctx.stroke(); }
      if (g('mode') === 'interrupted' && still) { ctx.lineWidth = W * .7; ctx.strokeStyle = `rgba(${hex(pal.speaking).join(',')},.35)`; ctx.beginPath(); ctx.arc(cx, cy, R * 1.28, 0, F); ctx.stroke(); }
      ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      
      const arcs = (n, lenf, spin, tr) => {
        if (tr) { ctx.lineWidth = W; ctx.strokeStyle = col(tr); ctx.beginPath(); ctx.arc(cx, cy, R, 0, F); ctx.stroke(); }
        const slot = F / n; ctx.lineWidth = W * 1.15; ctx.strokeStyle = col(1);
        for (let i = 0; i < n; i++) { const a = -Math.PI / 2 + spin + i * slot; ctx.beginPath(); ctx.arc(cx, cy, R, a, a + slot * lenf); ctx.stroke(); }
      };
      let pulse = 0, sat = false;
      if (mode === 'thinking') { arcs(3, .7, rot * F * .4, .12); pulse = .2 * Math.sin(t * F * 1.6); }
      else if (mode === 'tool') { arcs(6, .62, rot * 1.3, .1); sat = true; pulse = .1 * Math.sin(t * F * 1.2); }
      else if (mode === 'connecting') { ctx.lineWidth = W; ctx.strokeStyle = col(.14); ctx.beginPath(); ctx.arc(cx, cy, R, 0, F); ctx.stroke(); ctx.lineWidth = W * 1.3; ctx.strokeStyle = col(1); const a = -Math.PI / 2 + rot * 5.2; ctx.beginPath(); ctx.arc(cx, cy, R, a, a + F * .3); ctx.stroke(); }
      else if (mode === 'needs') { arcs(2, .78, rot * .35, .1); pulse = .14 * Math.sin(t * F * .9); }
      else if (mode === 'offline') { arcs(12, .55, rot * .1, 0); pulse = .08 * Math.sin(t * F * .5); }
      else if (mode === 'error') {
        const sh = still ? 0 : Math.max(0, 1 - (this.t % 4) / .3); ctx.translate(Math.sin(this.t * 55) * sh * sh * s * .04, 0);
        ctx.lineWidth = W; ctx.strokeStyle = col(.1); ctx.beginPath(); ctx.arc(cx, cy, R, 0, F); ctx.stroke();
        ctx.lineWidth = W * 1.2; ctx.strokeStyle = col(1); ctx.beginPath(); ctx.arc(cx, cy, R, -Math.PI / 2 + F * .08, -Math.PI / 2 + F * .92); ctx.stroke();
      } else {
        // closed ring with edge deformation
        const N = 110; ctx.lineWidth = W * (mode === 'muted' ? .8 : 1.1); ctx.strokeStyle = col(mode === 'muted' ? .8 : 1); ctx.beginPath();
        for (let i = 0; i <= N; i++) {
          const a = i / N * F; let df = 0;
          if (still) df = 0;
          else if (mode === 'hearing') df = L * (.12 * Math.sin(5 * a + rot * 1.7 + t * 2.3) * Math.sin(3 * a - t * 1.9) + .055 * Math.sin(9 * a - t * 4.1 + this.ph * 6) + .02 * Math.sin(2 * a + t * 3));
          else if (mode === 'listening') df = .012 * Math.sin(4 * a + t * 1.6) + (hold ? 0 : this.L * .3 * Math.sin(7 * a + t * 5));
          else if (mode === 'speaking') df = .012 * L * Math.sin(3 * a + t * 2);
          const rr = R * (1 + df), x = cx + Math.cos(a) * rr, y = cy + Math.sin(a) * rr;
          i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
        }
        ctx.stroke();
        if (mode === 'muted') { ctx.lineWidth = W * .9; ctx.beginPath(); ctx.moveTo(cx - R * .72, cy - R * .72); ctx.lineTo(cx + R * .72, cy + R * .72); ctx.stroke(); }
      }
      if (sat) { const a = still ? -.8 : rot * 1.9, sr = R + W * 2.4; ctx.fillStyle = col(1); ctx.beginPath(); ctx.arc(cx + Math.cos(a) * sr, cy + Math.sin(a) * sr, W * .75, 0, F); ctx.fill(); }
      // core
      const dm = { idle: .12 + .006 * Math.sin(t * F / 4), listening: .125, hearing: .125 + .045 * L, speaking: .13 + .07 * L, thinking: .115, tool: .125, connecting: .1, needs: .125, muted: .1, error: .12, offline: .1 }[mode] ?? .12;
      const D = s * dm * (1 + pulse + (mode === 'listening' ? .04 * Math.sin(t * F * 1.1) : 0));
      const dg = ctx.createRadialGradient(cx - D * .3, cy - D * .35, D * .1, cx, cy, D);
      const dim = mode === 'muted' || mode === 'offline' ? .6 : 1;
      dg.addColorStop(0, `rgba(255,255,255,${.95 * dim * A})`); dg.addColorStop(.35, col(1)); dg.addColorStop(1, col(.85));
      ctx.fillStyle = dg; ctx.beginPath(); ctx.arc(cx, cy, D, 0, F); ctx.fill();
    }
  }
  customElements.define('iris-voice-orb', IrisVoiceOrb);
})();
