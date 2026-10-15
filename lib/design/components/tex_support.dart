// lib/design/components/tex_support.dart
/// The TeX agents write that flutter_math_fork doesn't know: AMS display
/// environments, the `physics` package, `siunitx` units and `mhchem`
/// chemistry. Macros map what they can; a rewrite pass handles
/// environments, optional arguments and `\ce`. Probed against 93
/// expressions on flutter_math_fork 0.7.4.
library;

import 'package:flutter_math_fork/tex.dart';

MacroDefinition _m(String expansion) => MacroDefinition.fromString(expansion);

/// Takes one argument and draws nothing, for `\label{…}`.
final MacroDefinition _drop1 = MacroDefinition.fromMacroExpansion(
  const MacroExpansion(tokens: [], numArgs: 1),
);

final Map<String, MacroDefinition> irisTexMacros = {
  // AMS numbering: a tag is shown, labels and \nonumber vanish.
  r'\tag': _m(r'\qquad(\text{#1})'),
  r'\label': _drop1,
  r'\nonumber': _m(''),
  r'\notag': _m(''),
  r'\AA': _m(r'\mathring{\mathrm{A}}'),
  // physics. \dv[n] and \pdv[n] are rewritten to \irisdvn / \irispdvn first.
  r'\dv': _m(r'\irisdv'),
  r'\irisdv': _m(r'\frac{\mathrm{d}#1}{\mathrm{d}#2}'),
  r'\irisdvn': _m(r'\frac{\mathrm{d}^{#1}#2}{\mathrm{d}#3^{#1}}'),
  r'\pdv': _m(r'\irispdv'),
  r'\irispdv': _m(r'\frac{\partial #1}{\partial #2}'),
  r'\irispdvn': _m(r'\frac{\partial^{#1}#2}{\partial #3^{#1}}'),
  r'\abs': _m(r'\left\lvert #1\right\rvert'),
  r'\norm': _m(r'\left\lVert #1\right\rVert'),
  r'\grad': _m(r'\nabla'),
  r'\curl': _m(r'\nabla\times'),
  r'\divergence': _m(r'\nabla\cdot'),
  r'\laplacian': _m(r'\nabla^2'),
  // physics' \qty(…) auto-sizes; siunitx's \qty{9.8}{m} is a quantity.
  // Dropping the command serves both well enough: the brackets or the two
  // groups that follow are drawn as written.
  r'\qty': _m(''),
  r'\expval': _m(r'\left\langle #1\right\rangle'),
  r'\mel': _m(r'\left\langle #1\middle\vert #2\middle\vert #3\right\rangle'),
  r'\comm': _m(r'\left[#1,#2\right]'),
  r'\order': _m(r'\mathcal{O}\left(#1\right)'),
  r'\vb': _m(r'\mathbf{#1}'),
  r'\vu': _m(r'\hat{\mathbf{#1}}'),
  r'\dd': _m(r'\mathrm{d}'),
  r'\tr': _m(r'\operatorname{tr}'),
  r'\Tr': _m(r'\operatorname{Tr}'),
  // siunitx
  r'\SI': _m(r'#1\,\mathrm{#2}'),
  r'\si': _m(r'\mathrm{#1}'),
  r'\unit': _m(r'\mathrm{#1}'),
  r'\num': _m('#1'),
  r'\ang': _m(r'#1^\circ'),
  r'\pu': _m(r'\mathrm{#1}'),
  r'\per': _m('/'),
  r'\squared': _m('^2'),
  r'\cubed': _m('^3'),
  r'\metre': _m('m'),
  r'\meter': _m('m'),
  r'\second': _m('s'),
  r'\kilogram': _m('kg'),
  r'\gram': _m('g'),
  r'\newton': _m('N'),
  r'\joule': _m('J'),
  r'\watt': _m('W'),
  r'\pascal': _m('Pa'),
  r'\kelvin': _m('K'),
  r'\ampere': _m('A'),
  r'\volt': _m('V'),
  r'\ohm': _m(r'\Omega'),
  r'\hertz': _m('Hz'),
  r'\mole': _m('mol'),
  r'\coulomb': _m('C'),
  r'\tesla': _m('T'),
  r'\electronvolt': _m('eV'),
  r'\litre': _m('L'),
  r'\degreeCelsius': _m(r'{}^\circ\mathrm{C}'),
  r'\kilo': _m('k'),
  r'\mega': _m('M'),
  r'\giga': _m('G'),
  r'\centi': _m('c'),
  r'\milli': _m('m'),
  r'\micro': _m(r'\mu '),
  r'\nano': _m('n'),
};

