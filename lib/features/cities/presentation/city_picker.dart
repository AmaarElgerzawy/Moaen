import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inspections/presentation/widgets/design_widgets.dart';
import '../application/city_controller.dart';
import '../data/city_repository.dart';

/// A picker over the canonical city list, in place of a free-text city field.
///
/// A `FormField<String>`, so the three forms that take a city — sign-up, create
/// request and the profile editor — keep their `Form` validation: an empty
/// value can be flagged with the same `validator` a text field used. The value
/// is the Arabic city name from the `cities` table, the exact string the job
/// board's RLS comparison is written against.
///
/// Tapping the field opens a searchable sheet with the whole list, loaded from
/// `citiesProvider`. Load failure is surfaced inside the sheet with a retry
/// rather than as a broken-looking field, because it is exactly the kind of
/// offline moment the rest of this screen has to survive.
class CityPicker extends ConsumerWidget {
  const CityPicker({
    super.key,
    required this.label,
    this.helperText,
    this.initialValue,
    this.validator,
    this.onChanged,
    this.design = false,
  });

  final String label;
  final String? helperText;
  final String? initialValue;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  /// True renders the reference's `.fld v` — a white field with the value inside
  /// and a `⌄` chevron, no floating label.
  ///
  /// Two shapes rather than one styled with parameters, because the two belong to
  /// two different design systems: the Material one is the app's sign-up form,
  /// and this one is the Moaayen screens, where no field anywhere has a floating
  /// label. A single widget with a flag would end up with an `if` in its build
  /// and a decoration that is half of each.
  final bool design;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (design) {
      return _DesignCityPicker(
        label: label,
        initialValue: initialValue,
        validator: validator,
        onChanged: onChanged,
      );
    }
    return FormField<String>(
      initialValue: initialValue,
      validator: validator,
      builder: (FormFieldState<String> field) => InkWell(
        onTap: () => _openSheet(context, ref, field),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            helperText: helperText,
            errorText: field.errorText,
            // An explicit arrow keeps the affordance honest: a field that opens
            // a sheet instead of a keyboard should not look like it expects
            // typing.
            suffixIcon: const Icon(Icons.expand_more),
            // Reserved like the regular fields (see `_Field` in the create
            // form), so the row below does not jump when a picker goes red.
            helperMaxLines: 3,
          ),
          child: Text(
            field.value ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    WidgetRef ref,
    FormFieldState<String> field,
  ) async {
    final String? picked = await showCitySheet(context, selected: field.value);
    if (picked == null || picked == field.value) return;
    field.didChange(picked);
    onChanged?.call(picked);
  }
}

/// Opens the searchable city list as a sheet, and returns the chosen city's
/// Arabic name — the string RLS compares against — or null if it was dismissed.
///
/// The single way into the sheet: both pickers call it, and so does the
/// inspector's profile editor, which is the point of having it.
///
/// The editor opens the list rather than a [CityPicker]. A sheet whose content
/// is a field that opens a *second* sheet costs two taps and two animations to
/// choose one city, and it lies about what is on screen — the first sheet shows
/// a form field, not a list. It also lays out badly: a bottom sheet hands its
/// child the full screen height as a maximum, so a column with the default
/// `MainAxisSize.max` stretches to all of it and centres the lone field halfway
/// down the display, unreachable without scrolling a sheet that is not
/// scrollable.
Future<String?> showCitySheet(BuildContext context, {String? selected}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CitySheet(selected: selected),
    );

/// The reference's version of the field: a [SelectField] holding the value, with
/// the error rendered beneath it rather than inside it.
///
/// The error sits below rather than overlaid because the reference's `.fld` has a
/// fixed 48dp height and there is nowhere inside it to put a sentence — and
/// because a field that grows the moment it goes red moves every field under it,
/// which on a form this long means the buyer loses their place.
class _DesignCityPicker extends ConsumerWidget {
  const _DesignCityPicker({
    required this.label,
    required this.initialValue,
    required this.validator,
    required this.onChanged,
  });

  final String label;

  /// The pre-selected city.
  ///
  /// Carried into the [FormField] rather than read from the field, because a
  /// `FormField` that is told its validator but not its initial value validates
  /// an empty string it was never meant to hold — which is how the city field
  /// came to reject a city that had in fact been chosen.
  final String? initialValue;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  /// Opens the shared sheet and folds the result back into [field].
  ///
  /// Repeated from [CityPicker] rather than shared, because the two widgets have
  /// nothing else in common: one returns a `FormField` for the sign-up form, the
  /// other a `SelectField` for the reference. A shared helper would need both
  /// widgets' types as parameters and return whichever of them the caller wanted,
  /// which is a function that dispatches on a flag — the thing this pair exists to
  /// avoid.
  Future<void> _pick(
    BuildContext context,
    FormFieldState<String> field,
  ) async {
    final String? picked = await showCitySheet(context, selected: field.value);
    if (picked == null || picked == field.value) return;
    field.didChange(picked);
    onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FormField<String>(
      initialValue: initialValue,
      validator: validator,
      builder: (FormFieldState<String> field) => Column(
        // Shrink-wrapped: the field is a 48dp row, and a column that took the
        // maximum height available would put it in the middle of whatever box it
        // was dropped into — a bottom sheet, for one, whose maximum is the whole
        // screen.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SelectField(
            label: label,
            value: field.value ?? '',
            muted: field.value == null || field.value!.trim().isEmpty,
            onTap: () => _pick(context, field),
          ),
          if (field.errorText case final String error)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                error,
                style: const TextStyle(fontSize: 11, color: AppColors.live),
              ),
            ),
        ],
      ),
    );
  }
}

/// The searchable list behind the field.
///
/// Separated from [CityPicker] so the async load state renders inside the sheet
/// — a loading spinner in the modal, not wedged between two form fields.
class _CitySheet extends ConsumerStatefulWidget {
  const _CitySheet({this.selected});

  final String? selected;

  @override
  ConsumerState<_CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends ConsumerState<_CitySheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<City>> cities = ref.watch(citiesProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Text(
                  l10n.cityPickerTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: TextField(
                  controller: _search,
                  onChanged: (String value) => setState(() => _query = value.trim()),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.cityPickerSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: cities.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => _LoadFailed(
                    onRetry: () => ref.invalidate(citiesProvider),
                  ),
                  data: (List<City> all) {
                    final List<City> filtered = _query.isEmpty
                        ? all
                        : <City>[
                            for (final City city in all)
                              if (city.nameAr.contains(_query) ||
                                  city.nameEn.toLowerCase().contains(_query.toLowerCase()))
                                city,
                          ];
                    if (filtered.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Center(child: Text(l10n.cityPickerEmpty)),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (BuildContext context, int index) {
                        final City city = filtered[index];
                        final bool selected = city.nameAr == widget.selected;
                        return ListTile(
                          leading: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.location_city_outlined,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          title: Text(city.nameAr),
                          selected: selected,
                          onTap: () => Navigator.of(context).pop(city.nameAr),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(l10n.cityPickerLoadError, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.actionRetry),
          ),
        ],
      ),
    );
  }
}