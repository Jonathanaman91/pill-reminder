import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Shared layout for the login and register screens: a headline, a short
/// line of help text, then the form — centred and capped in width so it also
/// looks right on tablets.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.showBack = false,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: showBack
          ? AppBar(backgroundColor: Colors.transparent, scrolledUnderElevation: 0)
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.screen, AppSpace.xl, AppSpace.screen, AppSpace.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: text.headlineMedium),
                  const SizedBox(height: AppSpace.sm),
                  Text(subtitle, style: text.bodyMedium),
                  const SizedBox(height: AppSpace.xxl),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Password box with a show/hide button.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.validator,
    this.helperText,
    this.serverError,
    this.autofillHints = const [AutofillHints.password],
    this.textInputAction = TextInputAction.done,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;
  final String? helperText;
  final String? serverError;
  final Iterable<String> autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      enableSuggestions: false,
      autocorrect: false,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      forceErrorText: widget.serverError,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _hidden = !_hidden),
          tooltip: _hidden ? 'Show password' : 'Hide password',
          icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded),
        ),
      ),
    );
  }
}

/// A general error (wrong password, no internet) shown right above the button,
/// where the user is already looking.
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.danger);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: AppSpace.lg),
              child: Semantics(
                liveRegion: true, // read aloud by TalkBack when it appears
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1), // align icon with first text line
                      child: Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: Text(message!, style: style)),
                  ],
                ),
              ),
            ),
    );
  }
}
