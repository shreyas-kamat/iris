/// Conversations archived from home, newest first, each one a tap away from
/// coming back.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/toast.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import 'chat_controller.dart';
import 'chat_screen.dart';
import 'conversation_row.dart';
import 'delete_sheet.dart';

class ArchivedScreen extends StatefulWidget {
  const ArchivedScreen({required this.backend, super.key});

  final ChatBackend backend;

  @override
  State<ArchivedScreen> createState() => _ArchivedScreenState();
}

class _ArchivedScreenState extends State<ArchivedScreen> {
  List<ConversationSummary>? _rows;
  int _total = 0;
  String? _error;
  bool _loadingMore = false;
  final Set<String> _gone = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final page = await widget.backend.archivedConversations(0);
    if (!mounted) return;
    setState(() {
      switch (page) {
        case Ok(:final value):
          _rows = value.items;
          _total = value.total;
        case Err(:final failure):
          _error = ChatController.describe(failure);
      }
    });
  }

  Future<void> _more() async {
    final rows = _rows;
    if (rows == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    final page = await widget.backend.archivedConversations(rows.length);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (page case Ok(:final value)) _rows = [...rows, ...value.items];
    });
  }

  Future<void> _unarchive(ConversationSummary row) async {
    unawaited(IrisHaptics.commit());
    setState(() => _gone.add(row.id));
    final result = await widget.backend.setArchived(row.id, archived: false);
    if (!mounted) return;
    if (result case Err(:final failure)) {
      setState(() => _gone.remove(row.id));
      showIrisToast(
        context,
        message: 'Could not unarchive: ${ChatController.describe(failure)}',
      );
    }
  }

  Future<void> _delete(ConversationSummary row) async {
    if (!await showDeleteSheet(context, row.title) || !mounted) return;
    unawaited(IrisHaptics.commit());
    setState(() => _gone.add(row.id));
    final result = await widget.backend.delete(row.id);
    if (!mounted) return;
    if (result case Err(:final failure)) {
      setState(() => _gone.remove(row.id));
      showIrisToast(
        context,
        message: refusedAsLive(failure)
            ? 'Stop the reply before deleting this chat.'
            : 'Could not delete: ${ChatController.describe(failure)}',
      );
    }
  }

  Future<void> _open(ConversationSummary row) => Navigator.of(context).push(
    IrisPageRoute<void>(
      builder: (_) => ChatScreen(
        backend: widget.backend,
        conversationId: row.id,
        title: row.title,
        archived: true,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final gutter = context.window.gutter;
    return IrisScaffold(
      header: Padding(
        padding: EdgeInsets.fromLTRB(gutter, IrisSpace.sm, gutter, IrisSpace.sm),
        child: Row(
          children: [
            IrisCircleButton(
              icon: Icons.arrow_back_ios_new,
              semanticLabel: 'Back',
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              gutter + IrisSpace.xs,
              IrisSpace.xs,
              gutter,
              IrisSpace.md,
            ),
            child: Text(
              'Archived',
              style: context.type.serif.copyWith(fontSize: 34, height: 1),
            ),
          ),
          Expanded(child: _body(context, gutter)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, double gutter) {
    if (_error case final error?) {
      return IrisEmptyState(
        title: 'Could not load archived chats',
        message: error,
        action: IrisButton(
          label: 'Try again',
          onPressed: () => unawaited(_load()),
        ),
      );
    }
    final rows = _rows;
    if (rows == null) {
      return ListView(
        padding: EdgeInsets.symmetric(
          horizontal: gutter,
          vertical: IrisSpace.md,
        ),
        children: [
          for (var i = 0; i < 4; i++) ...[
            const IrisSkeleton(width: 220, height: 16),
            const SizedBox(height: IrisSpace.lg),
          ],
        ],
      );
    }
    if (rows.every((row) => _gone.contains(row.id))) {
      return const IrisEmptyState(
        title: 'Nothing archived',
        message:
            'Chats you archive from home wait here until you bring them back.',
      );
    }
    final hasMore = rows.length < _total;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, IrisSpace.sm, gutter, IrisSpace.xl),
      children: [
        for (final row in rows)
          Leaving(
            key: ValueKey(row.id),
            gone: _gone.contains(row.id),
            child: ConversationRow(
              title: row.title,
              onTap: () => unawaited(_open(row)),
              onLongPress: () => unawaited(_delete(row)),
              // Named with the chat's title: a list of identical
              // "Unarchive" buttons says nothing to a screen reader.
              trailing: Semantics(
                container: true,
                label: 'Unarchive ${row.title}',
                button: true,
                excludeSemantics: true,
                child: IrisButton(
                  label: 'Unarchive',
                  tone: IrisButtonTone.ghost,
                  onPressed: () => unawaited(_unarchive(row)),
                ),
              ),
            ),
          ),
        if (hasMore)
          Center(
            child: IrisButton(
              label: 'Show more',
              tone: IrisButtonTone.ghost,
              busy: _loadingMore,
              onPressed: () => unawaited(_more()),
            ),
          ),
      ],
    );
  }
}
