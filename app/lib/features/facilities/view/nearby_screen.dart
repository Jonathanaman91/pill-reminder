import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/launchers.dart';
import '../../../core/widgets/message_view.dart';
import '../bloc/nearby_cubit.dart';
import '../data/facility_repository.dart';
import '../data/location_service.dart';
import '../domain/facility.dart';
import 'widgets/facility_map.dart';
import 'widgets/facility_row.dart';
import 'widgets/facility_sheet.dart';

class NearbyScreen extends StatelessWidget {
  const NearbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => NearbyCubit(
        location: context.read<LocationService>(),
        repository: context.read<FacilityRepository>(),
      )..load(),
      child: const _NearbyView(),
    );
  }
}

class _NearbyView extends StatefulWidget {
  const _NearbyView();

  @override
  State<_NearbyView> createState() => _NearbyViewState();
}

class _NearbyViewState extends State<_NearbyView> {
  final _map = MapController();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back from Settings after turning Location on → try again.
    _lifecycle = AppLifecycleListener(onResume: () => context.read<NearbyCubit>().onResume());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _directions(Facility f) async {
    final ok = await openDirections(latitude: f.latitude, longitude: f.longitude, label: f.name);
    if (!ok && mounted) _toast('No maps app found on this phone.');
  }

  Future<void> _call(String phone) async {
    if (!await openDialer(phone) && mounted) _toast('This phone can’t make calls.');
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _fitTo(NearbyState state) {
    final points = [
      LatLng(state.latitude!, state.longitude!),
      for (final f in state.visible.take(5)) LatLng(f.latitude, f.longitude),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _map.fitCamera(CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(40),
        maxZoom: 16,
      ));
    });
  }

  Future<void> _open(Facility f) async {
    final cubit = context.read<NearbyCubit>()..select(f.id);
    _map.move(LatLng(f.latitude, f.longitude), 16);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => FacilitySheet(
        facility: f,
        onDirections: () => _directions(f),
        onCall: () => _call(f.phone!),
      ),
    );
    if (!cubit.isClosed) cubit.select(null);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NearbyCubit>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: BlocConsumer<NearbyCubit, NearbyState>(
          // After "search again", re-fit the map around the new results.
          listenWhen: (prev, curr) =>
          prev.result != null &&
              curr.result != null &&
              prev.result!.fetchedAt != curr.result!.fetchedAt,
          listener: (context, state) => _fitTo(state),
          builder: (context, state) {
            final Widget body = switch (state.status) {
            NearbyStatus.locating || NearbyStatus.loading when state.result == null =>
            _NearbySkeleton(
            key: const ValueKey('loading'),
            label: state.status == NearbyStatus.locating
            ? 'Finding your location…'
                : 'Looking for pharmacies and clinics…',
            ),
            NearbyStatus.locationOff => MessageView(
            key: const ValueKey('off'),
            icon: Icons.location_off_rounded,
            title: 'Location is turned off',
            body: 'Turn on Location to see pharmacies and clinics near you. '
            'GPS works even without internet.',
            actionLabel: 'Open settings',
            actionIcon: Icons.settings_rounded,
            onAction: cubit.fixLocation,
            ),
            NearbyStatus.permissionDenied => MessageView(
            key: const ValueKey('denied'),
            icon: Icons.location_disabled_rounded,
            title: 'Allow location access',
            body: 'Your location is only used to find places near you. It isn’t saved.',
            actionLabel: 'Allow',
            actionIcon: Icons.my_location_rounded,
            onAction: cubit.fixLocation,
            ),
            NearbyStatus.permissionDeniedForever => MessageView(
            key: const ValueKey('blocked'),
            icon: Icons.location_disabled_rounded,
            title: 'Location is blocked for this app',
            body: 'Turn it on in Settings → Permissions → Location, then come back.',
            actionLabel: 'Open app settings',
            actionIcon: Icons.settings_rounded,
            onAction: cubit.fixLocation,
            ),
            NearbyStatus.locationUnavailable => MessageView(
            key: const ValueKey('nofix'),
            icon: Icons.gps_not_fixed_rounded,
            title: 'Couldn’t find your location',
            body: 'Move near a window or outdoors, then try again.',
            actionLabel: 'Try again',
            actionIcon: Icons.refresh_rounded,
            onAction: cubit.load,
            ),
            NearbyStatus.locationNotConfigured => MessageView(
            key: const ValueKey('notconfigured'),
            icon: Icons.location_disabled_rounded,
            title: 'Location isn’t set up in this build',
            body: 'Add the ACCESS_FINE_LOCATION and ACCESS_COARSE_LOCATION permissions '
            'to android/app/src/main/AndroidManifest.xml (README section 1c), '
            'then stop and run the app again.',
            actionLabel: 'Try again',
            actionIcon: Icons.refresh_rounded,
            onAction: cubit.load,
            ),
            NearbyStatus.failure => MessageView(
            key: const ValueKey('failure'),
            icon: Icons.cloud_off_rounded,
            title: 'Couldn’t load nearby places',
            body: state.error ?? 'Please try again.',
            actionLabel: 'Try again',
            actionIcon: Icons.refresh_rounded,
            onAction: cubit.load,
            ),
            _ => _NearbyContent(
            key: const ValueKey('ready'),
            state: state,
            map: _map,
            onOpen: _open,
            onDirections: _directions,
            ),
            };
            return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: body);
          },
        ),
      ),
    );
  }
}

