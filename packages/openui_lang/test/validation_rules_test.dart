import 'package:openui_lang/openui_lang.dart';
import 'package:test/test.dart';

/// Input validation rules (language.md §5.4). The fixture state/005 runs in the conformance runner.
void main() {
  test('the first failing rule names the error', () {
    expect(validateRules('nope', {'required': true, 'email': true}), 'email');
    expect(validateRules('', {'required': true, 'email': true}), 'required');
    expect(validateRules('a@b.co', {'required': true, 'email': true}), isNull);
  });

  test('every rule but required skips empty values', () {
    for (final empty in [null, '', const <Object?>[], const <String, Object?>{}]) {
      expect(validateRules(empty, {'email': true, 'minLength': 3, 'min': 2, 'pattern': '^x'}), isNull);
      expect(validateRules(empty, {'required': true}), 'required');
    }
  });

  test('false, null and unknown rules are ignored', () {
    expect(validateRules('', {'required': false, 'shiny': true}), isNull);
  });

  test('numeric uses parseFloat, min and max read numbers from strings', () {
    expect(validateRules('12abc', {'numeric': true}), isNull);
    expect(validateRules(' ', {'numeric': true}), 'numeric');
    expect(validateRules('4', {'min': 5}), 'min');
    expect(validateRules('x', {'min': 5}), isNull, reason: 'not a number: min does not apply');
  });

  test('url needs a scheme and a host', () {
    expect(validateRules('https://openui.com/x', {'url': true}), isNull);
    expect(validateRules('openui.com', {'url': true}), 'url');
    expect(validateRules('mailto:a@b.c', {'url': true}), 'url', reason: 'the spec asks for a host');
  });

  test('a bad pattern is ignored', () {
    expect(validateRules('x', {'pattern': '('}), isNull);
  });
}
