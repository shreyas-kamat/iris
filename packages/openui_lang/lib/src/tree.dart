/// The validated program tree (language.md §9.1). Values are plain Dart (String, double, bool, null, List, Map),
/// [Element]s, [Binding]s, or [Deferred] expressions that the evaluator resolves later.
library;

import 'ast.dart';

class Element {
  Element(this.type, this.statementId, this.props);

  final String type;

  /// The statement this call was written in.
  final String statementId;

  /// Named props in positional order. Absent and null props are not stored.
  final Map<String, Object?> props;

  @override
  String toString() => '$type($props)';
}

/// A prop bound two-way to `$name`.
class Binding {
  const Binding(this.name);
  final String name;
  @override
  String toString() => 'bind($name)';
}

/// An evaluated action (language.md §6.3): the steps run in order when a component triggers it. One action call is an
/// `ActionValue` of one step; `Action([...])` flattens its list. An invalid action is an empty one and does nothing.
class ActionValue {
  const ActionValue(this.steps);
  final List<ActionStep> steps;
  @override
  String toString() => 'Action($steps)';
}

sealed class ActionStep {
  const ActionStep();
}

/// `@Set($var, value)`: [value] is evaluated when the action runs (`Evaluator.evaluateStepValue`).
class SetStep extends ActionStep {
  const SetStep(this.target, this.value);
  final String target;
  final Expr value;
}

/// `@Reset($a, $b, ...)`.
class ResetStep extends ActionStep {
  const ResetStep(this.targets);
  final List<String> targets;
}

/// `@Run(ref)`: runs a mutation or fetches a query again.
class RunStep extends ActionStep {
  const RunStep(this.statementId);
  final String statementId;
}

/// `@ToAssistant(message, context?)`: a `continue_conversation` event.
class ToAssistantStep extends ActionStep {
  const ToAssistantStep(this.message, [this.context]);
  final String message;
  final Object? context;
}

/// `@OpenUrl(url)`: an `open_url` event.
class OpenUrlStep extends ActionStep {
  const OpenUrlStep(this.url);
  final String url;
}

/// A library action: an event with `type` = [name] and [params] keyed by the action's parameter names.
class CustomStep extends ActionStep {
  const CustomStep(this.name, this.params);
  final String name;
  final Map<String, Object?> params;
}

/// An expression the evaluator must run (operators, built-ins, member access, ternaries, state reads, queries).
class Deferred {
  const Deferred(this.expr, this.statementId);
  final Expr expr;
  final String statementId;
  @override
  String toString() => 'deferred($expr)';
}
