(() => {
  if (customElements.get('iris-orb')) return;
  const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  // col, dot, pulse, pf(Hz), ring, w, arc, seg, spin, wob, glow, sat, track, alpha
  const S = {
    idle:      { col: '#C9C3FF', dot: .15, pulse: .05, pf: .5, ring: .36, w: .032, arc: 1,   seg: 0, spin: .25, wob: 0,   glow: .55, sat: 0, track: 0,   alpha: 1 },
    rest:      { col: '#8E89AE', dot: .13, pulse: 0,   pf: .5, ring: .35, w: .03,  arc: 1,   seg: 0, spin: 0,   wob: 0,   glow: 0,   sat: 0, track: 0,   alpha: .75 },
    thinking:  { col: '#9B7BFF', dot: .13, pulse: .2,  pf: 1.6, ring: .38, w: .045, arc: .72, seg: 3, spin: 2.4, wob: 0,   glow: .95, sat: 0, track: .12, alpha: 1 },
    loading:   { col: '#5CC8FF', dot: .1,  pulse: .08, pf: 1,  ring: .36, w: .05,  arc: .3,  seg: 0, spin: 5.2, wob: 0,   glow: .7,  sat: 0, track: .14, alpha: 1 },
    tool:      { col: '#FFB547', dot: .14, pulse: .1,  pf: 1.2, ring: .38, w: .04,  arc: .62, seg: 6, spin: 1.3, wob: 0,   glow: .75, sat: 1, track: .1,  alpha: 1 },
    streaming: { col: '#4FE3C1', dot: .16, pulse: .08, pf: 2.4, ring: .37, w: .04,  arc: 1,   seg: 0, spin: .7,  wob: .07, glow: .9,  sat: 0, track: 0,   alpha: 1 },
    listening: { col: '#FF8AD8', dot: .15, pulse: .12, pf: 1.1, ring: .37, w: .038, arc: 1,   seg: 0, spin: .5,  wob: .11, glow: .9,  sat: 0, track: 0,   alpha: 1 },
    success:   { col: '#6EE787', dot: .17, pulse: .03, pf: .6, ring: .38, w: .045, arc: 1,   seg: 0, spin: 0,   wob: 0,   glow: 1,   sat: 0, track: 0,   alpha: 1 },
    failed:    { col: '#FF6B6B', dot: .15, pulse: .04, pf: .8, ring: .37, w: .042, arc: .84, seg: 0, spin: 0,   wob: 0,   glow: .6,  sat: 0, track: .1,  alpha: 1 },
    needs:     { col: '#FF8A5C', dot: .15, pulse: .14, pf: .9, ring: .37, w: .04, arc: 1, seg: 2, spin: .35, wob: 0, glow: .85, sat: 0, track: .1, alpha: 1 },
    offline:   { col: '#6B6A78', dot: .11, pulse: 0,   pf: .5, ring: .35, w: .026, arc: 1,   seg: 12, spin: .1, wob: 0,   glow: 0,   sat: 0, track: 0,   alpha: .6 }
  };
  const keys = ['dot', 'pulse', 'pf', 'ring', 'w', 'arc', 'seg', 'spin', 'wob', 'glow', 'sat', 'track', 'alpha'];
  const L = { idle: '#4F3FCF', rest: '#625F7C', thinking: '#6544D9', loading: '#0B6FA3', tool: '#8A5000', streaming: '#00735E', listening: '#B0307F', success: '#1D7A34', failed: '#C0312D', offline: '#646372', needs: '#B5410F' };
  const tgt = (s, light) => { const p = S[s] || S.idle; return { ...p, rgb: hex(light && L[s] ? L[s] : p.col) }; };

  class IrisOrb extends HTMLElement {
    static get observedAttributes() { return ['state', 'size', 'glow']; }
    constructor() {
      super();
      this.c = document.createElement('canvas');
      this.c.style.display = 'block';
      this.ctx = this.c.getContext('2d');
      this.cur = null; this.rot = Math.random() * 6; this.shake = 0; this.burst = 0; this.t = Math.random() * 10;
    }
    connectedCallback() {
      this.style.display = 'inline-block'; this.style.flex = 'none';
      if (!this.c.parentNode) this.appendChild(this.c);
      this.resize();
      if (!this.cur) this.cur = { ...tgt(this.getAttribute('state')), rgb: hex((S[this.getAttribute('state')] || S.idle).col) };
      this.last = performance.now(); this.run = true;
      const loop = now => { if (!this.run) return; this.frame(now); this.raf = requestAnimationFrame(loop); };
      this.raf = requestAnimationFrame(loop);
    }
    disconnectedCallback() { this.run = false; cancelAnimationFrame(this.raf); }
    attributeChangedCallback(n, o, v) {
      if (n === 'size') this.resize();
      if (n === 'state' && o !== v) { if (v === 'failed') this.shake = 1; if (v === 'success') this.burst = 1; }
    }
    resize() {
      const s = +this.getAttribute('size') || 48, d = Math.min(window.devicePixelRatio || 1, 3);
      this.s = s; this.d = d; this.c.width = s * d; this.c.height = s * d;
      this.c.style.width = this.c.style.height = s + 'px'; this.style.width = this.style.height = s + 'px';
    }
    frame(now) {
      const dt = Math.min(.05, (now - this.last) / 1000); this.last = now; this.t += dt;
      const T = tgt(this.getAttribute('state'), this.getAttribute('theme') === 'light'), C = this.cur, k = Math.min(1, dt * 5);
      keys.forEach(key => C[key] += (T[key] - C[key]) * k);
      C.rgb = C.rgb.map((v, i) => v + (T.rgb[i] - v) * k);
      C.seg = T.seg; // discrete
      const sa = this.getAttribute('still');
      const still = (sa !== null && sa !== 'false') || document.documentElement.hasAttribute('data-iris-still');
      if (still) { C.pulse = 0; C.wob = 0; C.spin = 0; this.shake = 0; this.burst = 0; }
      this.rot += C.spin * dt;
      this.shake = Math.max(0, this.shake - dt * 1.6); this.burst = Math.max(0, this.burst - dt * 1.1);
      const glowOn = this.getAttribute('glow') !== 'off';
      const { ctx, s, d, t } = this, cx = s / 2, cy = s / 2;
      const [r, g, b] = C.rgb.map(Math.round), col = a => `rgba(${r},${g},${b},${a * C.alpha})`;
      ctx.setTransform(d, 0, 0, d, 0, 0); ctx.clearRect(0, 0, s, s);
      const ox = Math.sin(t * 55) * this.shake * this.shake * s * .045;
      ctx.translate(ox, 0);
      if (glowOn && C.glow > .01) {
        const gr = ctx.createRadialGradient(cx, cy, 0, cx, cy, s * .5);
        gr.addColorStop(0, col(.32 * C.glow)); gr.addColorStop(.45, col(.12 * C.glow)); gr.addColorStop(1, col(0));
        ctx.fillStyle = gr; ctx.fillRect(0, 0, s, s);
      }
      const R = s * C.ring, W = Math.max(1, s * C.w);
      const amp = still ? 0 : C.wob + (this.getAttribute('state') === 'listening' ? (Math.sin(t * 7.3) * .5 + Math.sin(t * 3.1) * .5) * .03 : 0);
      const rad = a => R * (1 + amp * Math.sin(a * 5 + t * 3.2) * Math.sin(a * 3 - t * 2.1));
      ctx.lineCap = 'round'; ctx.lineWidth = W;
      if (C.track > .01) { ctx.strokeStyle = col(C.track); ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.stroke(); }
      const stroke = (a0, len, fade) => {
        const n = Math.max(6, Math.ceil(len * 40));
        for (let i = 0; i < n; i++) {
          const f0 = i / n, f1 = (i + 1) / n, aA = a0 + len * f0, aB = a0 + len * f1;
          ctx.strokeStyle = col(fade ? .12 + .88 * Math.pow(f1, 1.6) : 1);
          ctx.beginPath();
          ctx.moveTo(cx + Math.cos(aA) * rad(aA), cy + Math.sin(aA) * rad(aA));
          const am = (aA + aB) / 2; ctx.lineTo(cx + Math.cos(am) * rad(am), cy + Math.sin(am) * rad(am));
          ctx.lineTo(cx + Math.cos(aB) * rad(aB), cy + Math.sin(aB) * rad(aB));
          ctx.stroke();
        }
      };
      if (glowOn) { ctx.shadowColor = col(.8 * C.glow); ctx.shadowBlur = s * .08 * C.glow; }
      const full = Math.PI * 2, base = this.rot - Math.PI / 2;
      if (C.seg >= 1) {
        const n = Math.round(C.seg), slot = full / n, len = slot * Math.min(.92, C.arc);
        for (let i = 0; i < n; i++) stroke(base + i * slot, len, false);
      } else if (C.arc > .985) {
        stroke(base, full, false);
      } else {
        stroke(this.getAttribute('state') === 'failed' ? -Math.PI / 2 + full * (1 - C.arc) / 2 + Math.PI : base, full * C.arc, this.getAttribute('state') !== 'failed');
      }
      if (C.sat > .02 && !still) {
        const a = this.rot * 1.9, sr = R + W * 2.2;
        ctx.fillStyle = col(C.sat); ctx.beginPath(); ctx.arc(cx + Math.cos(a) * sr, cy + Math.sin(a) * sr, W * .7, 0, full); ctx.fill();
      }
      if (this.burst > 0) {
        const p = 1 - this.burst; ctx.lineWidth = W * this.burst; ctx.strokeStyle = col(this.burst * .8);
        ctx.beginPath(); ctx.arc(cx, cy, R * (1 + p * .3), 0, full); ctx.stroke();
      }
      const D = s * C.dot * (1 + C.pulse * Math.sin(t * C.pf * full));
      const dg = ctx.createRadialGradient(cx - D * .3, cy - D * .35, D * .1, cx, cy, D);
      dg.addColorStop(0, `rgba(255,255,255,${.95 * C.alpha})`); dg.addColorStop(.35, col(1)); dg.addColorStop(1, col(.85));
      ctx.fillStyle = dg; ctx.beginPath(); ctx.arc(cx, cy, D, 0, full); ctx.fill();
      ctx.shadowBlur = 0;
    }
  }
  customElements.define('iris-orb', IrisOrb);
})();
