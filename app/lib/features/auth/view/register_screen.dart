import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/submit_button.dart';
import '../../../core/widgets/waiting_hint.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_form_cubit.dart';
import '../data/auth_repository.dart';
import 'login_screen.dart';
import 'widgets/auth_widgets.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key, this.fromGuest = false});

  /// Opened by a guest: what they saved on this phone moves into the account.
  final bool fromGuest;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthFormCubit(context.read<AuthRepository>()),
      child: _RegisterForm(fromGuest: fromGuest),
    );
  }
}

class _RegisterForm extends StatefulWidget {
  const _RegisterForm({required this.fromGuest});

  final bool fromGuest;

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  var _autovalidate = AutovalidateMode.disabled;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
    if (!_formKey.currentState!.validate()) return;

    final user = await context.read<AuthFormCubit>().register(
          fullName: _name.text,
          email: _email.text,
          password: _password.text,
        );
    if (user != null && mounted) {
      TextInput.finishAutofillContext();
      // AuthGate closes this screen and shows the dashboard.
      context.read<AuthBloc>().add(AuthLoggedIn(user,
          notice: widget.fromGuest
              ? 'Account created · your medications are now backed up'
              : 'Account created'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = context.watch<AuthFormCubit>().state;
    final cubit = context.read<AuthFormCubit>();

    return AuthLayout(
      showBack: true,
      title: 'Create your account',
      subtitle: widget.fromGuest
          ? 'The medications on this phone move into your new account, so '
              'you can get them back on a new phone.'
          : 'Your medications are backed up to your account, so you can '
              'get them back on a new phone.',
      children: [
        AutofillGroup(
          child: Form(
            key: _formKey,
            autovalidateMode: _autovalidate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  validator: Validators.fullName,
                  forceErrorText: form.fieldErrors['fullName'],
                  onChanged: (_) => cubit.clearFieldError('fullName'),
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: AppSpace.lg),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  validator: Validators.email,
                  forceErrorText: form.fieldErrors['email'],
                  onChanged: (_) => cubit.clearFieldError('email'),
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: AppSpace.lg),
                PasswordField(
                  controller: _password,
                  label: 'Password',
                  helperText: 'At least 8 characters, with a letter and a number',
                  validator: Validators.newPassword,
                  serverError: form.fieldErrors['password'],
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => cubit.clearFieldError('password'),
                ),
                const SizedBox(height: AppSpace.lg),
                PasswordField(
                  controller: _confirm,
                  label: 'Confirm password',
                  validator: Validators.matches(() => _password.text),
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        FormErrorText(form.error),
        const SizedBox(height: AppSpace.xl),
        SubmitButton(
          label: 'Create account',
          submitting: form.submitting,
          onPressed: _submit,
        ),
        WaitingHint(active: form.submitting),
        const SizedBox(height: AppSpace.sm),
        TextButton(
          onPressed: form.submitting
              ? null
              : widget.fromGuest
                  // Opened from the dashboard: swap to the login form instead
                  // of going back to the dashboard.
                  ? () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(fromGuest: true)))
                  : () => Navigator.of(context).pop(),
          child: const Text('I already have an account'),
        ),
      ],
    );
  }
}
