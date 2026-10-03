import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/env.dart';
import '../../core/logging/app_logger.dart';
import '../../core/media/photo_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/utils/validators.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_failure_localizations.dart';
import '../auth/auth_repository.dart';
import '../auth/user_profile.dart';
import '../auth/user_role_localizations.dart';
import '../cities/presentation/city_picker.dart';
import '../inspections/presentation/widgets/design_widgets.dart';

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

  /// The chosen canonical service city, for an inspector registering.
  ///
  /// A value rather than a controller: the city comes from the [CityPicker]
  /// sheet, not from typing, so there is no cursor to own.
  String? _serviceCity;

  bool _registering = false;
  bool _obscurePassword = true;
  UserRole _role = UserRole.client;

  /// The identity document chosen for this registration.
  ///
  /// Held in memory and passed to [AuthController.signUp] rather than uploaded
  /// immediately, because the object cannot be filed until Supabase Auth has minted
  /// the id — the repository does the upload itself straight after signup returns.
  XFile? _idPhoto;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickIdPhoto() async {
    final PhotoPicker picker = ref.read(identityPhotoPickerProvider);
    final XFile? file = await picker.pickFromGallery();
    if (file == null || !mounted) return;
    setState(() => _idPhoto = file);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // The create-account button is disabled while this is false, so reaching here
    // without a photo means the state changed under a keyboard submission. Returning
    // rather than signing up without a document is the point of the check: a
    // `?.` fallback would let an inspector through with nothing for an admin to
    // review, which is the exact gap the document exists to close.
    // The create-account button is disabled while no photo is chosen, so reaching
    // here without one means the state changed under a keyboard submission. Returning
    // rather than signing up without a document is the point of the check: a `?.`
    // fallback would let an inspector through with nothing for an admin to review,
    // which is the exact gap the document exists to close.
    final XFile? idPhoto = _idPhoto;

    AppLogger.instance.info(_registering ? 'submitting registration' : 'submitting sign-in');

    if (_registering) {
      if (idPhoto == null) return;
      await ref.read(authControllerProvider.notifier).signUp(
        email: _email.text,
        password: _password.text,
        fullName: _fullName.text,
        role: _role,
        idPhoto: idPhoto,
        phone: _phone.text,
        city: _role == UserRole.inspector ? _serviceCity : null,
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
      // The whole form resets, so the document does too. Keeping it would mean
      // signing up in a different mode with a picture picked for the previous one,
      // which is the kind of small wrongness that is impossible to notice later.
      _idPhoto = null;
      _formKey.currentState?.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<UserProfile?> auth = ref.watch(authControllerProvider);
    final bool busy = auth.isLoading;
    final Object? authError = auth.error;
    // An [AuthFailure] carries a reason, and the reason is turned into a
    // sentence here so the text is localised and translatable. Its `detail` —
    // the server's own wording — stays in the log.
    final String? failure = switch (authError) {
      null => null,
      final AuthFailure authFailure => authFailure.localizedMessage(l10n),
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
                        CityPicker(
                          label: l10n.fieldServiceCity,
                          helperText: l10n.helperServiceCity,
                          onChanged: (String city) =>
                              setState(() => _serviceCity = city),
                          validator: Validators.city,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _IdPhotoField(
                        photo: _idPhoto,
                        onPick: _pickIdPhoto,
                      ),
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
                      // Disabled until a document is chosen. The requirement is the
                      // point of the field above, and an account with no document is
                      // one an admin's queue cannot act on — so the button refuses
                      // rather than explaining afterwards.
                      onPressed: busy || (_registering && _idPhoto == null)
                          ? null
                          : _submit,
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

/// The identity-document control in the registration form.
///
/// A [NoticeBox] rather than a [TextFormField] because there is nothing to type: the
/// only input is a picture, and the requirement is that it exists. The dashed border
/// is the design's own "put something here" treatment, which is exactly the state
/// this field is in until a photo is chosen.
///
/// Rendered for both roles, not only inspectors. A buyer uses the platform the
/// moment they sign up, so an unverified buyer is working and an inspector is not —
/// but the *document* is wanted from both, and a control that appears only for one
/// role would make the document look optional to the other.
class _IdPhotoField extends StatelessWidget {
  const _IdPhotoField({required this.photo, required this.onPick});

  final XFile? photo;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool chosen = photo != null;

    return NoticeBox(
      title: l10n.accessDocumentsTitle,
      titleIcon: Icons.badge_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.accessDocumentsBody, style: AppText.secondary(13)),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: Icon(
              chosen ? Icons.check_circle_outline : Icons.upload_file,
              size: 18,
            ),
            label: Text(l10n.actionUploadId),
          ),
          if (chosen) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            // The button's own label is deliberately unchanged when a photo is
            // chosen: relabelling it to something like "replace" would read as a
            // different action, and the file name is worse still — an Arabic user
            // gets `IMG_0042.jpg` with no indication of what it is. A confirmed
            // line under the control says the one thing that matters: the platform
            // has the document.
            Text(
              l10n.adminDocumentOnFile,
              style: AppText.secondary(
                12,
                color: AppColors.green,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ],
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
