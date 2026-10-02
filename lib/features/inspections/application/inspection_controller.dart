import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/auth_controller.dart';
import '../../auth/user_profile.dart';
import '../data/centre_repository.dart';
import '../data/inspection_repository.dart';
import '../data/location_surface.dart';
import '../data/media_repository.dart';
import '../data/photo_picker.dart';
import '../data/report_repository.dart';
import '../domain/custom_centre.dart';
import '../domain/inspection_centre.dart';
import '../domain/inspection_draft.dart';
import '../domain/inspection_report.dart';
import '../domain/inspection_request.dart';
import '../domain/report_media.dart';

final inspectionRepositoryProvider = Provider<InspectionRepository>(
  (Ref ref) => InspectionRepository(ref.watch(supabaseClientProvider)),
);

/// The signed-in buyer's requests, newest first.
///
/// Watches [authControllerProvider] for its invalidation side effect, not its
/// value. Without that, a sign-out followed by a different sign-in would show
/// the previous buyer's requests on screen, because this provider would still be
/// holding its cached value — a privacy bug that no single test would catch,
/// since each one starts signed in.
///
/// The read takes no user id because RLS decides visibility; see
/// [InspectionRepository.listForClient].
final myRequestsProvider = FutureProvider<List<InspectionRequest>>((
  Ref ref,
) async {
  ref.watch(authControllerProvider);
  return ref.watch(inspectionRepositoryProvider).listForClient();
});

/// The request the dashboard leads with, or null when the buyer has none.
///
/// A separate provider from [myRequestsProvider] because the dashboard needs one
/// row, and fetching the whole history to show the newest is the kind of request
/// that grows without anyone noticing.
final dashboardRequestProvider = FutureProvider<InspectionRequest?>((Ref ref) {
  ref.watch(authControllerProvider);
  return ref.watch(inspectionRepositoryProvider).latestForClient();
});

/// The inspector's job board: pending requests in their city, newest first.
///
/// Watches [authControllerProvider] the same way [myRequestsProvider] does, so a
/// sign-out cannot leave the previous inspector's board on screen. It takes no
/// user id because RLS decides which city's requests are visible; see
/// [InspectionRepository.listBoard].
final jobBoardProvider = FutureProvider<List<InspectionRequest>>((Ref ref) async {
  ref.watch(authControllerProvider);
  return ref.watch(inspectionRepositoryProvider).listBoard();
});

/// The signed-in inspector's own jobs, newest first.
///
/// This one has to wait for the profile: the repository narrows on
/// `inspector_id`, because the participant RLS policy cannot tell which side of
/// a request the caller was. See [InspectionRepository.listForInspector].
final myJobsProvider = FutureProvider<List<InspectionRequest>>((Ref ref) async {
  final UserProfile? profile = await ref.watch(authControllerProvider.future);
  if (profile == null) return const <InspectionRequest>[];
  return ref.watch(inspectionRepositoryProvider).listForInspector(profile.id);
});

/// One request, as the inspector's detail page sees it.
///
/// A family rather than a cache hit off a list, because the inspector can reach
/// a job from either the board or their jobs list, and neither list reliably
/// holds a row that is now on the *other* list (accepting moves a request
/// between them). Fetching by id also lets an action invalidate just this row so
/// the page shows the post-transition status without refetching both lists.
final inspectorJobProvider =
    FutureProvider.family<InspectionRequest, String>((Ref ref, String id) {
      ref.watch(authControllerProvider);
      return ref.watch(inspectionRepositoryProvider).byId(id);
    });

/// The signed-in user's display name, for the copy frozen onto a request.
///
/// Returns null rather than a placeholder. A missing name is not a reason to write
/// "عميل" onto a record an inspector reads before travelling to a car, and the
/// column is nullable precisely so that "not recorded" is expressible.
String? _displayName(UserProfile? profile) {
  final String name = profile?.fullName.trim() ?? '';
  return name.isEmpty ? null : name;
}

