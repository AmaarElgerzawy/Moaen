import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import 'commission.dart';
import 'commission_repository.dart';

final commissionRepositoryProvider = Provider<CommissionRepository>(
  (Ref ref) => CommissionRepository(ref.watch(supabaseClientProvider)),
);

/// The platform commission, for any screen that quotes a price.
///
/// Watches [authControllerProvider] for its invalidation side effect, not its value:
/// a sign-out followed by a different sign-in would otherwise leave the previous
/// session's commission cached on a form that has not been rebuilt from scratch, and
/// the next buyer would be quoted the wrong fee for the length of one session's cache
/// lifetime. The read itself needs no user id — every authenticated account may read
/// the singleton, which is what lets a buyer's create form and an inspector's offer
/// sheet both depend on this.
final commissionProvider = FutureProvider<Commission>((Ref ref) async {
  ref.watch(authControllerProvider);
  return ref.watch(commissionRepositoryProvider).commission();
});