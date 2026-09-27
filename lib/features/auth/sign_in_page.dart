import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/logging/app_logger.dart';
import '../../shared/utils/validators.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_repository.dart';
import '../auth/user_profile.dart';

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
    final AsyncValue<UserProfile?> auth = ref.watch(authControllerProvider);
    final bool busy = auth.isLoading;
    final Object? authError = auth.error;
    final String? failure = switch (authError) {
      null => null,
      final AuthFailure authFailure => authFailure.message,
      final Object _ => 'Something went wrong. Please try again.',
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                    const SizedBox(height: 8),
                    Text(
                      _registering
                          ? 'Create an account to request or provide an inspection.'
                          : 'Sign in to continue.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 28),

                    if (_registering) ...<Widget>[
                      TextFormField(
                        controller: _fullName,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          border: OutlineInputBorder(),
                        ),
                        validator: Validators.fullName,
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<UserRole>(
                        segments: const <ButtonSegment<UserRole>>[
                          ButtonSegment<UserRole>(
                            value: UserRole.client,
                            label: Text('I am buying'),
                            icon: Icon(Icons.directions_car_outlined),
                          ),
                          ButtonSegment<UserRole>(
                            value: UserRole.inspector,
                            label: Text('I inspect'),
                            icon: Icon(Icons.fact_check_outlined),
                          ),
                        ],
                        selected: <UserRole>{_role},
                        onSelectionChanged: (Set<UserRole> selection) =>
                            setState(() => _role = selection.first),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Phone (optional)',
                          helperText: 'Used to contact you about an inspection.',
                          border: OutlineInputBorder(),
                        ),
                        validator: Validators.phone,
                      ),
                      if (_role == UserRole.inspector) ...<Widget>[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _city,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Service city',
                            helperText:
                                'You will see inspection requests from this city only.',
                            border: OutlineInputBorder(),
                          ),
                          validator: Validators.city,
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: Validators.email,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.password],
                      onFieldSubmitted: (_) => busy ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: _registering
                            ? 'At least ${Validators.minPasswordLength} characters.'
                            : null,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                        ),
                      ),
                      validator: Validators.password,
                    ),

                    if (failure != null) ...<Widget>[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: failure),
                    ],

                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_registering ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy ? null : _toggleMode,
                      child: Text(
                        _registering
                            ? 'Already have an account? Sign in'
                            : 'New to ${Env.appName}? Create an account',
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, color: colors.onErrorContainer, size: 20),
          const SizedBox(width: 8),
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
