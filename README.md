# تطبيق معلم الإنجليزية الذكي بدون إنترنت (Offline English Tutor - Flutter)

مشروع Flutter متكامل يعمل محلياً 100% على الهاتف (بدون إنترنت بعد التحميل الأول للنموذج) لحل تمارين قواعد ومفردات اللغة الإنجليزية من الصور عبر مرحلتين:
1. **المرحلة الأولى (العيون - OCR & Image Cropping):** التقاط الصورة وقص السؤال بدقة عبر [image_cropper](https://pub.dev/packages/image_cropper) ثم استخراج النص الإنجليزي وترتيبه هندسياً عبر [google_mlkit_text_recognition](https://pub.dev/packages/google_mlkit_text_recognition).
2. **المرحلة الثانية (العقل - Local GGUF LLM):** تمرير النص المستخرج (بعد إتاحة تعديله يدوياً) إلى نموذج لغوي محلي بصيغة `GGUF` (`Q4_K_M`) يعمل عبر `llama.cpp` ([flutter_llama](https://pub.dev/packages/flutter_llama) و [llama_cpp_dart](https://pub.dev/packages/llama_cpp_dart)) مع توليد متدفق للكلمات (Streaming Token Generation).

## هيكلية ملفات المشروع
- `pubspec.yaml`: تعريف كافة الحزم والمكتبات المعتمدة.
- `lib/models/gguf_model_info.dart`: إعدادات نماذج `Phi-3.5-mini-instruct-Q4_K_M.gguf` و `Qwen2.5-3B-Instruct-Q4_K_M.gguf` و `gemma-2-2b-it-Q4_K_M.gguf` مع روابط التحميل المباشرة من Hugging Face.
- `lib/services/model_download_service.dart`: خدمة تحميل ملفات `GGUF` عبر `Dio` مع دعم استئناف التحميل الجزئي (`HTTP Range .part`) وحساب السرعة.
- `lib/services/ocr_crop_service.dart`: خدمة قص الصورة واستخراج النص اللاتيني وترتيب الأسطر وتنظيف الفراغات النحوية.
- `lib/services/prompt_builder_service.dart`: هندسة الأوامر (`System Prompt`) بصيغتي `ChatML` و `Gemma-2`.
- `lib/services/local_llm_service.dart`: خدمة شحن النموذج في الذاكرة (`RAM/GPU`) وتوليد الحل المتدفق (`Stream<String>`) بدرجة عشوائية منخفضة (`temperature: 0.15`).
- `lib/main.dart`: واجهة المستخدم الكاملة باللغة العربية (`RTL`) مع محرر نص التمرين (`LTR`) وإعدادات المحرك.
- `android/` و `ios/`: ملفات الصلاحيات والـ NDK (`AndroidManifest.xml`, `build.gradle`, `Info.plist`).
