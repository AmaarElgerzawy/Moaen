import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/saudi_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/auth_controller.dart';
import '../application/inspection_controller.dart';
import '../domain/inspection_draft.dart';
import '../domain/inspection_request.dart';
import 'accept_request.dart';
import 'widgets/design_widgets.dart';

/// Screen 3: the inspector's market — every pending request in their city.
///
/// RTL, because the reference's `.sc` is an `.rtl` container, and pushed: the
/// reference gives this screen no bottom bar, so it is a route rather than a tab.
/// The way in is the `عرض كل` link on the inspector's home.
///
/// The board itself is not filtered, sorted or paginated here beyond what
/// [jobBoardProvider] already does — the query is the RLS policy plus the city
/// comparison, and it returns the newest first. A market that re-sorted its own
/// listings would make two inspectors see different orders for the same moment,
/// which is exactly the race the `48 ساعة` window is supposed to make visible
/// rather than hide.
class InspectorMarketPage extends ConsumerWidget {
  const InspectorMarketPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionRequest>> board = ref.watch(
      jobBoardProvider,
    );
    // The header pill is the *inspector's* city, not the request's, and not a
    // filter: the board is already scoped to it server-side, so showing anything
    // else would be a control that does not change the list.
    final String city = ref.watch(authControllerProvider).value?.locationCity ?? '';

