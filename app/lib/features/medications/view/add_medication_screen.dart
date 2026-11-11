import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/submit_button.dart';
import '../bloc/add_medication_cubit.dart';
import '../data/medication_repository.dart';
import '../domain/medication.dart';
import 'widgets/photo_slot.dart';

class AddMedicationScreen extends StatelessWidget {
  const AddMedicationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AddMedicationCubit(context.read<MedicationRepository>()),
      child: const _AddMedicationForm(),
    );
  }
}

class _AddMedicationForm extends StatefulWidget {
  const _AddMedicationForm();

  @override
  State<_AddMedicationForm> createState() => _AddMedicationFormState();
}

class _AddMedicationFormState extends State<_AddMedicationForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _strength = TextEditingController();
  final _instructions = TextEditingController();
  final _picker = ImagePicker();
  bool _saved = false;

  static const _instructionPresets = ['Before food', 'After food', 'With food', 'Before bed'];

  AddMedicationCubit get _cubit => context.read<AddMedicationCubit>();

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _instructions.dispose();
    super.dispose();
  }

  bool get _hasInput {
    final s = _cubit.state;
    return _name.text.isNotEmpty ||
        _strength.text.isNotEmpty ||
        _instructions.text.isNotEmpty ||
        s.photoPath != null ||
        s.times.isNotEmpty;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // Photo
  // ---------------------------------------------------------------------------

  Future<void> _choosePhoto() async {
    final hasPhoto = _cubit.state.photoPath != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheet, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheet, 'gallery'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                title: const Text('Remove photo', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(sheet, 'remove'),
              ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      _cubit.setPhoto(null);
      return;
    }

    try {
      final picked = await _picker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        // Shrinks a 12 MP photo (~4 MB) to roughly 200 KB — quicker to upload
        // on a weak connection, and well under the server's 5 MB limit.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked != null) _cubit.setPhoto(picked.path);
    } on PlatformException catch (e) {
      _toast(e.code.contains('denied')
          ? 'Camera or photo access is turned off. Allow it in Settings → Apps → Pill Reminder.'
          : 'Couldn’t open the ${choice == 'camera' ? 'camera' : 'gallery'}.');
    }
  }

  // ---------------------------------------------------------------------------
  // Times and dates
  // ---------------------------------------------------------------------------

  Future<void> _addTime() async {
    final last = _cubit.state.times.isEmpty ? null : _cubit.state.times.last;
    final picked = await showTimePicker(
      context: context,
      initialTime: last == null
          ? const TimeOfDay(hour: 8, minute: 0)
          : TimeOfDay(hour: (last.hour + 4) % 24, minute: last.minute),
      helpText: 'Reminder time',
      // The app shows times as 08:00, so pick them the same way.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final problem = _cubit.addTime(ClockTime(picked.hour, picked.minute));
    if (problem != null) _toast(problem);
  }

  Future<DateTime?> _pickDate(DateTime initial, {DateTime? first}) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    _cubit.revealErrors();
    final textOk = _formKey.currentState!.validate();
    if (!textOk || !_cubit.state.choicesValid) {
      _toast('Some details are missing. Check the fields marked in red.');
      return;
    }

    final ok = await _cubit.save(
      name: _name.text,
      strength: Validators.parseAmount(_strength.text)!,
      instructions: _instructions.text,
    );
    if (!ok || !mounted) return;

    final count = _cubit.state.times.length;
    _saved = true;
    _toast('${_name.text.trim()} added · $count reminder${count == 1 ? '' : 's'} a day');
    Navigator.of(context).pop();
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Discard this medication?'),
        content: const Text('What you’ve entered will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AddMedicationCubit>().state;
    final text = Theme.of(context).textTheme;
    final autovalidate =
        state.showErrors ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled;

    return PopScope(
      // Back is intercepted so a half-filled form isn't lost by accident.
      // (Navigator.pop() in _save/_confirmDiscard still closes the screen.)
      canPop: _saved,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_hasInput) {
          _confirmDiscard();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add medication'),
          backgroundColor: AppColors.background,
          scrolledUnderElevation: 0,
        ),
        body: Form(
          key: _formKey,
          autovalidateMode: autovalidate,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.screen, AppSpace.sm, AppSpace.screen, AppSpace.xxl),
            children: [
              PhotoSlot(path: state.photoPath, onTap: state.submitting ? null : _choosePhoto),
              const SizedBox(height: AppSpace.xl),

              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: Validators.medicationName,
                decoration: const InputDecoration(
                  labelText: 'Medication name',
                  hintText: 'e.g. Metformin',
                ),
              ),

              _Section(
                label: 'Form',
                child: Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final f in DosageForm.values)
                      ChoiceChip(
                        label: Text(f.label),
                        selected: state.form == f,
                        onSelected: (_) => _cubit.setForm(f),
                        showCheckmark: false,
                      ),
                  ],
                ),
              ),

              _Section(
                label: 'Strength',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _strength,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        textInputAction: TextInputAction.next,
                        validator: Validators.strength,
                        style: text.bodyLarge?.tabular,
                        decoration: const InputDecoration(labelText: 'Amount', hintText: '500'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    SizedBox(
                      width: 116,
                      child: DropdownButtonFormField<String>(
                        // Rebuild when the form changes so the list of units updates.
                        key: ValueKey(state.form),
                        initialValue: state.unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: [
                          for (final u in state.form.units)
                            DropdownMenuItem(value: u, child: Text(u)),
                        ],
                        onChanged: (u) {
                          if (u != null) _cubit.setUnit(u);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              if (state.form.countable)
                _Section(
                  label: 'Each dose',
                  child: _QuantityStepper(
                    quantity: state.quantity,
                    noun: state.form.name,
                    onChange: _cubit.changeQuantity,
                  ),
                ),

              _Section(
                label: 'Reminder times',
                error: state.showErrors ? state.timesError : null,
                child: Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final t in state.times)
                      InputChip(
                        label: Text(t.hhmm, style: text.titleSmall?.tabular),
                        onDeleted: () => _cubit.removeTime(t),
                        deleteIcon: const Icon(Icons.close_rounded, size: 18),
                        deleteButtonTooltipMessage: 'Remove ${t.hhmm}',
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add time'),
                      onPressed: _addTime,
                    ),
                  ],
                ),
              ),

              _Section(
                label: 'Repeat',
                error: state.showErrors ? state.daysError : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Every day')),
                        ButtonSegment(value: false, label: Text('Some days')),
                      ],
                      selected: {state.everyDay},
                      onSelectionChanged: (s) => _cubit.setEveryDay(s.first),
                      showSelectedIcon: false,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      alignment: Alignment.topCenter,
                      child: state.everyDay
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: AppSpace.md),
                              child: Wrap(
                                spacing: AppSpace.sm,
                                runSpacing: AppSpace.sm,
                                children: [
                                  for (var i = 0; i < 7; i++)
                                    FilterChip(
                                      label: Text(WeekDays.labels[i]),
                                      selected: WeekDays.has(state.customDays, i),
                                      onSelected: (_) => _cubit.toggleDay(i),
                                      showCheckmark: false,
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              _Section(
                label: 'Dates',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Start',
                        value: state.startDate,
                        onTap: () async {
                          final d = await _pickDate(state.startDate);
                          if (d != null) _cubit.setStartDate(d);
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: _DateField(
                        label: 'End',
                        value: state.endDate,
                        emptyText: 'No end date',
                        error: state.endDateError,
                        onClear: state.endDate == null ? null : () => _cubit.setEndDate(null),
                        onTap: () async {
                          final d = await _pickDate(state.endDate ?? state.startDate,
                              first: state.startDate);
                          if (d != null) _cubit.setEndDate(d);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              _Section(
                label: 'Instructions (optional)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _instructions,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 255,
                      validator: Validators.instructions,
                      decoration: const InputDecoration(
                        hintText: 'e.g. After food',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        for (final preset in _instructionPresets)
                          ActionChip(
                            label: Text(preset),
                            onPressed: () => _instructions.text = preset,
                              ),
                      ],
                    ),
                  ],
                ),
              ),

              if (state.saveError != null) ...[
                const SizedBox(height: AppSpace.lg),
                Text(state.saveError!,
                    style: text.bodyMedium?.copyWith(color: AppColors.danger)),
              ],
            ],
          ),
        ),
        // The one accent button, pinned so it's always reachable.
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.screen, AppSpace.sm, AppSpace.screen, AppSpace.md),
            child: SubmitButton(
              label: 'Save medication',
              submitting: state.submitting,
              onPressed: _save,
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled group of fields, with an optional error under it.
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child, this.error});

  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: text.labelMedium),
          const SizedBox(height: AppSpace.sm),
          child,
          if (error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(error!, style: text.bodyMedium?.copyWith(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.noun, required this.onChange});

  final double quantity;
  final String noun; // tablet / capsule
  final ValueChanged<double> onChange;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final whole = quantity == quantity.roundToDouble();
    final number = whole ? quantity.toInt().toString() : quantity.toString();
    final label = '$number ${quantity == 1 ? noun : '${noun}s'}';

    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: quantity > AddMedicationCubit.minQuantity ? () => onChange(-0.5) : null,
          tooltip: 'Half less',
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 120,
          child: Text(label, textAlign: TextAlign.center, style: text.titleMedium?.tabular),
        ),
        IconButton.filledTonal(
          onPressed: quantity < AddMedicationCubit.maxQuantity ? () => onChange(0.5) : null,
          tooltip: 'Half more',
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// Looks like a text box, opens a date picker when tapped.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.emptyText = '',
    this.error,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String emptyText;
  final String? error;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          suffixIcon: onClear == null
              ? const Icon(Icons.calendar_today_rounded, size: 18)
              : IconButton(
                  onPressed: onClear,
                  tooltip: 'Remove end date',
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
        ),
        child: Text(
          value == null ? emptyText : DateFormat('d MMM yyyy').format(value!),
          style: (value == null ? text.bodyMedium : text.bodyLarge)?.tabular,
        ),
      ),
    );
  }
}
