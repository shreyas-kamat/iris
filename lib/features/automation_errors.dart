/// How a failed write to the cron, Kanban or profile routes is worded.
library;

import '../core/failure.dart';
import 'chat/chat_controller.dart';

/// A route the server lacks is not an error in the person's request.
String describeWrite(IrisFailure failure) =>
    failure.kind == FailureKind.notFound
    ? 'Not supported on this server'
    : ChatController.describe(failure);