/// [tex] rewritten for the parser: chemistry expanded, optional derivative
/// orders made plain arguments, and AMS environments mapped to the ones
/// it has.
String prepareTex(String tex) => _replaceCe(tex)
    .replaceAllMapped(
      RegExp(r'\\(dv|pdv)\[([^\]]*)\]'),
      (m) => '\\iris${m[1]}n{${m[2]}}',
    )
    // One argument is the variable of an operator: physics reads \pdv{t} as
    // ∂/∂t, and only a second group makes it a fraction.
    .replaceAllMapped(
      RegExp(r'\\(dv|pdv)\{([^{}]*)\}(?!\s*\{)'),
      (m) => m[1] == 'dv'
          ? '\\frac{\\mathrm{d}}{\\mathrm{d} ${m[2]}}'
          : '\\frac{\\partial}{\\partial ${m[2]}}',
    )
    .replaceAllMapped(
      RegExp(r'\\(begin|end)\{(align|flalign|eqnarray|split)\*?\}'),
      (m) => '\\${m[1]}{aligned}',
    )
    .replaceAllMapped(
      RegExp(r'\\(begin|end)\{alignat\*?\}'),
      (m) => '\\${m[1]}{alignedat}',
    )
    .replaceAll(RegExp(r'\\begin\{(gather|multline)\*?\}'), r'\begin{array}{c}')
    .replaceAll(RegExp(r'\\end\{(gather|multline)\*?\}'), r'\end{array}')
    .replaceAll(RegExp(r'\\(begin|end)\{(equation|displaymath)\*?\}'), '');

/// Every `\ce{…}` replaced, braces matched. An unclosed one is left alone,
/// so the parser fails and the source shows.
String _replaceCe(String tex) {
  final out = StringBuffer();
  var i = 0;
  while (true) {
    final start = tex.indexOf(r'\ce{', i);
    if (start < 0) break;
    var depth = 0;
    var end = -1;
    for (var j = start + 3; j < tex.length; j++) {
      if (tex[j] == '{') depth++;
      if (tex[j] == '}' && --depth == 0) {
        end = j;
        break;
      }
    }
    if (end < 0) break;
    out
      ..write(tex.substring(i, start))
      ..write('{${_mhchem(tex.substring(start + 4, end))}}');
    i = end + 1;
  }
  return (out..write(tex.substring(i))).toString();
}

/// mhchem's common cases: formulas, coefficients, charges, states and
/// arrows. Anything stranger draws as upright text, which still reads.
String _mhchem(String source) {
  const arrows = {
    '<=>': r'\rightleftharpoons',
    '<->': r'\leftrightarrow',
    '->': r'\rightarrow',
    '<-': r'\leftarrow',
  };
  return [
    for (final token in source.trim().split(RegExp(r'\s+')))
      arrows[token] ?? (token == '+' ? '+' : _species(token)),
  ].join(' ');
}

String _species(String token) {
  final parts = RegExp(r'^(\d+(?:/\d+)?)?(.*)$').firstMatch(token)!;
  final coefficient = parts[1] ?? '';
  var body = parts[2]!;
  var state = '';
  final s = RegExp(r'\((s|l|g|aq)\)$').firstMatch(body);
  if (s != null) {
    state = '\\,(\\mathrm{${s[1]}})';
    body = body.substring(0, s.start);
  }
  var charge = '';
  final c =
      RegExp(r'\^\{?(\d*[+-])\}?$').firstMatch(body) ??
      RegExp(r'(?<=[A-Za-z\d)\]])(\d*[+-])$').firstMatch(body);
  if (c != null && c.start > 0) {
    charge = '^{${c[1]}}';
    body = body.substring(0, c.start);
  }
  final formula = body.replaceAllMapped(
    RegExp(r'([A-Za-z)\]])(\d+)'),
    (x) => '${x[1]}_{${x[2]}}',
  );
  return '$coefficient\\mathrm{$formula}$charge$state';
}
