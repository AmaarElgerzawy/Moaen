import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/inspection_controller.dart';
import '../domain/inspection_request.dart';
import 'widgets/design_widgets.dart';
import 'widgets/request_widgets.dart';

/// The buyer's request history.
///
/// Split into open and settled rather than shown as one chronological list.
/// A buyer opens this to answer "is anything happening", and burying an
/// in-progress inspection below last month's completed ones is how that answer
/// gets missed.
class MyRequestsPage extends ConsumerWidget {
  const MyRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(body: MyRequestsBody());
  }
}

/// The list itself, without a [Scaffold].
///
/// Split out because the buyer's shell shows this as a tab and the route shows
/// it as a pushed page, and the two must not be able to drift: a `Scaffold` with
/// an `AppBar` inside a tab would put a second app bar under the shell's header,
/// and one with a `bottomNavigationBar` would draw a second bar above the
/// shell's. The header and the bar are the shell's job, so the body has neither.
class MyRequestsBody extends ConsumerWidget {
  const MyRequestsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionRequest>> requests = ref.watch(
      myRequestsProvider,
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myRequestsProvider);
        await ref.read(myRequestsProvider.future);
      },
      child: requests.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Every branch is scrollable, so pull-to-refresh works even on the error
        // and empty states. A bare `Column` has nothing to drag, and the one
        // action that would fix a failed read is the gesture the user already
        // knows.
        error: (_, _) => ListView(
          children: <Widget>[
            const SizedBox(height: AppSpacing.xxxl * 3),
            DesignRetry(
              message: l10n.tabLoadError,
              actionLabel: l10n.actionRetry,
              onRetry: () => ref.invalidate(myRequestsProvider),
            ),
          ],
        ),
        data: (List<InspectionRequest> all) {
          if (all.isEmpty) {
            return ListView(
              children: <Widget>[
                const SizedBox(height: AppSpacing.xxxl * 3),
                DesignEmpty(title: l10n.myRequestsEmpty),
              ],
            );
          }

          final List<InspectionRequest> open = all
              .where((InspectionRequest r) => r.status.isOpen)
              .toList();
          final List<InspectionRequest> settled = all
              .where((InspectionRequest r) => !r.status.isOpen)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.inset),
            children: <Widget>[
              // A heading above each half, not just a rule between them. The rule
              // says *something* changed here; only the headings say which half
              // is live work, and that is the question this page exists to answer.
              // A settled row directly under an open one is otherwise ambiguous,
              // and the ambiguity falls exactly on the buyer who came here to
              // check on something in progress.
              if (open.isNotEmpty) ...<Widget>[
                _SectionLabel(l10n.myRequestsOpen),
                for (final InspectionRequest r in open)
                  _Tappable(request: r),
              ],
              if (open.isNotEmpty && settled.isNotEmpty)
                const DashedDivider(indent: AppSpacing.inset),
              if (settled.isNotEmpty) ...<Widget>[
                _SectionLabel(l10n.myRequestsSettled),
                for (final InspectionRequest r in settled)
                  _Tappable(request: r),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The heading above one half of the list.
///
/// Small, quiet and secondary: the rows are the content and the labels only
/// exist to bound them, so this is the design's 11px secondary grey rather than
/// anything that competes with a car name.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(text, style: AppText.secondary(11)),
  );
}

class _Tappable extends StatelessWidget {
  const _Tappable({required this.request});

  final InspectionRequest request;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: RequestCard(
        request: request,
        onTap: () => context.pushNamed(
          'requestDetail',
          pathParameters: <String, String>{'id': request.id},
        ),
      ),
    );
  }
}
