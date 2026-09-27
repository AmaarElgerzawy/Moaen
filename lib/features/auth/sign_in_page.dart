import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/utils/validators.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_repository.dart';
import '../auth/user_profile.dart';
import '../auth/user_role_localizations.dart';

/// Sign in, or create an account.
///
/// Both modes live in one screen because they are two halves of a single
/// decision. Splitting them across two routes would add navigation state for no
/// gain, and the shared validation is identical.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _city = TextEditingController();

  bool _registering = false;
  bool _obscurePassword = true;
  UserRole _role = UserRole.client;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    _phone.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    AppLogger.instance.info(_registering ? 'submitting registration' : 'submitting sign-in');

    if (_registering) {
      await ref.read(authControllerProvider.notifier).signUp(
        email: _email.text,
        password: _password.text,
        fullName: _fullName.text,
        role: _role,
        phone: _phone.text,
        city: _city.text,
      );
    } else {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(email: _email.text, password: _password.text);
    }

    if (!mounted) return;
    final Object? rejection = ref.read(authControllerProvider).error;
    if (rejection != null) {
      AppLogger.instance.warn('authentication rejected', {'reason': '$rejection'});
    }
  }

  void _toggleMode() {
    setState(() {
      _registering = !_registering;
      _formKey.currentState?.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<UserProfile?> auth = ref.watch(authControllerProvider);
    final bool busy = auth.isLoading;
    final Object? authError = auth.error;
    final String? failure = switch (authError) {
      null => null,
      final AuthFailure authFailure => authFailure.message,
      // Deliberately not the raw error: an AuthException can carry a Supabase
      // message written for developers. The detail goes to the log instead.
      final Object _ => l10n.errorGeneric,
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      Env.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _registering
                          ? l10n.authRegisterSubtitle
                          : l10n.authSignInSubtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    if (_registering) ...<Widget>[
                      TextFormField(
                        controller: _fullName,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        textDirection: TextDirection.rtl,
                        decoration: InputDecoration(
                          labelText: l10n.fieldFullName,
                        ),
                        validator: Validators.fullName,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SegmentedButton<UserRole>(
                        segments: <ButtonSegment<UserRole>>[
                          ButtonSegment<UserRole>(
                            value: UserRole.client,
                            label: Text(
                              UserRole.client.localizedPrompt(context),
                            ),
                            icon: const Icon(Icons.directions_car_outlined),
                          ),
                          ButtonSegment<UserRole>(
                            value: UserRole.inspector,
                            label: Text(
                              UserRole.inspector.localizedPrompt(context),
                            ),
                            icon: const Icon(Icons.fact_check_outlined),
                          ),
                        ],
                        selected: <UserRole>{_role},
                        showSelectedIcon: false,
                        onSelectionChanged: (Set<UserRole> selection) =>
                            setState(() => _role = selection.first),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: l10n.fieldPhoneOptional,
                          helperText: l10n.helperPhone,
                        ),
                        validator: Validators.phone,
                      ),
                      if (_role == UserRole.inspector) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        TextFormField(
                          controller: _city,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: l10n.fieldServiceCity,
                            helperText: l10n.helperServiceCity,
                          ),
                          validator: Validators.city,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.email],
                      // Email and phone are LTR even in an Arabic layout:
                      // bidi reordering mangles a mixed address or number, and
                      // the caret jumping mid-string is worse than the field
                      // technically reading right-to-left.
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: l10n.fieldEmail),
                      validator: Validators.email,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.password],
                      onFieldSubmitted: (_) => busy ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: l10n.fieldPassword,
                        helperText: _registering
                            ? l10n.helperPasswordMinLength(
                                Validators.minPasswordLength,
                              )
                            : null,
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscurePassword
                              ? l10n.actionShowPassword
                              : l10n.actionHidePassword,
                        ),
                      ),
                      validator: Validators.password,
                    ),

                    if (failure != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      _ErrorBanner(message: failure),
                    ],

                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _registering
                                  ? l10n.actionCreateAccount
                                  : l10n.actionSignIn,
                            ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: busy ? null : _toggleMode,
                      child: Text(
                        _registering
                            ? l10n.linkAlreadyRegistered
                            : l10n.linkRegisterPrompt(Env.appName),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, color: colors.onErrorContainer, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
