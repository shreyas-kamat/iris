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

/// How an approval was answered by voice.
enum SpokenVerdict { approve, deny }

const _approveWords = {
  'approve',
  'approved',
  'yes',
  'yeah',
  'yep',
  'yup',
  'ok',
  'okay',
  'allow',
  'proceed',
  'confirm',
  'affirmative',
};

const _approvePhrases = ['go ahead', 'do it', 'run it', 'go for it'];

const _denyWords = {
  'deny',
  'denied',
  'no',
  'nope',
  'nah',
  'dont',
  'cancel',
  'reject',
  'refuse',
  'negative',
  'never',
};

/// An answer longer than this is a remark, not a verdict.
const _longestVerdict = 8;

/// Whether [heard] approves or denies: "approve", "yes", "go ahead", or
/// "deny", "no", "don't". A refusal anywhere wins over a yes, because acting
/// on a misheard yes costs more than asking again. Anything else, or a long
/// remark, is null.
SpokenVerdict? matchApproval(String heard) {
  final words = _words(heard);
  if (words.isEmpty || words.length > _longestVerdict) return null;
  if (words.any(_denyWords.contains)) return SpokenVerdict.deny;
  final joined = words.join(' ');
  if (words.any(_approveWords.contains) ||
      _approvePhrases.any(joined.contains)) {
    return SpokenVerdict.approve;
  }
  return null;
}

/// The one of [choices] that [heard] names, by its words, or null when it
/// names none or more than one ("the second one" is not a choice).
String? matchChoice(String heard, List<String> choices) {
  final said = _words(heard);
  if (said.isEmpty) return null;
  final found = <String>[];
  for (final choice in choices) {
    final words = _words(choice);
    if (words.isEmpty || words.length > said.length) continue;
    for (var at = 0; at + words.length <= said.length; at++) {
      if (_same(words, said, at)) {
        found.add(choice);
        break;
      }
    }
  }
  return found.length == 1 ? found.single : null;
}
