/// What a demo turn does, step by step. Data only; `ScriptPlayer` plays it.
library;

sealed class DemoStep {
  const DemoStep();
}

/// Visible thinking.
final class ThinkStep extends DemoStep {
  const ThinkStep(this.text);
  final String text;
}

/// A tool call that runs for [duration] and returns [output].
final class ToolStep extends DemoStep {
  const ToolStep(
    this.name, {
    required this.input,
    required this.output,
    this.duration = const Duration(milliseconds: 1500),
    this.failed = false,
  });
  final String name;
  final String input;
  final String output;
  final Duration duration;
  final bool failed;
}

/// Asks to run [command] and plays one branch or the other.
final class ApprovalStep extends DemoStep {
  const ApprovalStep({
    required this.command,
    required this.description,
    required this.ifApproved,
    required this.ifDenied,
  });
  final String command;
  final String description;
  final List<DemoStep> ifApproved;
  final List<DemoStep> ifDenied;
}

/// Asks for a sudo password. Any answer continues; none is kept.
final class SecretStep extends DemoStep {
  const SecretStep(this.command);
  final String command;
}

/// Reply text, in Markdown.
final class SayStep extends DemoStep {
  const SayStep(this.markdown);
  final String markdown;
}

/// How full the context window is, 0 to 100.
final class ContextStep extends DemoStep {
  const ContextStep(this.percent);
  final double percent;
}

/// Ends the turn as failed, so retry can be shown.
final class FailStep extends DemoStep {
  const FailStep(this.message);
  final String message;
}

/// A suggested prompt and what it plays.
final class DemoScript {
  const DemoScript({
    required this.prompt,
    required this.title,
    required this.steps,
    this.firstRun,
  });

  /// The text that triggers it, as shown on its suggestion.
  final String prompt;

  /// The new conversation's title.
  final String title;

  final List<DemoStep> steps;

  /// Played instead of [steps] the first time only, so a retry can succeed.
  final List<DemoStep>? firstRun;
}
