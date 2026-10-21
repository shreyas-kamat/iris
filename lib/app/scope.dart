/// Reaching the provider container from a widget that is not a consumer.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The container of the nearest [ProviderScope], or null when there is none.
///
/// For the few places that read a preference or a seam once, from plain
/// widgets that are also built bare in tests, where `ProviderScope.containerOf`
/// would throw.
ProviderContainer? maybeProviderContainer(BuildContext context) => context
    .findAncestorWidgetOfExactType<UncontrolledProviderScope>()
    ?.container;
