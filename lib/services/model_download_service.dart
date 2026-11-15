import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/gguf_model_info.dart';

/// خدمة تحميل وإدارة ملفات نماذج GGUF المحلية مع دعم استئناف التحميل (HTTP Range Resume)
class ModelDownloadService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(hours: 2),
      followRedirects: true,
    ),
  );

  CancelToken? _activeCancelToken;

  /// الحصول على المسار المحلي لملف النموذج داخل مجلد التطبيق الخاص
  Future<String> getModelFilePath(GgufModelInfo model) async {
    final Directory appSupportDir = await getApplicationSupportDirectory();
    final Directory modelsDir = Directory(p.join(appSupportDir.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return p.join(modelsDir.path, model.fileName);
  }

  /// التحقق مما إذا كان النموذج محملاً بالكامل وجاهزاً للاستخدام بدون إنترنت
  Future<bool> isModelDownloaded(GgufModelInfo model) async {
    final String filePath = await getModelFilePath(model);
    final File file = File(filePath);
    if (!await file.exists()) return false;

    final int lengthBytes = await file.length();
    return lengthBytes > 500 * 1024 * 1024;
  }

  /// إرجاع حجم الملف المحمل حالياً بالميجابايت
  Future<double> getDownloadedFileSizeMb(GgufModelInfo model) async {
    final String filePath = await getModelFilePath(model);
    final File file = File(filePath);
    if (!await file.exists()) return 0.0;
    final int bytes = await file.length();
    return bytes / (1024 * 1024);
  }

  /// تحميل ملف GGUF مع دعم استئناف التحميل الجزئي (.part) وشريط التقدم
  Future<String> downloadModel({
    required GgufModelInfo model,
    required void Function(int receivedBytes, int totalBytes, double speedMbPerSec) onProgress,
  }) async {
    final String finalPath = await getModelFilePath(model);
    final String tempPath = '$finalPath.part';
    final File tempFile = File(tempPath);

    int existingBytes = 0;
    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
    }

    _activeCancelToken = CancelToken();
    final Stopwatch stopwatch = Stopwatch()..start();
    int lastReceivedBytes = 0;
    int lastElapsedMs = 0;

    try {
      final Response<ResponseBody> response = await _dio.get<ResponseBody>(
        model.downloadUrl,
        cancelToken: _activeCancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : null,
        ),
      );

      final bool isPartialContent = response.statusCode == 206;
      final int contentLength = int.tryParse(
            response.headers.value(Headers.contentLengthHeader) ?? '0',
          ) ??
          0;
      final int totalBytes = isPartialContent ? existingBytes + contentLength : contentLength;

      final RandomAccessFile raf = await tempFile.open(
        mode: isPartialContent ? FileMode.append : FileMode.write,
      );

      int received = isPartialContent ? existingBytes : 0;

      await for (final List<int> chunk in response.data!.stream) {
        await raf.writeFrom(chunk);
        received += chunk.length;

        final int nowMs = stopwatch.elapsedMilliseconds;
        if (nowMs - lastElapsedMs >= 400) {
          final int deltaBytes = received - lastReceivedBytes;
          final double deltaSec = (nowMs - lastElapsedMs) / 1000.0;
          final double speedMbPerSec =
              deltaSec > 0 ? (deltaBytes / (1024 * 1024)) / deltaSec : 0.0;

          lastReceivedBytes = received;
          lastElapsedMs = nowMs;
          onProgress(received, totalBytes, speedMbPerSec);
        }
      }

      await raf.close();
      stopwatch.stop();

      if (await File(finalPath).exists()) {
        await File(finalPath).delete();
      }
      await tempFile.rename(finalPath);
      return finalPath;
    } catch (e) {
      stopwatch.stop();
      rethrow;
    }
  }

  void cancelDownload() {
    if (_activeCancelToken != null && !_activeCancelToken!.isCancelled) {
      _activeCancelToken!.cancel('تم إيقاف التحميل مؤقتاً من قِبل المستخدم.');
    }
  }

  Future<void> deleteModel(GgufModelInfo model) async {
    final String finalPath = await getModelFilePath(model);
    final File finalFile = File(finalPath);
    final File partFile = File('$finalPath.part');

    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    if (await partFile.exists()) {
      await partFile.delete();
    }
  }
}
