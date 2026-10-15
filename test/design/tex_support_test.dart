// test/design/tex_support_test.dart
/// TeX as agents write it (algebra, calculus, physics, units, chemistry)
/// must all lay out. The corpus was probed against flutter_math_fork 0.7.4.
library;

import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/tex_support.dart';

const corpus = <String, String>{
  // Algebra
  'quadratic': r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}',
  'binomial': r'(a+b)^n = \sum_{k=0}^{n} \binom{n}{k} a^{n-k} b^k',
  'nthroot': r'\sqrt[3]{x^2+1}',
  'system cases': r'\begin{cases} 2x + y = 5 \\ x - y = 1 \end{cases}',
  'piecewise': r'f(x) = \begin{cases} x^2 & x \ge 0 \\ -x & \text{otherwise} \end{cases}',
  'aligned': r'\begin{aligned} (x+1)^2 &= x^2 + 2x + 1 \\ &\geq 0 \end{aligned}',
  'matrix': r'A = \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}',
  'bmatrix det': r'\det\begin{bmatrix} a & b \\ c & d \end{bmatrix} = ad - bc',
  'vmatrix': r'\begin{vmatrix} a & b \\ c & d \end{vmatrix}',
  'array': r'\left[\begin{array}{cc|c} 1 & 2 & 3 \\ 4 & 5 & 6 \end{array}\right]',
  'big matrix': r'\begin{pmatrix} a_{11} & \cdots & a_{1n} \\ \vdots & \ddots & \vdots \\ a_{m1} & \cdots & a_{mn} \end{pmatrix}',
  'logs': r'\log_b(xy) = \log_b x + \log_b y, \ln e = 1',
  'mod': r'a \equiv b \pmod{n}',
  'sets': r'\mathbb{R}, \mathbb{Z}, \forall x \in A \cup B, \emptyset \subseteq S',
  'groups': r'G / \ker\varphi \cong \operatorname{im}\varphi',
  'boxed': r'\boxed{x = 2}',
  'cancel': r'\frac{\cancel{2}x}{\cancel{2}}',
  'overbrace': r'\overbrace{1+2+\cdots+n}^{n \text{ terms}}',
  'underbrace': r'\underbrace{a+b}_{c}',
  'stackrel': r'\stackrel{?}{=}',
  'overset': r'\overset{\text{def}}{=}',
  'xrightarrow': r'A \xrightarrow{f} B',
  'floor ceil': r'\lfloor x \rfloor + \lceil y \rceil',
  'complex': r'z = re^{i\theta}, \bar{z}, |z|, \Re(z), \Im(z)',
  'eigen': r'\det(A - \lambda I) = 0, \quad A\mathbf{v} = \lambda \mathbf{v}',
  // Calculus
  'limit': r'\lim_{x \to 0} \frac{\sin x}{x} = 1',
  'derivative': r'\frac{d}{dx} x^n = n x^{n-1}',
  'partial': r'\frac{\partial^2 f}{\partial x \partial y}',
  'integral': r'\int_a^b f(x)\,dx = F(b) - F(a)',
  'double int': r'\iint_D f(x,y)\,dA',
  'triple int': r'\iiint_V \rho\,dV',
  'contour': r'\oint_C \mathbf{F} \cdot d\mathbf{r}',
  'oiint': r'\oiint_S \mathbf{E}\cdot d\mathbf{A}',
  'series': r'e^x = \sum_{n=0}^{\infty} \frac{x^n}{n!}',
  'product': r'\prod_{i=1}^n x_i',
  'taylor': r'f(x) = \sum_{n=0}^\infty \frac{f^{(n)}(a)}{n!}(x-a)^n',
  'primes': r"f'(x), f''(x), \dot{x}, \ddot{x}",
  'evaluated': r'\left. \frac{x^2}{2} \right|_0^1',
  'limsup': r'\limsup_{n\to\infty} a_n',
  'ode': "y'' + p(x)y' + q(x)y = 0",
  'fourier': r'\hat{f}(\xi) = \int_{-\infty}^{\infty} f(x)\, e^{-2\pi i x \xi}\, dx',
  'sum limits': r'\sum_{\substack{i=1 \\ i \ne j}}^{n} a_i',
  // Physics
  'maxwell': r'\nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t}',
  'gauss': r'\nabla \cdot \mathbf{E} = \frac{\rho}{\varepsilon_0}',
  'laplacian sym': r'\nabla^2 \phi = 0, \Delta u',
  'vec hat': r'\vec{F} = m\vec{a}, \hat{n}, \boldsymbol{\sigma}, \bm{v}',
  'schrodinger': r'i\hbar \frac{\partial}{\partial t}\Psi = \hat{H}\Psi',
  'bra ket': r'\langle \psi | \phi \rangle, \ket{\psi}, \bra{\psi}, \braket{\psi}{\phi}',
  'tensor': r'R^\mu{}_{\nu\rho\sigma}, g_{\mu\nu} dx^\mu dx^\nu',
  'einstein': r'G_{\mu\nu} + \Lambda g_{\mu\nu} = \frac{8\pi G}{c^4} T_{\mu\nu}',
  'lagrangian': r'\frac{d}{dt}\frac{\partial \mathcal{L}}{\partial \dot{q}} = \frac{\partial \mathcal{L}}{\partial q}',
  'units manual': r'g = 9.81\,\mathrm{m\,s^{-2}}',
  'relations': r'F \propto \frac{1}{r^2}, \approx, \sim, \ll, \gg',
  'dagger otimes': r'A^\dagger, \psi \otimes \phi, [\hat{x}, \hat{p}] = i\hbar',
  'degree': r'90^\circ',
  'mathscr frak': r'\mathscr{L}, \mathfrak{g}',
  'color': r'\color{red}{x}',
  // Supported through tex_support.dart
  'align*': r'\begin{align*} a &= b + c \\ d &= e \end{align*}',
  'align label': r'\begin{align} a &= b \label{eq:1} \\ c &= d \nonumber \end{align}',
  'equation': r'\begin{equation} E = mc^2 \end{equation}',
  'gather': r'\begin{gather} a = b \\ c = d \end{gather}',
  'multline': r'\begin{multline} a + b \\ = c \end{multline}',
  'alignat': r'\begin{alignat}{2} x &= 1 & y &= 2 \end{alignat}',
  'split': r'\begin{split} a &= b \\ &= c \end{split}',
  'tag': r'a = b \tag{1}',
  'angstrom': r'1\,\AA',
  'dv': r'\dv{f}{x}',
  'dv n': r'\dv[2]{y}{t}',
  'pdv': r'\pdv{f}{x}',
  'pdv n': r'\pdv[2]{u}{x}',
  'abs': r'\abs{x - 1}',
  'norm': r'\norm{\vb{v}}',
  'grad curl': r'\grad{\phi}, \curl{\vb{B}}',
  'qty': r'\qty(\frac{a}{b})',
  'expval': r'\expval{\hat{H}}',
  'mel': r'\mel{n}{\hat{H}}{m}',
  'comm': r'\comm{\hat{x}}{\hat{p}} = i\hbar',
  'order': r'\order{n^2}',
  'dd': r'\int f\,\dd x',
  'SI': r'\SI{9.81}{m/s^2}',
  'SI macros': r'\SI{3e8}{\metre\per\second}',
  'si': r'\si{kg.m^2}',
  'unit': r'\unit{\metre\per\second\squared}',
  'num ang': r'\num{6.022e23}, \ang{45}',
  'siunitx qty': r'\qty{9.8}{\metre\per\second\squared}',
  'celsius': r'\SI{25}{\degreeCelsius}',
  'newcommand': r'\newcommand{\Rn}{\mathbb{R}^n} \Rn',
  'ce': r'\ce{H2O}',
  'ce reaction': r'\ce{2H2 + O2 -> 2H2O}',
  'ce ions': r'\ce{SO4^2- + Ba^2+ -> BaSO4}',
  'ce equilibrium': r'\ce{CH3COOH <=> CH3COO- + H+}',
  'ce states': r'\ce{NaCl(s) -> Na+(aq) + Cl-(aq)}',
  'ce inline': r'K = \frac{[\ce{H+}][\ce{A-}]}{[\ce{HA}]}',
};

