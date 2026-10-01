import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_request.dart';

/// Asks for confirmation, then takes [request].
///
/// One function, not two. The market's listing and the job detail both offer to
/// take a request, and they must not disagree about what that costs: the
/// reference draws the market's button as a plain dark `.btn k` with no dialog
/// drawn over it, but the act is identical — an inspector commits to a buyer and
/// to a 48-hour clock — and an inspector who has already accepted one request
/// should not find that a second route skips the question. The confirmation is a
/// safety property, not a design element, so it is not the design's to decide.
///
/// Returns whether the request is now this inspector's. The caller uses it to
/// decide whether to navigate somewhere that assumes a job: the detail page
/// stays put and refetches, the market's listing just refetches.
Future<bool> confirmAccept(
  BuildContext context,
  WidgetRef ref,
  InspectionRequest request,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(l10n.acceptConfirmTitle),
      content: Text(l10n.acceptConfirmBody(request.city)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.actionKeep),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.actionAccept),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;

  try {
    await ref.read(inspectionRequestControllerProvider.notifier).accept(request.id);
  } on InspectionFailure catch (failure) {
    if (!context.mounted) return false;
    _showMessage(context, failure.message);
    return false;
  } on Object {
    if (!context.mounted) return false;
    _showMessage(context, l10n.errorGeneric);
    return false;
  }

  if (!context.mounted) return false;
  // A lost race is the one failure an inspector will actually hit: two
  // inspectors, one request, and the database decides. The database's message is
  // the only one that tells this inspector what happened.
  _showMessage(context, l10n.inspectorAccepted);
  return true;
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
