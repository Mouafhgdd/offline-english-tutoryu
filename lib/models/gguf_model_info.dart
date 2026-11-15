/// تعريف نماذج GGUF المقترحة للعمل محلياً على الهاتف بتقنية 4-bit Quantization (Q4_K_M)
enum PromptTemplateFormat {
  chatML, // متوافق مع Phi-3.5 و Qwen2.5
  gemma2, // متوافق مع Gemma-2
}

class GgufModelInfo {
  final String id;
  final String name;
  final String fileName;
  final String descriptionAr;
  final double expectedSizeGb;
  final int minRamGb;
  final String downloadUrl;
  final String repoPageUrl;
  final PromptTemplateFormat templateFormat;

  const GgufModelInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.descriptionAr,
    required this.expectedSizeGb,
    required this.minRamGb,
    required this.downloadUrl,
    required this.repoPageUrl,
    required this.templateFormat,
  });

  /// قائمة النماذج المعتمدة والمختبرة لحل تمارين القواعد والمفردات الإنجليزية
  static const List<GgufModelInfo> presets = [
    GgufModelInfo(
      id: 'phi_3_5_mini',
      name: 'Phi-3.5 Mini Instruct (Q4_K_M)',
      fileName: 'Phi-3.5-mini-instruct-Q4_K_M.gguf',
      descriptionAr: 'الخيار الأول (الأفضل للقواعد والتمارين متعددة الصفحات - 2.23 GB)',
      expectedSizeGb: 2.23,
      minRamGb: 6,
      downloadUrl:
          'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      repoPageUrl: 'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF',
      templateFormat: PromptTemplateFormat.chatML,
    ),
    GgufModelInfo(
      id: 'qwen_2_5_3b',
      name: 'Qwen2.5 3B Instruct (Q4_K_M)',
      fileName: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      descriptionAr: 'الخيار المتوازن (سريع جداً وممتاز في الشرح بالعربية والإنجليزية - 1.93 GB)',
      expectedSizeGb: 1.93,
      minRamGb: 4,
      downloadUrl:
          'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      repoPageUrl: 'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF',
      templateFormat: PromptTemplateFormat.chatML,
    ),
    GgufModelInfo(
      id: 'gemma_2_2b',
      name: 'Gemma-2 2B Instruct (Q4_K_M)',
      fileName: 'gemma-2-2b-it-Q4_K_M.gguf',
      descriptionAr: 'الخيار الأخف (مثالي للهواتف المتوسطة والضعيفة - 1.71 GB)',
      expectedSizeGb: 1.71,
      minRamGb: 4,
      downloadUrl:
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      repoPageUrl: 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF',
      templateFormat: PromptTemplateFormat.gemma2,
    ),
  ];
}