void main() {
  for (final MapEntry(key: name, value: tex) in corpus.entries) {
    test('$name lays out', () {
      expect(
        () => TexParser(prepareTex(tex), TexParserSettings(macros: irisTexMacros)).parse(),
        returnsNormally,
      );
    });
  }

  test('chemistry reads as chemistry', () {
    expect(
      prepareTex(r'\ce{NaCl(s) -> Na+(aq) + Cl-(aq)}'),
      r'{\mathrm{NaCl}\,(\mathrm{s}) \rightarrow \mathrm{Na}^{+}\,(\mathrm{aq}) + \mathrm{Cl}^{-}\,(\mathrm{aq})}',
    );
    expect(
      prepareTex(r'\ce{SO4^2- + Ba^2+ -> BaSO4}'),
      r'{\mathrm{SO_{4}}^{2-} + \mathrm{Ba}^{2+} \rightarrow \mathrm{BaSO_{4}}}',
    );
  });

  test('a derivative with one argument is an operator, not a fraction', () {
    expect(
      prepareTex(r'i\hbar \pdv{t}\ket{\psi}'),
      r'i\hbar \frac{\partial}{\partial t}\ket{\psi}',
    );
    expect(prepareTex(r'\dv{x} f'), r'\frac{\mathrm{d}}{\mathrm{d} x} f');
    // Two arguments stay a fraction.
    expect(prepareTex(r'\pdv{f}{x}'), r'\pdv{f}{x}');
  });

  test('an unclosed \\ce is left for the error fallback', () {
    expect(prepareTex(r'\ce{H2O'), r'\ce{H2O');
  });
}
