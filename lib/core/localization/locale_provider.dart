import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The active locale.
///
/// Injected rather than hard-coded in `MoaenApp` for two reasons:
///
///  * A future language switcher becomes a matter of invalidating this provider,
///    not restructuring the widget tree.
///  * Behaviour tests can render in English and stay readable. The widget tests
///    in `auth_flow_test.dart` are about the routing guard and form validation,
///    not about translation — pointing their finders at Arabic text would couple
///    them to wording that is expected to change. The Arabic and RTL behaviour
///    has its own coverage in `test/core/localization_test.dart`.
///
/// Arabic is both the default and the fallback, per D7.
final localeProvider = Provider<Locale>((Ref ref) => const Locale('ar'));
