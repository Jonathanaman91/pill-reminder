import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/submit_button.dart';
import '../bloc/profile_cubit.dart';
import '../data/profile_repository.dart';
import '../domain/health_profile.dart';

/// Health profile: date of birth, gender, long-term conditions and allergies.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ProfileCubit(context.read<ProfileRepository>()),
      child: const _ProfileForm(),
    );
  }
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm();

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  final _newCondition = TextEditingController();
  final _allergies = TextEditingController();
  bool _filled = false;

  ProfileCubit get _cubit => context.read<ProfileCubit>();

  @override
  void dispose() {
    _newCondition.dispose();
    _allergies.dispose();
    super.dispose();
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _pickBirthday(DateTime? current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 40),
      firstDate: DateTime(1900),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDatePickerMode: DatePickerMode.year, // pick the year first
      helpText: 'Date of birth',
    );
    if (picked != null) _cubit.setDateOfBirth(picked);
  }

  void _addCondition() {
    final problem = _cubit.addCondition(_newCondition.text);
    if (problem != null) {
      _toast(problem);
    } else {
      _newCondition.clear();
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_cubit.state.changed) {
      Navigator.of(context).pop();
      return;
    }
    if (await _cubit.save() && mounted) {
      _toast('Health profile saved');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileCubit>().state;
    final text = Theme.of(context).textTheme;
    final p = state.profile;

    if (state.status == ProfileStatus.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_filled) {
      _allergies.text = p.allergies ?? '';
      _filled = true;
    }

    final age = p.ageOn(DateTime.now());
    // Quick choices first, then anything the user typed themselves.
    final custom = p.conditions
        .where((c) => !HealthProfile.commonConditions.any((x) => x.toLowerCase() == c.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health profile'),
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.sm, AppSpace.screen, AppSpace.xxl),
        children: [
          Text(
            'Kept on this phone and in your account. It helps you show your doctor the full '
            'picture. Admins only ever see totals, never your details.',
            style: text.bodyMedium,
          ),

          _Section(
            label: 'Date of birth',
            child: InkWell(
              onTap: () => _pickBirthday(p.dateOfBirth),
              borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
              child: InputDecorator(
                isEmpty: false,
                decoration: InputDecoration(
                  suffixIcon: p.dateOfBirth == null
                      ? const Icon(Icons.calendar_today_rounded, size: 18)
                      : IconButton(
                          onPressed: () => _cubit.setDateOfBirth(null),
                          tooltip: 'Remove date of birth',
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                ),
                child: Text(
                  p.dateOfBirth == null
                      ? 'Not set'
                      : '${DateFormat('d MMMM yyyy').format(p.dateOfBirth!)} · age $age',
                  style: (p.dateOfBirth == null ? text.bodyMedium : text.bodyLarge)?.tabular,
                ),
              ),
            ),
          ),

          _Section(
            label: 'Gender',
            child: SegmentedButton<Gender>(
              segments: [
                for (final g in Gender.values) ButtonSegment(value: g, label: Text(g.label)),
              ],
              selected: {if (p.gender != null) p.gender!},
              emptySelectionAllowed: true,
              onSelectionChanged: (s) => _cubit.setGender(s.isEmpty ? null : s.first),
              showSelectedIcon: false,
            ),
          ),

          _Section(
            label: 'Long-term conditions',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final c in HealthProfile.commonConditions)
                      FilterChip(
                        label: Text(c),
                        selected: p.conditions.any((x) => x.toLowerCase() == c.toLowerCase()),
                        onSelected: (_) => _cubit.toggleCondition(c),
                        showCheckmark: false,
                      ),
                    for (final c in custom)
                      InputChip(
                        label: Text(c),
                        selected: true,
                        showCheckmark: false,
                        onDeleted: () => _cubit.toggleCondition(c),
                        deleteIcon: const Icon(Icons.close_rounded, size: 18),
                        deleteButtonTooltipMessage: 'Remove $c',
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newCondition,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 60,
                        onSubmitted: (_) => _addCondition(),
                        decoration: const InputDecoration(
                          hintText: 'Another condition',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    IconButton.filledTonal(
                      onPressed: _addCondition,
                      tooltip: 'Add condition',
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),

          _Section(
            label: 'Allergies (optional)',
            child: TextField(
              controller: _allergies,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 255,
              minLines: 1,
              maxLines: 3,
              onChanged: _cubit.setAllergies,
              decoration: const InputDecoration(
                hintText: 'e.g. Penicillin, peanuts',
                counterText: '',
              ),
            ),
          ),

          if (state.error != null) ...[
            const SizedBox(height: AppSpace.lg),
            Text(state.error!, style: text.bodyMedium?.copyWith(color: AppColors.danger)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.sm, AppSpace.screen, AppSpace.md),
          child: SubmitButton(
            label: 'Save profile',
            submitting: state.status == ProfileStatus.saving,
            onPressed: _save,
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpace.sm),
          child,
        ],
      ),
    );
  }
}
