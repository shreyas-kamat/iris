/// Matching what was heard against what it might be: a stop phrase, or Iris
/// hearing itself.
library;

final _apostrophes = RegExp("['’]");
final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _fence = RegExp(r'```[\s\S]*?(?:```|$)');

/// Lower case, apostrophes dropped, every other mark a word break.
List<String> _words(String text) => text
    .toLowerCase()
    .replaceAll(_apostrophes, '')
    .split(_separators)
    .where((w) => w.isNotEmpty)
    .toList();

/// [heard] is exactly one of [phrases], ignoring case and punctuation: "Stop."
/// ends the call, "stop the deploy" does not.
bool isStopPhrase(String heard, List<String> phrases) {
  final words = _words(heard).join(' ');
  if (words.isEmpty) return false;
  return phrases.any((phrase) => _words(phrase).join(' ') == words);
}

/// [heard] is Iris's own voice coming back through the microphone: all of
/// what it just [spoke], or a run of three or more of its words in order.
/// Shorter runs ("yes") are too likely to be a real answer.
bool isEcho(String heard, String spoke) {
  final h = _words(heard);
  final s = _words(spoke);
  if (h.isEmpty || s.isEmpty) return false;
  if (h.length == s.length) return _same(h, s, 0);
  if (h.length < 3 || h.length > s.length) return false;
  for (var start = 0; start + h.length <= s.length; start++) {
    if (_same(h, s, start)) return true;
  }
  return false;
}

bool _same(List<String> run, List<String> within, int at) {
  for (var i = 0; i < run.length; i++) {
    if (run[i] != within[at + i]) return false;
  }
  return true;
}

/// [text] without its code blocks, which are read on the screen, not aloud.
/// Empty when nothing is left to say.
String speakable(String text) => text.replaceAll(_fence, '').trim();
