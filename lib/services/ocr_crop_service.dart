import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/exercise_page_item.dart';

/// خدمة المرحلة الأولى (العيون - Multi-Image OCR & Sequential Image Cropping)
class OcrCropService {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// 1. التقاط صورة واحدة من الكاميرا أو المعرض وقصها وإرجاع عنصر صفحة جاهز
  Future<ExercisePageItem?> pickAndProcessSinglePage({
    required ImageSource source,
    required Color primaryColor,
    required int pageNumberHint,
  }) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 95,
    );
    if (pickedFile == null) return null;

    final File? cropped = await cropImageFile(
      sourcePath: pickedFile.path,
      primaryColor: primaryColor,
      toolbarTitle: 'قص وتحديد الصفحة ($pageNumberHint)',
    );
    if (cropped == null) return null;

    return await extractPageItemFromFile(
      imageFile: cropped,
      pageNumberHint: pageNumberHint,
    );
  }

  /// 2. اختيار عدة صور دفعة واحدة من المعرض (Multi-Image Selection) وقصها بالتتابع مع الحفاظ على ترتيبها
  Future<List<ExercisePageItem>> pickAndProcessMultipleGalleryPages({
    required Color primaryColor,
    required int startingPageNumber,
    required void Function(int currentIndex, int totalCount) onPageProgress,
  }) async {
    final List<XFile> pickedFiles = await _picker.pickMultiImage(
      imageQuality: 95,
    );
    if (pickedFiles.isEmpty) return [];

    final List<ExercisePageItem> results = [];

    for (int i = 0; i < pickedFiles.length; i++) {
      final int pageNum = startingPageNumber + i;
      onPageProgress(i + 1, pickedFiles.length);

      // فتح أداة القص لكل صورة بالترتيب لضمان نظافة السياق من الهوامش الجانبية
      final File? cropped = await cropImageFile(
        sourcePath: pickedFiles[i].path,
        primaryColor: primaryColor,
        toolbarTitle: 'قص الصورة ${i + 1} من ${pickedFiles.length} (صفحة $pageNum)',
      );

      // إذا ضغط المستخدم إلغاء على صورة معينة نستخدم الصورة الأصلية أو نتخطاها؛ هنا نعتمد الصورة المقصوصة
      final File targetFile = cropped ?? File(pickedFiles[i].path);

      final ExercisePageItem item = await extractPageItemFromFile(
        imageFile: targetFile,
        pageNumberHint: pageNum,
      );
      results.add(item);
    }

    return results;
  }

  /// أداة قص صورة مفردة (تُستخدم عند الإضافة أو عند الضغط على زر إعادة قص صورة موجودة)
  Future<File?> cropImageFile({
    required String sourcePath,
    required Color primaryColor,
    String toolbarTitle = 'قص وتحديد سؤال التمرين',
  }) async {
    final CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: toolbarTitle,
          toolbarColor: primaryColor,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: primaryColor,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: toolbarTitle,
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
        ),
      ],
    );

    if (croppedFile == null) return null;
    return File(croppedFile.path);
  }

  /// استخراج النص الإنجليزي وترتيب الأسطر هندسياً من الأعلى للأسفل وتحديد الدور السياقي للصفحة
  Future<ExercisePageItem> extractPageItemFromFile({
    required File imageFile,
    required int pageNumberHint,
  }) async {
    final InputImage inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    final List<TextLine> allLines = [];
    for (final TextBlock block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }

    // ترتيب الأسطر هندسياً من الأعلى للأسفل ومن اليسار لليمين للخيارات الأفقية
    allLines.sort((a, b) {
      final double dy = a.boundingBox.top - b.boundingBox.top;
      if (dy.abs() < 12.0) {
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      }
      return dy.compareTo(0.0);
    });

    final List<String> cleanedLines = allLines
        .map((line) => _normalizeOcrLine(line.text))
        .where((line) => line.isNotEmpty)
        .toList();

    final String fullStructuredText = cleanedLines.join('\n');
    final String autoRole = _inferPageContextualRole(fullStructuredText, pageNumberHint);

    return ExercisePageItem(
      id: '${DateTime.now().microsecondsSinceEpoch}_$pageNumberHint',
      imageFile: imageFile,
      extractedText: fullStructuredText,
      lines: cleanedLines,
      pageRoleLabel: autoRole,
    );
  }

  /// استنتاج دور الصفحة تلقائياً لمساعدة النموذج اللغوي على ربط السياق بين الصور
  String _inferPageContextualRole(String text, int pageNumber) {
    final lower = text.toLowerCase();
    if (lower.contains('read the following') ||
        lower.contains('passage') ||
        (text.length > 350 && !text.contains('_____'))) {
      return 'قطعة القراءة / السياق (Reading Passage)';
    }
    if (lower.contains('word bank') || lower.contains('box below')) {
      return 'صندوق المفردات (Word Bank)';
    }
    if (text.contains('_____') ||
        RegExp(r'\b[a-dA-D][\)\.]').hasMatch(text) ||
        lower.contains('choose') ||
        lower.contains('complete')) {
      return 'أسئلة التمرين (Exercise Questions)';
    }
    return 'الجزء $pageNumber من التمرين';
  }

  /// تنظيف أخطاء الـ OCR الشائعة في تمارين القواعد (مثل الفراغات المنقطة والأقواس)
  String _normalizeOcrLine(String raw) {
    String text = raw.trim();
    text = text.replaceAll(RegExp(r'[.…]{3,}'), ' _____ ');
    text = text.replaceAll(RegExp(r'_{2,}'), ' _____ ');
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ');
    return text.trim();
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
