import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/launchers.dart';
import '../../domain/facility.dart';
import 'facility_icons.dart';

/// OpenStreetMap with the user's position and a pin per place.
/// Tiles are free and need no API key; the attribution is required by
/// OpenStreetMap's tile usage policy.
class FacilityMap extends StatelessWidget {
  const FacilityMap({
    super.key,
    required this.controller,
    required this.me,
    required this.facilities,
    required this.selectedId,
    required this.onSelect,
  });

  final MapController controller;
  final LatLng me;
  final List<Facility> facilities;
  final String? selectedId;
  final ValueChanged<Facility> onSelect;

  @override
  Widget build(BuildContext context) {
    final nearest = facilities.take(5).map((f) => LatLng(f.latitude, f.longitude));

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: me,
        initialZoom: 14,
        // Start zoomed so you and the nearest few places are all visible.
        initialCameraFit: facilities.isEmpty
            ? null
            : CameraFit.coordinates(
                coordinates: [me, ...nearest],
                padding: const EdgeInsets.all(40),
                maxZoom: 16,
              ),
        minZoom: 5,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'my.edu.uts.pill_reminder',
        ),
        MarkerLayer(
          markers: [
            for (final f in facilities.reversed) // nearest drawn on top
              Marker(
                point: LatLng(f.latitude, f.longitude),
                width: f.id == selectedId ? 40 : 32,
                height: f.id == selectedId ? 40 : 32,
                child: _Pin(
                  facility: f,
                  selected: f.id == selectedId,
                  onTap: () => onSelect(f),
                ),
              ),
            Marker(point: me, width: 20, height: 20, child: const _MeDot()),
          ],
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => openWebPage('https://www.openstreetmap.org/copyright'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.facility, required this.selected, required this.onTap});

  final Facility facility;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${facility.name}, ${facility.kindLabel}, ${facility.distanceLabel}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            // The selected place uses the accent; all others stay ink.
            color: selected ? AppColors.accent : AppColors.ink,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(facilityIcon(facility.type), color: Colors.white, size: selected ? 20 : 16),
        ),
      ),
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Your location',
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB), // standard "you are here" blue, not the accent
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
      ),
    );
  }
}
