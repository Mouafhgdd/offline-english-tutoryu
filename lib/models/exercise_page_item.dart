import 'dart:io';

/// نموذج يمثل صورة/صفحة واحدة ضمن سلسلة صور التمرين مع الحفاظ على ترتيبها وسياقها
class ExercisePageItem {
  final String id;
  File imageFile;
  String extractedText;
  List<String> lines;
  String pageRoleLabel; // مثال: "قطعة القراءة (Passage)" أو "الأسئلة (Questions)" أو "تتمة التمرين"

  ExercisePageItem({
    required this.id,
    required this.imageFile,
    required this.extractedText,
    required this.lines,
    this.pageRoleLabel = 'صفحة تمرين',
  });
}
