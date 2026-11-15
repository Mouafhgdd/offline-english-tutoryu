import '../models/exercise_page_item.dart';
import '../models/gguf_model_info.dart';

/// خدمة هندسة الأوامر وبناء السياق المتسلسل للصور المتعددة (Multi-Image Context Stitching)
class PromptBuilderService {
  static const String systemInstruction = '''
You are an expert English Grammar, Reading Comprehension, and Vocabulary Teacher.
The user will provide text extracted from ONE or MULTIPLE ordered images (Pages/Parts) of an English exercise.
CRITICAL MULTI-IMAGE CONTEXT RULES:
1. Treat [Page 1], [Page 2], etc. as a single continuous, connected exercise in strict chronological order.
2. If an earlier image contains a reading passage, grammar rule box, word bank, or context paragraph, use that exact context to answer the questions in subsequent images.
3. If a sentence or question is split across the bottom of [Page N] and the top of [Page N+1], seamlessly merge and reconstruct it before solving.
4. Clean up any minor OCR typos, solve every question in order, and provide a clear English explanation followed by a brief Arabic explanation (شرح مبسط بالعربية) and the grammar formula.''';

  /// دمج نصوص الصور المتعددة بترتيبها الحالي مع فواصل سياقية واضحة للنموذج والطالب
  static String combineOrderedPagesText(List<ExercisePageItem> orderedPages) {
    if (orderedPages.isEmpty) return '';
    if (orderedPages.length == 1) {
      return orderedPages.first.extractedText.trim();
    }

    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < orderedPages.length; i++) {
      final page = orderedPages[i];
      final int pageNum = i + 1;
      buffer.writeln(
        '=== [Page $pageNum of ${orderedPages.length} - ${page.pageRoleLabel}] ===',
      );
      buffer.writeln(page.extractedText.trim());
      if (i < orderedPages.length - 1) {
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  /// بناء الأمر الموجه النهائي حسب صيغة القالب الخاصة بالنموذج المختار (ChatML أو Gemma-2)
  static String buildPrompt({
    required String combinedExerciseText,
    required int totalPagesCount,
    required PromptTemplateFormat format,
  }) {
    final String cleanedInput = combinedExerciseText.trim();
    final String multiPageNote = totalPagesCount > 1
        ? 'Note: This exercise spans $totalPagesCount ordered images. Maintain full context across all pages (e.g., reading passages, word banks, or split sentences from Page 1 to Page $totalPagesCount).'
        : 'Solve this English exercise accurately and explain each answer:';

    switch (format) {
      case PromptTemplateFormat.chatML:
        // متوافق مع Phi-3.5-mini و Qwen2.5-3B
        return '''<|system|>
$systemInstruction<|end|>
<|user|>
$multiPageNote

$cleanedInput<|end|>
<|assistant|>
''';

      case PromptTemplateFormat.gemma2:
        // متوافق مع Gemma-2-2B-It
        return '''<start_of_turn>user
$systemInstruction

$multiPageNote

$cleanedInput<end_of_turn>
<start_of_turn>model
''';
    }
  }
}