class _NearbyContent extends StatelessWidget {
  const _NearbyContent({
    super.key,
    required this.state,
    required this.map,
    required this.onOpen,
    required this.onDirections,
  });

  final NearbyState state;
  final MapController map;
  final ValueChanged<Facility> onOpen;
  final ValueChanged<Facility> onDirections;

  String _statusLine() {
    final r = state.result!;
    if (r.isDemo) return 'Demo mode · sample places around you';
    if (r.fromCache) {
      return 'Offline · places saved ${DateFormat('d MMM, HH:mm').format(r.fetchedAt)}';
    }
    if (r.partial) return 'Map service unavailable · showing places added by admins';
    final n = r.facilities.length;
    return '$n ${n == 1 ? 'place' : 'places'} within 10 km';
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NearbyCubit>();
    final text = Theme.of(context).textTheme;
    final visible = state.visible;
    final me = LatLng(state.latitude!, state.longitude!);
    final refreshing = state.status == NearbyStatus.locating || state.status == NearbyStatus.loading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.lg, AppSpace.sm, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Where to get your medicine', style: text.headlineMedium),
                    const SizedBox(height: AppSpace.xs),
                    Text(_statusLine(), style: text.labelMedium?.tabular),
                  ],
                ),
              ),
              refreshing
                  ? const SizedBox.square(
                dimension: 48,
                child: Center(
                  child: SizedBox.square(
                      dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
                  : IconButton(
                onPressed: cubit.load,
                tooltip: 'Search again from here',
                icon: const Icon(Icons.my_location_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.card)),
            child: SizedBox(
              height: 220,
              child: FacilityMap(
                controller: map,
                me: me,
                facilities: visible,
                selectedId: state.selectedId,
                onSelect: onOpen,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
            children: [
              for (final f in FacilityFilter.values) ...[
                ChoiceChip(
                  label: Text(f.label),
                  selected: state.filter == f,
                  onSelected: (_) => cubit.setFilter(f),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
              FilterChip(
                avatar: const Icon(Icons.schedule_rounded),
                label: const Text('Open 24 hours'),
                selected: state.open24Only,
                onSelected: (_) => cubit.toggleOpen24(),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: cubit.load,
            child: visible.isEmpty
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpace.screen),
              children: [
                Text('No places match these filters within 10 km.', style: text.bodyMedium),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      cubit.setFilter(FacilityFilter.all);
                      if (state.open24Only) cubit.toggleOpen24();
                    },
                    child: const Text('Show all places'),
                  ),
                ),
              ],
            )
                : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xl),
              itemCount: visible.length,
              itemBuilder: (context, i) => FacilityRow(
                key: ValueKey(visible[i].id),
                facility: visible[i],
                onTap: () => onOpen(visible[i]),
                onDirections: () => onDirections(visible[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NearbySkeleton extends StatelessWidget {
  const _NearbySkeleton({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    Widget bone(double? w, double h, [double r = AppRadius.bone]) => Container(
      width: w ?? double.infinity,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(r)),
      ),
    );

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.lg, AppSpace.screen, 0),
      children: [
        Row(
          children: [
            const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: AppSpace.sm),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        Shimmer.fromColors(
          baseColor: AppColors.surfaceMuted,
          highlightColor: AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bone(260, 28),
              const SizedBox(height: AppSpace.lg),
              bone(null, 220, AppRadius.card),
              const SizedBox(height: AppSpace.lg),
              Row(children: [bone(64, 32), const SizedBox(width: 8), bone(96, 32), const SizedBox(width: 8), bone(110, 32)]),
              const SizedBox(height: AppSpace.lg),
              for (var i = 0; i < 4; i++) ...[
                Row(
                  children: [
                    bone(40, 40, AppRadius.full),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [bone(160, 16), const SizedBox(height: 6), bone(210, 13)],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
              ],
            ],
          ),
        ),
      ],
    );
  }
}