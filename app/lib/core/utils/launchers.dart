import 'package:url_launcher/url_launcher.dart';

/// Opens turn-by-turn directions. The `geo:` link makes Android ask which
/// app to use, so people can pick Waze or Google Maps. If no app handles it,
/// Google Maps opens in the browser instead.
Future<bool> openDirections({
  required double latitude,
  required double longitude,
  required String label,
}) async {
  final geo = Uri.parse(
      'geo:$latitude,$longitude?q=$latitude,$longitude(${Uri.encodeComponent(label)})');
  if (await _tryLaunch(geo)) return true;
  return _tryLaunch(Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '$latitude,$longitude',
  }));
}

/// Opens the phone dialer with the number filled in (the user still taps Call).
Future<bool> openDialer(String phone) =>
    _tryLaunch(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')));

Future<bool> openWebPage(String url) => _tryLaunch(Uri.parse(url));

Future<bool> _tryLaunch(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}