    return Scaffold(
      body: RtlRegion(
        child: Column(
          children: <Widget>[
            DarkHeader(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // 21px, not the 19px the other five headers use. The
                        // reference sets it inline on this one title and on no
                        // other, and it is the only difference between this
                        // screen's header and the inspector's.
                        Text(l10n.marketTitle, style: AppText.onDark(21)),
                        const SizedBox(height: 3),
                        Text(
                          l10n.marketSubtitle,
                          style: AppText.secondary(
                            12,
                            color: AppColors.onDarkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppPill(
                    label: l10n.marketLocation(city),
                    tone: PillTone.onDark,
                    fontSize: 12,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                // White, where Screen 2 keeps the page colour. The reference
                // overrides `.body`'s `#F8FAFC` on this screen specifically,
                // because the request cards are white and a gray page behind
                // white cards would put a second edge around each one.
                color: AppColors.surface,
                child: board.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (_, _) => Center(
                    child: DesignRetry(
                      message: l10n.tabLoadError,
                      actionLabel: l10n.actionRetry,
                      onRetry: () => ref.invalidate(jobBoardProvider),
                    ),
                  ),
                  data: (List<InspectionRequest> rows) {
                    if (rows.isEmpty) {
                      return Center(
                        child: DesignEmpty(
                          title: l10n.marketEmptyTitle,
                          body: l10n.marketEmptyBody(city),
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(jobBoardProvider);
                        await ref.read(jobBoardProvider.future);
                      },
                      child: ListView.separated(
                        // Always scrollable so pull-to-refresh works on the empty
                        // case too, which is the one an inspector hits most.
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AppSpacing.inset),
                        itemCount: rows.length + 1,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.md),
                        itemBuilder: (BuildContext context, int index) {
                          if (index == 0) {
                            return _BoardHeading(
                              title: l10n.marketBoardTitle,
                              live: l10n.marketLive,
                            );
                          }
                          return _RequestListing(
                            request: rows[index - 1],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `الطلبات المعروضة حالياً` and, at the other end, `🔴 تحديث مباشر`.
///
/// The heading is a list header, so it scrolls with the list rather than sitting
/// above it. The reference has it inside the scrolling `.body`, and pinning it
/// would be the one change on this screen that moves a thing.
class _BoardHeading extends StatelessWidget {
  const _BoardHeading({required this.title, required this.live});

  final String title;
  final String live;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: AppText.title(15).copyWith(height: 1.5),
          ),
        ),
        // Not a [LiveBadge]: the reference's own text carries the red dot as an
        // emoji, and a painted circle beside it would show two red dots.
        Text(
          live,
          style: AppText.title(11, color: AppColors.live),
        ),
      ],
    );
  }
}

/// One `.req`: the car, the fee, the seller strip, and the accept button.
class _RequestListing extends ConsumerWidget {
  const _RequestListing({required this.request});

  final InspectionRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SaudiFormat format = SaudiFormat(
      Localizations.localeOf(context).toString(),
    );
    final DateTime now = DateTime.now();
    // The controller's state is watched for the loading flag only, not for its
    // error. The write's failure is reported once, by the snackbar
    // [confirmAccept] raises, because that state is global to every card: reading
    // `error` here would print the same red sentence under all of them the moment
    // one accept failed.
    final bool busy = ref.watch(
      inspectionRequestControllerProvider.select(
        (AsyncValue<void> state) => state.isLoading,
      ),
    );

    return DesignCard(
      padding: const EdgeInsets.all(AppSpacing.inset),
      borderColor: AppColors.marketBorder,
      // 20dp, not the 18dp every other card uses. The reference sizes the
      // market's listings larger than the rest of the app's cards, and they are
      // the one card a buyer-facing inspector is choosing between.
      borderRadius: AppRadius.cardLarge,
      // The card opens the job, the button takes it. The reference draws one
      // card with one button and no navigation, but a listing that names a car, a
      // district, a buyer and a fee and cannot be opened is a card that reads as
      // a link — so the rest of the card is the link, and the one thing that
      // commits to a buyer stays behind the button.
      onTap: () => context.pushNamed(
        'inspectorJob',
        pathParameters: <String, String>{'id': request.id},
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(request.carDescription, style: AppText.title(20)),
                    const SizedBox(height: 3),
                    Text(
                      // Two halves, composed rather than stored as one string:
                      // the reference writes `📍 الدمام | طالب الفحص: سعود` on the
                      // first listing and `📍 الدمام - حي الشاطئ` on the second,
                      // because the first sells the identity of the person
                      // asking and the second sells where the car is. Both are
                      // the same two parts in a different arrangement, so the
                      // buyer name is appended when there is one.
                      _locationLine(l10n),
                      style: AppText.secondary(11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FeeBadge(
                // `+150` with no currency: the caption underneath already says
                // `أتعاب المعاين`, and the design's `.fee` box is narrow enough
                // that a third line would wrap it.
                amount:
                    '+${CostEstimate.amount(CostEstimate.defaultInspectorFee)}',
                caption: l10n.marketFeeLabel,
              ),
            ],
          ),
          InfoStrip(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.row,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.marketOwner(
                      (request.sellerName?.trim().isNotEmpty ?? false)
                          ? request.sellerName!
                          : l10n.marketOwnerUnknown,
                    ),
                    style: AppText.secondary(12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  l10n.marketPosted(
                    format.relative(request.createdAt, now),
                  ),
                  style: AppText.secondary(12),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            // `.btn k` — the dark button, not the green one. The reference makes
            // every other primary action in the app green and makes *this* one
            // dark, because accepting a job is a commitment rather than a
            // navigation. Reproduced rather than normalised.
            style: AppTheme.blackButton,
            onPressed: busy
                ? null
                : () => confirmAccept(context, ref, request),
            child: Text(l10n.marketAccept),
          ),
        ],
      ),
    );
  }

  /// `📍 {city} | طالب الفحص: {name}`, or `📍 {city}` when the request predates
  /// the frozen buyer name.
  ///
  /// The buyer name is a frozen copy on the row rather than a join, because RLS
  /// lets an inspector read only their own profile row — see the note in
  /// `InspectionRequest.clientName`. A request that predates the column has a
  /// null there, and the line falls back to the city alone rather than printing
  /// `طالب الفحص: null`.
  String _locationLine(AppLocalizations l10n) {
    final String base = l10n.marketLocation(request.city);
    final String? buyer = request.clientName;
    if (buyer == null || buyer.trim().isEmpty) return base;
    return '$base | ${l10n.marketBuyer(buyer)}';
  }
}
