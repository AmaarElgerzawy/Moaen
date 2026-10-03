import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../auth/user_profile.dart';
import '../auth/user_role_localizations.dart';

/// The generic signed-in screen: who you are, and the sign-out button.
///
/// Kept as the fallback destination for `/home` rather than deleted, because it is
/// the one screen that answers "who does the app think I am" for a session that has
/// no more specific destination — a profile whose role the build does not recognise,
/// or a direct navigation to `/home` from outside the redirect. Every role the app
/// *does* know is sent elsewhere by the redirect, so nothing routine reaches this.
///
/// It was Phase 1's proof that a session resolves to the right role (O1). That proof
/// now lives in the redirect, which is where the rule has to be to be worth anything
/// — but the screen still has a job, so it was not taken apart.
class RoleLandingPage extends ConsumerWidget {
  const RoleLandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
            tooltip: l10n.actionSignOut,
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: <Widget>[
              Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundImage: profile.avatarUrl == null
                      ? null
                      : NetworkImage(profile.avatarUrl!),
                  child: profile.avatarUrl == null
                      ? Text(
                          // substring(0, 1) would throw on an empty name. The
                          // database requires a non-empty full_name, so this is
                          // defensive only — but an avatar is not worth a crash.
                          profile.fullName.isEmpty
                              ? '?'
                              : profile.fullName
                                    .substring(0, 1)
                                    .toUpperCase(),
                        )
                      : null,
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
              _DetailRow(label: l10n.detailEmail, value: profile.email),
              if (profile.phone case final String phone when phone.isNotEmpty)
                _DetailRow(label: l10n.detailPhone, value: phone),
              if (profile.locationCity case final String city when city.isNotEmpty)
                _DetailRow(label: l10n.detailServiceCity, value: city),
              if (profile.role == UserRole.inspector)
                _DetailRow(
                  label: l10n.detailRating,
                  value: profile.rating == 0
                      ? l10n.detailNoRatingsYet
                      : profile.rating.toStringAsFixed(2),
                ),
              const SizedBox(height: AppSpacing.xxl),
              _PhaseNotice(title: l10n.phase1Title, body: l10n.phase1Body),
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
        // The label column is on the leading side, so it flips automatically
        // under RTL. Nothing here is written as "left" or "right".
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
  const _PhaseNotice({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: text.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(body, style: text.bodySmall),
      ],
    );
  }
}
