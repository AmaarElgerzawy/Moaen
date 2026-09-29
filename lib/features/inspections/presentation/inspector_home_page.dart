import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/auth_controller.dart';
import '../../auth/user_profile.dart';
import '../../auth/user_role_localizations.dart';
import '../../cities/presentation/city_picker.dart';
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
            caption: l10n.boardEmptyHint,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The dark board header: city title on the slate banner with the
            // live badge, matching the design's dark "my city" chrome while the
            // requests below sit on white cards.
            Container(
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.darkHeader,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.boardTitle(city),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _LiveBadge(label: l10n.boardLive),
                ],
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

/// The pulsing red "live" dot next to the board heading.
///
/// Static by design: the board already refreshes on pull, and an endlessly
/// animating dot would also make every `pumpAndSettle` in the widget tests
/// time out.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFFE5484D),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
        // Changing city is the one profile edit an inspector needs day-to-day:
        // the board is scoped to it, so a move or a typo from sign-up shows up
        // here instead of as a mysterious empty board.
        FilledButton.tonalIcon(
          onPressed: () => _editCity(context, ref),
          icon: const Icon(Icons.location_city_outlined),
          label: Text(l10n.profileEditCity),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.tonalIcon(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout),
          label: Text(l10n.actionSignOut),
        ),
      ],
    );
  }

  Future<void> _editCity(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UserProfile? profile = ref.read(authControllerProvider).value;
    if (profile == null) return;

    final String? city = await showDialog<String>(
      context: context,
      builder: (_) => _CityEditDialog(current: profile.locationCity),
    );
    if (city == null || !context.mounted) return;

    try {
      await ref.read(authControllerProvider.notifier).updateCity(city);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
      return;
    }

    // The board lives on the city the profile was saved with, so a change has
    // to refresh it or the header and the list would disagree.
    ref.invalidate(jobBoardProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.profileCityUpdated)));
  }
}

/// The change-service-city dialog: a canonical-city picker over the current
/// value, with Save enabled only once a different city is chosen.
class _CityEditDialog extends ConsumerStatefulWidget {
  const _CityEditDialog({this.current});

  final String? current;

  @override
  ConsumerState<_CityEditDialog> createState() => _CityEditDialogState();
}

class _CityEditDialogState extends ConsumerState<_CityEditDialog> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.profileEditCity),
      content: CityPicker(
        label: l10n.fieldServiceCity,
        initialValue: widget.current,
        // setState is what turns a selection into an enabled Save button: the
        // sheet updates the FormField on its own, but only a rebuild of this
        // dialog re-evaluates `_selected == null`.
        onChanged: (String city) => setState(() => _selected = city),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: Text(l10n.actionSave),
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
  const _CenteredMessage({required this.title, this.body, this.caption});

  final String title;
  final String? body;
  final String? caption;

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
            if (caption case final String value when value.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                value,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
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