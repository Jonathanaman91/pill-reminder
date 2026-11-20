import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../dashboard/view/dashboard_screen.dart';
import '../facilities/view/nearby_screen.dart';
import '../history/view/history_screen.dart';
import '../medications/view/medications_screen.dart';

/// Four tabs: Today (the dose dashboard), Medications (edit or delete what
/// is saved), History (the last 30 days) and Nearby (pharmacies & clinics).
///
/// IndexedStack keeps each tab alive when switching, so the dashboard
/// doesn't reload. The other tabs are only built the first time they're
/// opened, so the app never asks for location until the user wants the map.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onAddMedication, required this.onOpenAccount});

  final VoidCallback onAddMedication;
  final VoidCallback onOpenAccount;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _opened = <int>{0};

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(
            // The NavigationBar below handles the bottom safe area, so the
            // tabs don't need to leave room for it again.
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: IndexedStack(
              index: _index,
              children: [
                DashboardScreen(
                  onAddMedication: widget.onAddMedication,
                  onOpenAccount: widget.onOpenAccount,
                ),
                if (_opened.contains(1))
                  MedicationsScreen(onAddMedication: widget.onAddMedication)
                else
                  const SizedBox.shrink(),
                if (_opened.contains(2)) const HistoryScreen() else const SizedBox.shrink(),
                if (_opened.contains(3)) const NearbyScreen() else const SizedBox.shrink(),
              ],
              ),
            ),
          ),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() {
              _index = i;
              _opened.add(i);
            }),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.today_rounded), label: 'Today'),
              NavigationDestination(icon: Icon(Icons.medication_rounded), label: 'Medications'),
              NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
              NavigationDestination(icon: Icon(Icons.local_pharmacy_rounded), label: 'Nearby'),
            ],
          ),
        ],
      ),
    );
  }
}
