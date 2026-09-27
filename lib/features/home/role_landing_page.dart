import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../auth/auth_controller.dart';
import '../auth/user_profile.dart';

/// The signed-in screen, chosen by role.
///
/// Phase 1 stops here. The screen exists to prove the objective that a session
/// resolves to the correct role-specific destination (O1) and to give the
/// sign-out path something to exercise; the marketplace itself is Phase 2.
class RoleLandingPage extends ConsumerWidget {
  const RoleLandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<UserProfile?> auth = ref.watch(authControllerProvider);
    final UserProfile? profile = auth.value;

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(Env.appName),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              CircleAvatar(
                radius: 36,
                backgroundImage: profile.avatarUrl == null
                    ? null
                    : NetworkImage(profile.avatarUrl!),
                child: profile.avatarUrl == null
                    ? Text(profile.fullName.substring(0, 1).toUpperCase())
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                profile.fullName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                profile.role.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              _DetailRow(label: 'Email', value: profile.email),
              if (profile.phone case final String phone when phone.isNotEmpty)
                _DetailRow(label: 'Phone', value: phone),
              if (profile.locationCity case final String city when city.isNotEmpty)
                _DetailRow(label: 'Service city', value: city),
              if (profile.role == UserRole.inspector)
                _DetailRow(
                  label: 'Rating',
                  value: profile.rating == 0
                      ? 'No ratings yet'
                      : profile.rating.toStringAsFixed(2),
                ),
              const SizedBox(height: 32),
              const _PhaseNotice(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 110, child: Text(label, style: text.bodySmall)),
          Expanded(
            child: Text(value, style: text.bodyMedium, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _PhaseNotice extends StatelessWidget {
  const _PhaseNotice();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Phase 1 complete', style: text.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Identity, roles and city scoping are live. Inspection requests, the '
          'job board and report entry arrive in Phase 2.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}
