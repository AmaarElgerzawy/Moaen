import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/inspection_controller.dart';
import '../domain/inspection_request.dart';
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionRequest>> requests = ref.watch(
      myRequestsProvider,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myRequestsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed('createRequest'),
        icon: const Icon(Icons.add),
        label: Text(l10n.dashboardNewRequest),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myRequestsProvider);
          await ref.read(myRequestsProvider.future);
        },
        child: requests.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            // A scrollable error, so pull-to-refresh still works. A bare
            // Column with an error message has nothing to drag.
            children: <Widget>[
              const SizedBox(height: 120),
              Icon(
                Icons.cloud_off_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.md),
              Center(child: Text(l10n.errorGeneric)),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(myRequestsProvider),
                  child: Text(l10n.actionRetry),
                ),
              ),
            ],
          ),
          data: (List<InspectionRequest> all) {
            if (all.isEmpty) {
              return ListView(
                children: <Widget>[
                  const SizedBox(height: 120),
                  Icon(
                    Icons.inbox_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(child: Text(l10n.myRequestsEmpty)),
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                // Clears the extended FAB, so the last card is not permanently
                // underneath it.
                96,
              ),
              children: <Widget>[
                if (open.isNotEmpty) ...<Widget>[
                  _GroupHeader(
                    title: l10n.myRequestsOpen,
                    count: open.length,
                  ),
                  for (final InspectionRequest r in open)
                    _Tappable(request: r),
                ],
                if (settled.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  _GroupHeader(
                    title: l10n.myRequestsSettled,
                    count: settled.length,
                  ),
                  for (final InspectionRequest r in settled)
                    _Tappable(request: r),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
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

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$count',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
