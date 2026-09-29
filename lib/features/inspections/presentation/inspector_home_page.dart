import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/auth_controller.dart';
import '../../auth/user_profile.dart';
import '../../auth/user_role_localizations.dart';
import '../application/inspection_controller.dart';
import '../domain/inspection_request.dart';
import 'widgets/request_widgets.dart';

/// The inspector's home: three surfaces for the work an inspector has.
///
/// [InspectorHomePage] is a shell over three tabs — the job board of requests
/// waiting in the inspector's city, the jobs they have taken, and their
/// profile. Everything an inspector does starts here and returns here, so the
/// tabs live in one scaffold with a navigation bar rather than three routes:
/// the job detail pushes a full-screen route on top, and the tab state (and
/// the scroll position of a long board) survives the round trip.
class InspectorHomePage extends ConsumerStatefulWidget {
  const InspectorHomePage({super.key});

  @override
  ConsumerState<InspectorHomePage> createState() => _InspectorHomePageState();
}

class _InspectorHomePageState extends ConsumerState<InspectorHomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_index) {
          0 => l10n.navJobBoard,
          1 => l10n.navMyJobs,
          _ => l10n.navProfile,
        }),
      ),
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          _BoardTab(),
          _JobsTab(),
          _ProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int index) => setState(() => _index = index),
        destinations: <Widget>[
          NavigationDestination(
            icon: const Icon(Icons.work_outline),
            selectedIcon: const Icon(Icons.work),
            label: l10n.navJobBoard,
          ),
          NavigationDestination(
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: const Icon(Icons.assignment),
            label: l10n.navMyJobs,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.navProfile,
          ),
        ],
      ),
    );
  }
}

/// Requests waiting in the inspector's city, newest first (the board RLS policy
/// and the `inspections_board_idx` index in migration 0001 agree on that order).
class _BoardTab extends ConsumerWidget {
  const _BoardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UserProfile? profile = ref.watch(authControllerProvider).value;
    final String city = profile?.locationCity ?? '';
    final AsyncValue<List<InspectionRequest>> board = ref.watch(jobBoardProvider);

    return board.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _RetryMessage(
        message: l10n.boardLoadError,
        onRetry: () => ref.invalidate(jobBoardProvider),
      ),
      data: (List<InspectionRequest> requests) {
        if (requests.isEmpty) {
          return _CenteredMessage(
            title: l10n.boardEmptyTitle,
            body: l10n.boardEmptyBody(city),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                l10n.boardTitle(city),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                itemCount: requests.length,
                itemBuilder: (BuildContext context, int index) {
                  final InspectionRequest request = requests[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: RequestCard(
                      request: request,
                      onTap: () => context.push(
                        AppRoutes.inspectorJobDetailPath(request.id),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The inspector's own jobs, grouped into open work and settled work exactly
/// the way the buyer's requests are — an inspector who has taken a request
/// needs the same separation of "still happening" from "done".
class _JobsTab extends ConsumerWidget {
  const _JobsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionRequest>> jobs = ref.watch(myJobsProvider);

    return jobs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _RetryMessage(
        message: l10n.jobsLoadError,
        onRetry: () => ref.invalidate(myJobsProvider),
      ),
      data: (List<InspectionRequest> all) {
        if (all.isEmpty) {
          return _CenteredMessage(title: l10n.jobsEmpty);
        }

        final List<InspectionRequest> open = <InspectionRequest>[
          for (final InspectionRequest request in all)
            if (request.status.isOpen) request,
        ];
        final List<InspectionRequest> settled = <InspectionRequest>[
          for (final InspectionRequest request in all)
            if (!request.status.isOpen) request,
        ];

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: <Widget>[
            if (open.isNotEmpty)
              _SectionHeader(l10n.myRequestsOpen),
            ..._jobCards(context, open),
            if (settled.isNotEmpty)
              _SectionHeader(l10n.myRequestsSettled),
            ..._jobCards(context, settled),
          ],
        );
      },
    );
  }

  List<Widget> _jobCards(
    BuildContext context,
    List<InspectionRequest> requests,
  ) => <Widget>[
    for (final InspectionRequest request in requests)
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: RequestCard(
          request: request,
          onTap: () => context.push(
            AppRoutes.inspectorJobDetailPath(request.id),
          ),
        ),
      ),
  ];
}

/// The inspector's own profile: the same facts the buyer sees, so an inspector
/// can check what they are presenting to the market.
class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UserProfile? profile = ref.watch(authControllerProvider).value;

    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: <Widget>[
        Center(
          child: CircleAvatar(
            radius: 36,
            // substring(0, 1) would throw on an empty name; the database
            // requires a non-empty full_name, so this is defensive only — an
            // avatar is not worth a crash.
            child: Text(
              profile.fullName.isEmpty
                  ? '?'
                  : profile.fullName.substring(0, 1).toUpperCase(),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          profile.fullName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          profile.role.localizedName(context),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.xxl),
        DetailRow(label: l10n.detailEmail, value: profile.email),
        if (profile.phone case final String phone when phone.isNotEmpty)
          DetailRow(label: l10n.detailPhone, value: phone),
        DetailRow(
          label: l10n.detailServiceCity,
          value: profile.locationCity ?? l10n.profileCityNotSet,
        ),
        DetailRow(
          label: l10n.detailRating,
          value: profile.rating == 0
              ? l10n.detailNoRatingsYet
              : profile.rating.toStringAsFixed(2),
        ),
        const SizedBox(height: AppSpacing.xxl),
        FilledButton.tonalIcon(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout),
          label: Text(l10n.actionSignOut),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title, textAlign: TextAlign.center, style: text.titleMedium),
            if (body case final String value when value.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(value, textAlign: TextAlign.center, style: text.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// A load failure with a retry, rather than a blank screen or a permanent
/// error page — both lists here are pure reads, so retrying is always safe.
class _RetryMessage extends StatelessWidget {
  const _RetryMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.actionRetry),
            ),
          ],
        ),
      ),
    );
  }
}