import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_error.dart';
import '../data/facility_repository.dart';
import '../data/location_service.dart';
import '../domain/facility.dart';

enum NearbyStatus {
  locating,
  loading,
  ready,
  locationOff,
  permissionDenied,
  permissionDeniedForever,
  locationUnavailable,
  locationNotConfigured,
  failure,
}

final class NearbyState extends Equatable {
  const NearbyState({
    this.status = NearbyStatus.locating,
    this.latitude,
    this.longitude,
    this.result,
    this.filter = FacilityFilter.all,
    this.open24Only = false,
    this.selectedId,
    this.error,
  });

  final NearbyStatus status;
  final double? latitude;
  final double? longitude;
  final NearbyFacilities? result;
  final FacilityFilter filter;
  final bool open24Only;
  final String? selectedId;
  final String? error;

  /// The list after the chips are applied (nearest first).
  List<Facility> get visible => [
        for (final f in result?.facilities ?? const <Facility>[])
          if (filter.matches(f) && (!open24Only || f.is24Hours)) f,
      ];

  Facility? get selected {
    for (final f in result?.facilities ?? const <Facility>[]) {
      if (f.id == selectedId) return f;
    }
    return null;
  }

  NearbyState copyWith({
    NearbyStatus? status,
    double? latitude,
    double? longitude,
    NearbyFacilities? result,
    FacilityFilter? filter,
    bool? open24Only,
    String? Function()? selectedId,
    String? Function()? error,
  }) =>
      NearbyState(
        status: status ?? this.status,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        result: result ?? this.result,
        filter: filter ?? this.filter,
        open24Only: open24Only ?? this.open24Only,
        selectedId: selectedId != null ? selectedId() : this.selectedId,
        error: error != null ? error() : this.error,
      );

  @override
  List<Object?> get props =>
      [status, latitude, longitude, result?.fetchedAt, result?.facilities, filter, open24Only, selectedId, error];
}

/// ViewModel for the Nearby screen: find the phone → ask for places → filter.
class NearbyCubit extends Cubit<NearbyState> {
  NearbyCubit({required LocationService location, required FacilityRepository repository})
      : _location = location,
        _repository = repository,
        super(const NearbyState());

  final LocationService _location;
  final FacilityRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: NearbyStatus.locating, error: () => null));
    LocationResult position;
    try {
      position = await _location.current();
    } catch (_) {
      position = const LocationUnavailable(); // never stay stuck on "locating"
    }
    if (isClosed) return;

    switch (position) {
      case LocationServiceOff _:
        return emit(state.copyWith(status: NearbyStatus.locationOff));
      case LocationDenied(permanently: true):
        return emit(state.copyWith(status: NearbyStatus.permissionDeniedForever));
      case LocationDenied _:
        return emit(state.copyWith(status: NearbyStatus.permissionDenied));
      case LocationUnavailable _:
        return emit(state.copyWith(status: NearbyStatus.locationUnavailable));
      case LocationNotConfigured _:
        return emit(state.copyWith(status: NearbyStatus.locationNotConfigured));
      case LocationFound(:final latitude, :final longitude):
        emit(state.copyWith(
          status: state.result == null ? NearbyStatus.loading : NearbyStatus.ready,
          latitude: latitude,
          longitude: longitude,
        ));
        try {
          final result = await _repository.nearby(latitude, longitude);
          if (!isClosed) emit(state.copyWith(status: NearbyStatus.ready, result: result));
        } catch (e) {
          if (!isClosed) {
            final error = ApiError.from(e);
            emit(state.copyWith(
              status: state.result == null ? NearbyStatus.failure : NearbyStatus.ready,
              error: () => error.isOffline
                  ? 'Couldn’t reach the server. Check your internet connection '
                      '(and that the backend is running), then try again.'
                  : error.message,
            ));
          }
        }
    }
  }

  void setFilter(FacilityFilter filter) =>
      emit(state.copyWith(filter: filter, selectedId: () => null));

  void toggleOpen24() => emit(state.copyWith(open24Only: !state.open24Only, selectedId: () => null));

  void select(String? id) => emit(state.copyWith(selectedId: () => id));

  /// The button on the "location is off / not allowed" message.
  Future<void> fixLocation() async {
    switch (state.status) {
      case NearbyStatus.locationOff:
        // Opens Android settings; the screen reloads when the user comes back.
        await _location.openLocationSettings();
      case NearbyStatus.permissionDeniedForever:
        await _location.openAppSettings();
      default:
        await load(); // asks for permission again / retries
    }
  }

  /// Called when the app returns to the foreground (e.g. from Settings).
  Future<void> onResume() async {
    const waitingOnSettings = {NearbyStatus.locationOff, NearbyStatus.permissionDeniedForever};
    if (waitingOnSettings.contains(state.status)) await load();
  }
}
