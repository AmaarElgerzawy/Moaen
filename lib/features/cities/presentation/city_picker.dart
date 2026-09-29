import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
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
  });

  final String label;
  final String? helperText;
  final String? initialValue;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CitySheet(selected: field.value),
    );
    if (picked == null || picked == field.value) return;
    field.didChange(picked);
    onChanged?.call(picked);
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