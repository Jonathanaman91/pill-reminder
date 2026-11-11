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
import 'register_screen.dart';
import 'widgets/auth_widgets.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthFormCubit(context.read<AuthRepository>()),
      child: const _LoginForm(),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _autovalidate = AutovalidateMode.disabled;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    // After the first attempt, re-check each field as the user types.
    setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
    if (!_formKey.currentState!.validate()) return;

    final user = await context
        .read<AuthFormCubit>()
        .logIn(email: _email.text, password: _password.text);
    if (user != null && mounted) {
      TextInput.finishAutofillContext(); // offers to save the password
      context.read<AuthBloc>().add(AuthLoggedIn(user));
    }
  }

  // AuthRepository and AuthBloc sit above MaterialApp, so every route sees them.
  void _openRegister() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const RegisterScreen()));

  @override
  Widget build(BuildContext context) {
    final form = context.watch<AuthFormCubit>().state;
    final cubit = context.read<AuthFormCubit>();

    return AuthLayout(
      title: 'Log in',
      subtitle: 'Your schedule is saved on this phone, so reminders keep '
          'working when you have no signal.',
      children: [
        AutofillGroup(
          child: Form(
            key: _formKey,
            autovalidateMode: _autovalidate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  validator: Validators.passwordPresent,
                  serverError: form.fieldErrors['password'],
                  onChanged: (_) => cubit.clearFieldError('password'),
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        FormErrorText(form.error),
        const SizedBox(height: AppSpace.xl),
        SubmitButton(label: 'Log in', submitting: form.submitting, onPressed: _submit),
        WaitingHint(active: form.submitting),
        const SizedBox(height: AppSpace.sm),
        TextButton(
          onPressed: form.submitting ? null : _openRegister,
          child: const Text('Create an account'),
        ),
      ],
    );
  }
}
