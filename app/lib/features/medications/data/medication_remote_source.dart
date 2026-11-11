import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

class MedicationRemoteSource {
  MedicationRemoteSource(this._dio);

  final Dio _dio;

  /// POST /api/v1/medications/batch — safe to resend (upsert by id).
  Future<void> pushMedications(List<Map<String, Object?>> medications) async {
    await _dio.post<void>('/medications/batch', data: {
      'medications': [
        for (final m in medications) Map.of(m)..remove('updatedAt'),
      ],
    });
  }

  /// POST /api/v1/medications/:id/photo (multipart). Returns the photo URL.
  Future<String> uploadPhoto(String medicationId, String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    final subtype = switch (ext) {
      '.png' => 'png',
      '.webp' => 'webp',
      _ => 'jpeg',
    };
    final form = FormData.fromMap({
      'photo': await MultipartFile.fromFile(
        filePath,
        filename: 'bottle$ext',
        contentType: DioMediaType('image', subtype),
      ),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/medications/$medicationId/photo',
      data: form,
      options: Options(contentType: Headers.multipartFormDataContentType),
    );
    return res.data!['photoUrl'] as String;
  }
}