/// Writes: create and cancel.
///
/// Separate from the read providers because these are user-initiated and want a
/// loading state of their own — [myRequestsProvider] being `AsyncLoading` during
/// a cancel would blank the list the user is looking at.
class InspectionRequestController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Creates a request, returning it so the caller can show the assigned
  /// reference.
  ///
  /// Invalidates the read providers on success rather than optimistically
  /// inserting the new row: the database is what assigns `reference_no` and
  /// decides `created_at`, so the row that comes back is the only truthful one.
  ///
  /// Rethrows so the caller can react to a failure, while also recording it in
  /// [state] so a rebuild keeps showing the error rather than silently clearing
  /// it. A caller that only reads [state] is a supported way to use this.
  Future<InspectionRequest> create(InspectionDraft draft) async {
    state = const AsyncLoading();
    try {
      // The buyer's name is read from the profile here rather than taken from the
      // draft, so the form cannot be made to file a request under someone else's
      // name. The draft keeps a `clientName` field for tests and for the rare
      // caller that already has the profile, but a form is not where that
      // decision should be trusted from.
      final UserProfile? profile = await ref.read(authControllerProvider.future);
      if (profile == null) {
        throw StateError('inspection write attempted with no signed-in user');
      }
      final InspectionRequest created = await ref
          .read(inspectionRepositoryProvider)
          .create(
            draft.copyWith(clientName: _displayName(profile) ?? draft.clientName),
            profile.id,
          );
      state = const AsyncData(null);
      ref.invalidate(myRequestsProvider);
      ref.invalidate(dashboardRequestProvider);
      return created;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  /// Cancels a request.
  ///
  /// Throws on failure, like [create]. The earlier version recorded the error in
  /// [state] and returned normally, which pushed every caller into reading the
  /// state back afterwards to find out what happened — and that read can return
  /// a rebuilt notifier's initial value rather than the failure.
  Future<void> cancel(String id) async {
    state = const AsyncLoading();
    try {
      await ref.read(inspectionRepositoryProvider).cancel(id);
      state = const AsyncData(null);
      ref.invalidate(myRequestsProvider);
      ref.invalidate(dashboardRequestProvider);
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  /// The three inspector status writes share one shape: run the transition,
  /// then let every index that can show the request refetch so its new status
  /// is everywhere immediately. Invalidation rather than optimistic updates,
  /// for the same reason as [create] — the trigger is what decides the
  /// transition is legal, so the database's answer is the only truthful one.
  ///
  /// Throws on failure, like [cancel], recording the error in [state] as well.
  Future<void> _transition(
    Future<void> Function() write,
    String id,
  ) async {
    state = const AsyncLoading();
    try {
      await write();
      state = const AsyncData(null);
      ref.invalidate(jobBoardProvider);
      ref.invalidate(myJobsProvider);
      ref.invalidate(inspectorJobProvider(id));
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  /// Claims a pending request.
  ///
  /// Not a [_transition] call, because the claim is the one inspector write that
  /// has to carry something the database cannot derive: the inspector's own name,
  /// frozen so the A4 report can name them later. `public.users` RLS gives a buyer
  /// read access to their own row only, so the report the buyer is handed is
  /// exactly the document that cannot look the name up — see
  /// `InspectionRequest.inspectorName`.
  ///
  /// The profile is read here rather than in the repository, matching [create]: a
  /// form is not where that decision should be trusted from, and the trigger in
  /// migration 0009 is the authority on which writes are legal anyway.
  ///
  /// Invalidates the shared indexes plus this one row, so the board drops it and
  /// the jobs list picks it up.
  Future<void> accept(String id) async {
    state = const AsyncLoading();
    try {
      final String? name = _displayName(await ref.read(authControllerProvider.future));
      await ref.read(inspectionRepositoryProvider).accept(id, inspectorName: name);
      state = const AsyncData(null);
      ref.invalidate(jobBoardProvider);
      ref.invalidate(myJobsProvider);
      ref.invalidate(inspectorJobProvider(id));
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> start(String id) {
    return _transition(
      () => ref.read(inspectionRepositoryProvider).start(id),
      id,
    );
  }

  Future<void> complete(String id) {
    return _transition(
      () => ref.read(inspectionRepositoryProvider).complete(id),
      id,
    );
  }

  /// Books the centre and appointment for an accepted job.
  ///
  /// Not a `_transition` because it changes no status, and it invalidates a
  /// different set: the buyer's dashboard and their request list both gain a
  /// centre name, a fee and a time from this write, so those are the rows that
  /// must refetch. Invalidating the inspector's own indexes too would be harmless
  /// but would make the booking form re-read a list the inspector is looking at.
  ///
  /// [customCentre] is the unlisted-centre case and [proofPhoto] its evidence.
  /// They are separate parameters because they are separate facts: the name and
  /// location are the booking, while the photograph is the inspector standing
  /// behind the claim that a shop is real. The name may be one the buyer suggested;
  /// the photograph is always the inspector's own, and migration 0010's trigger
  /// refuses to let anyone else write it.
  Future<void> book(
    String id, {
    required String centreName,
    required double fee,
    required DateTime appointmentAt,
    CustomCentre? customCentre,
    XFile? proofPhoto,
  }) async {
    state = const AsyncLoading();
    try {
      // Uploaded here rather than by the form, so the object and the booking land
      // as one outcome: the inspector gets a single failure for the whole booking
      // instead of a confirmed appointment citing a photograph that never
      // uploaded. An approved centre skips the upload — it has no proof to supply,
      // and `customCentre` is null.
      final CustomCentre? booked = proofPhoto == null || customCentre == null
          ? customCentre
          : customCentre.copyWith(
              proofPhotoPath: await ref
                  .read(mediaRepositoryProvider)
                  .uploadCentreProof(inspectionId: id, file: proofPhoto),
            );
      await ref.read(inspectionRepositoryProvider).book(
            id,
            centreName: centreName,
            fee: fee,
            appointmentAt: appointmentAt,
            customCentre: booked,
          );
      state = const AsyncData(null);
      ref.invalidate(myRequestsProvider);
      ref.invalidate(dashboardRequestProvider);
      ref.invalidate(inspectorJobProvider(id));
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  /// Records the buyer's approval of the invoice.
  ///
  /// The write the design's `الموافقة على العرض وتأكيد الطلب` button makes, and
  /// the one the buyer's dashboard has the most interest in showing the result of:
  /// [dashboardRequestProvider] is invalidated so the button's success state and
  /// the step timeline both reflect it on the next frame.
  Future<void> approveInvoice(String id) async {
    state = const AsyncLoading();
    try {
      await ref.read(inspectionRepositoryProvider).approveInvoice(id);
      state = const AsyncData(null);
      ref.invalidate(dashboardRequestProvider);
      ref.invalidate(myRequestsProvider);
      ref.invalidate(inspectorJobProvider(id));
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

final inspectionRequestControllerProvider =
    NotifierProvider<InspectionRequestController, AsyncValue<void>>(
      InspectionRequestController.new,
    );

// ---------------------------------------------------------------------------
// Centres
// ---------------------------------------------------------------------------

final centreRepositoryProvider = Provider<CentreRepository>(
  (Ref ref) => CentreRepository(ref.watch(supabaseClientProvider)),
);

/// The approved centres in one city, for the booking dropdown.
///
/// Takes the city rather than reading the profile itself, because the caller is
/// the screen that already has the request and its city — and a centre is booked
/// inside the request's city, not the inspector's. A keying rule can only be
/// written one way, and this way makes the mismatch visible in the call.
final centresInCityProvider = FutureProvider.family<List<InspectionCentre>, String>(
  (Ref ref, String city) {
    ref.watch(authControllerProvider);
    return ref.watch(centreRepositoryProvider).listForCity(city);
  },
);

/// The map a custom centre's location is picked on, behind a provider.
///
/// The same seam [photoPickerProvider] is, for the same reason: `flutter_map`
/// fetches tiles over HTTP and `flutter test` has no HTTP stack, so a test
/// rendering the real map fails on tile requests that have nothing to do with what
/// it is asserting. Override this with a builder that reports a fixed point and the
/// whole pick-and-record path runs with no network.
final locationSurfaceProvider = Provider<LocationSurfaceBuilder>(
  (Ref ref) => systemLocationSurface,
);

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

final mediaRepositoryProvider = Provider<MediaRepository>(
  (Ref ref) => MediaRepository(ref.watch(supabaseClientProvider)),
);

/// The device's photo library, behind a provider.
///
/// The seam that lets the report-entry form's photo control be driven in a widget
/// test: override it with a fake that returns a file, and the whole
/// pick-then-upload path runs without a gallery. See [PhotoPicker].
final photoPickerProvider = Provider<PhotoPicker>(
  (Ref ref) => const SystemPhotoPicker(),
);

/// The photos already attached to one report, keyed by its report id.
///
/// Separate from [reportBundleProvider] because the A4 report page has no use for
/// them: the design prints four caption boxes under
/// `المرفقات والصور الميدانية الموثقة` rather than thumbnails, so loading signed
/// URLs there would mint a token per photo for a page that shows none of them.
/// Only Screen 5 reads this.
final reportMediaProvider = FutureProvider.family<List<ReportMedia>, String>((
  Ref ref,
  String reportId,
) {
  ref.watch(authControllerProvider);
  return ref.watch(mediaRepositoryProvider).listForReport(reportId);
});

final reportRepositoryProvider = Provider<ReportRepository>(
  (Ref ref) => ReportRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(inspectionRepositoryProvider),
  ),
);

/// The full A4 report for one inspection, or null if none has been started.
///
/// A `FutureProvider.family` over [ReportRepository.load] rather than a cache hit
/// off the jobs list, for the reason [inspectorJobProvider] is: the report is
/// reached from the buyer's dashboard, the inspector's job detail and the reports
/// tab, and a fetch-by-id means a certifying action invalidates one document
/// rather than every list that happens to mention it.
final reportBundleProvider = FutureProvider.family<ReportBundle?, String>((
  Ref ref,
  String inspectionId,
) {
  ref.watch(authControllerProvider);
  return ref.watch(reportRepositoryProvider).load(inspectionId);
});

/// The buyer's issued reports, newest first.
///
/// Derived from [myRequestsProvider] rather than queried by user id, because
/// `inspection_reports` has no `client_id` — see
/// [ReportRepository.listForInspections]. Chaining off the request list also means
/// the reports tab and the requests tab can never disagree about which requests
/// exist.
final myReportsProvider = FutureProvider<List<InspectionReport>>((Ref ref) async {
  final List<InspectionRequest> requests =
      await ref.watch(myRequestsProvider.future);
  final List<InspectionReport> reports = await ref
      .watch(reportRepositoryProvider)
      .listForInspections(<String>[
        for (final InspectionRequest request in requests) request.id,
      ]);
  return reports;
});

/// Writes the report: the header row, its sectors, its chips, its photos, and the
/// issue.
///
/// One notifier for the five writes rather than five, because the design's issue
/// button performs all of them in sequence and a form that could issue a document
/// with its sectors missing is a document that is wrong. [issue] is the only
/// public method, and it does the writes in order.
class ReportController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Saves [draft] and [photos], then certifies.
  ///
  /// The order matters and is not reversed for speed: a report becomes citable at
  /// the moment of `certify`, and the buyer's reports tab and the A4's seal both
  /// key off that timestamp. Certifying first would publish a document whose
  /// sectors, chips and photos are still the previous draft's — or absent, on a
  /// first issue.
  ///
  /// [photos] are the files the inspector picked on the form, held until now.
  /// They are uploaded here rather than when picked because `report_media` is
  /// append-only and keyed by `report_id`, and the report row does not exist until
  /// [ReportRepository.upsert] has run. Uploading at pick time would mean either
  /// creating the header row for a form the inspector may abandon, or holding
  /// photos with no destination row to attach them to.
  ///
  /// Throws on failure and records it in [state], like the request writes, so a
  /// caller can either await the throw or read the state back.
  Future<void> issue(ReportDraft draft, {List<XFile> photos = const <XFile>[]}) async {
    state = const AsyncLoading();
    try {
      final ReportRepository repository = ref.read(reportRepositoryProvider);
      final String reportId = await repository.upsert(draft);
      await repository.replaceSections(reportId, draft.sections);
      await repository.replaceParts(reportId, draft.parts);
      if (photos.isNotEmpty) {
        await ref
            .read(mediaRepositoryProvider)
            .attachAll(
              inspectionId: draft.inspectionId,
              reportId: reportId,
              files: photos,
            );
      }
      await repository.certify(reportId);
      state = const AsyncData(null);
      ref.invalidate(reportBundleProvider(draft.inspectionId));
      ref.invalidate(reportMediaProvider(reportId));
      ref.invalidate(myReportsProvider);
      ref.invalidate(inspectionRequestControllerProvider);
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

final reportControllerProvider = NotifierProvider<ReportController, AsyncValue<void>>(
  ReportController.new,
);
