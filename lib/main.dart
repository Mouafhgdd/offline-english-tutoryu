import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'models/exercise_page_item.dart';
import 'models/gguf_model_info.dart';
import 'services/local_llm_service.dart';
import 'services/model_download_service.dart';
import 'services/ocr_crop_service.dart';
import 'services/prompt_builder_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OfflineEnglishTutorApp());
}

class OfflineEnglishTutorApp extends StatelessWidget {
  const OfflineEnglishTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'معلم الإنجليزية الذكي (Offline AI)',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const TutorHomePage(),
    );
  }
}

class TutorHomePage extends StatefulWidget {
  const TutorHomePage({super.key});

  @override
  State<TutorHomePage> createState() => _TutorHomePageState();
}

class _TutorHomePageState extends State<TutorHomePage> {
  final OcrCropService _ocrService = OcrCropService();
  final ModelDownloadService _downloadService = ModelDownloadService();
  final LocalLlmService _llmService = LocalLlmService();
  final TextEditingController _combinedOcrController = TextEditingController();

  GgufModelInfo _selectedModel = GgufModelInfo.presets.first;
  LlmBackendEngine _selectedBackend = LlmBackendEngine.flutterLlamaGpu;

  bool _isModelDownloaded = false;
  bool _isDownloadingModel = false;
  bool _isLoadingModelIntoRam = false;
  double _downloadProgress = 0.0;
  double _downloadSpeedMbPerSec = 0.0;
  double _downloadedSizeMb = 0.0;

  // قائمة صفحات/صور التمرين المرتبة مع الحفاظ على السياق المتسلسل
  final List<ExercisePageItem> _exercisePages = [];
  bool _isRunningOcr = false;
  bool _isGeneratingSolution = false;
  double _temperature = 0.15;
  String _aiSolution = '';
  String _statusBanner = 'جاري التحقق من حالة النموذج المحلي...';

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
  }

  /// التحقق من وجود ملف GGUF على ذاكرة الهاتف وتحديث الواجهة
  Future<void> _checkModelStatus() async {
    final bool downloaded = await _downloadService.isModelDownloaded(_selectedModel);
    final double sizeMb = await _downloadService.getDownloadedFileSizeMb(_selectedModel);

    if (!mounted) return;
    setState(() {
      _isModelDownloaded = downloaded;
      _downloadedSizeMb = sizeMb;
      _statusBanner = downloaded
          ? 'النموذج (${_selectedModel.name}) جاهز على الهاتف (${(sizeMb / 1024).toStringAsFixed(2)} GB).'
          : 'النموذج غير محمّل بعد. قم بتحميله مرة واحدة ليعمل التطبيق للأبد بدون إنترنت.';
    });

    if (downloaded && !_llmService.isModelLoaded) {
      await _initializeLocalEngine();
    }
  }

  /// تحميل ملف النموذج من HuggingFace مع شريط التقدم ودعم الاستئناف
  Future<void> _startModelDownload() async {
    setState(() {
      _isDownloadingModel = true;
      _downloadProgress = 0.0;
      _statusBanner = 'جاري تحميل ${_selectedModel.fileName}...';
    });

    try {
      await _downloadService.downloadModel(
        model: _selectedModel,
        onProgress: (int received, int total, double speedMb) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = total > 0 ? received / total : 0.0;
            _downloadedSizeMb = received / (1024 * 1024);
            _downloadSpeedMbPerSec = speedMb;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isDownloadingModel = false;
        _isModelDownloaded = true;
        _statusBanner = 'اكتمل تحميل النموذج بنجاح! جاري تهيئة المحرك...';
      });

      await _initializeLocalEngine();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloadingModel = false;
        _statusBanner = 'توقف التحميل (يمكنك استئنافه من حيث توقف): $e';
      });
    }
  }

  /// شحن النموذج في الذاكرة العشوائية (RAM / GPU) بسياق 4096 لدعم عدة صور
  Future<void> _initializeLocalEngine() async {
    setState(() {
      _isLoadingModelIntoRam = true;
      _statusBanner = 'جاري تهيئة محرك Llama.cpp وشحن النموذج في الذاكرة...';
    });

    try {
      final String path = await _downloadService.getModelFilePath(_selectedModel);
      await _llmService.loadModel(
        modelPath: path,
        modelInfo: _selectedModel,
        backend: _selectedBackend,
        contextSize: 4096,
        threads: 4,
        useGpu: true,
      );

      if (!mounted) return;
      setState(() {
        _isLoadingModelIntoRam = false;
        _statusBanner = 'المحرك الذكي متصل ويعمل محلياً 100% بدون إنترنت!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingModelIntoRam = false;
        _statusBanner = 'تعذر شحن النموذج في الذاكرة: $e';
      });
    }
  }

  /// إعادة بناء النص المدمج كلما أضيفت صورة أو تغير ترتيب الصور
  void _rebuildCombinedContextText() {
    _combinedOcrController.text =
        PromptBuilderService.combineOrderedPagesText(_exercisePages);
  }

  /// إضافة صورة جديدة من الكاميرا وإلحاقها بنهاية سلسلة الصور الحالية
  Future<void> _addSinglePageFromCamera() async {
    try {
      setState(() {
        _isRunningOcr = true;
        _statusBanner = 'جاري التقاط وقص الصفحة رقم ${_exercisePages.length + 1}...';
      });

      final ExercisePageItem? newItem = await _ocrService.pickAndProcessSinglePage(
        source: ImageSource.camera,
        primaryColor: Theme.of(context).colorScheme.primary,
        pageNumberHint: _exercisePages.length + 1,
      );

      if (!mounted) return;
      if (newItem == null) {
        setState(() {
          _isRunningOcr = false;
          _statusBanner = 'تم إلغاء إضافة الصورة.';
        });
        return;
      }

      setState(() {
        _exercisePages.add(newItem);
        _isRunningOcr = false;
        _rebuildCombinedContextText();
        _statusBanner =
            'تمت إضافة الصفحة (${_exercisePages.length}) بنجاح! يمكنك إضافة المزيد من الصور أو تعديل ترتيبها.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRunningOcr = false;
        _statusBanner = 'حدث خطأ أثناء التقاط الصورة: $e';
      });
    }
  }

  /// اختيار عدة صور دفعة واحدة من المعرض وقصها واستخراج نصوصها بالتتابع
  Future<void> _addMultiplePagesFromGallery() async {
    try {
      setState(() {
        _isRunningOcr = true;
        _statusBanner = 'اختر صورة أو عدة صور مرتبة من المعرض...';
      });

      final List<ExercisePageItem> newItems =
          await _ocrService.pickAndProcessMultipleGalleryPages(
        primaryColor: Theme.of(context).colorScheme.primary,
        startingPageNumber: _exercisePages.length + 1,
        onPageProgress: (int current, int total) {
          if (!mounted) return;
          setState(() {
            _statusBanner = 'جاري قص وقراءة الصورة $current من $total...';
          });
        },
      );

      if (!mounted) return;
      if (newItems.isEmpty) {
        setState(() {
          _isRunningOcr = false;
          _statusBanner = 'لم يتم اختيار صور جديدة.';
        });
        return;
      }

      setState(() {
        _exercisePages.addAll(newItems);
        _isRunningOcr = false;
        _rebuildCombinedContextText();
        _statusBanner =
            'تمت قراءة ودمج ${newItems.length} صور بنجاح (إجمالي الصفحات: ${_exercisePages.length}). يمكنك سحب البطاقات لتغيير ترتيبها.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRunningOcr = false;
        _statusBanner = 'حدث خطأ أثناء معالجة الصور المتعددة: $e';
      });
    }
  }

  /// إعادة قص صورة معينة داخل القائمة وتحديث نصها ضمن السياق العام
  Future<void> _recropExistingPage(int index) async {
    final ExercisePageItem current = _exercisePages[index];
    final File? recropped = await _ocrService.cropImageFile(
      sourcePath: current.imageFile.path,
      primaryColor: Theme.of(context).colorScheme.primary,
      toolbarTitle: 'إعادة قص الصفحة (${index + 1})',
    );
    if (recropped == null) return;

    setState(() => _isRunningOcr = true);
    final ExercisePageItem updated = await _ocrService.extractPageItemFromFile(
      imageFile: recropped,
      pageNumberHint: index + 1,
    );

    if (!mounted) return;
    setState(() {
      _exercisePages[index] = updated;
      _isRunningOcr = false;
      _rebuildCombinedContextText();
      _statusBanner = 'تم تحديث نص الصفحة (${index + 1}) وإعادة بناء السياق.';
    });
  }

  /// تحريك صورة للأعلى أو للأسفل (أو بالسحب والإفلات) مع تحديث السياق فوراً
  void _reorderPages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final ExercisePageItem moved = _exercisePages.removeAt(oldIndex);
      _exercisePages.insert(newIndex, moved);
      _rebuildCombinedContextText();
      _statusBanner =
          'تم تحديث ترتيب الصور وإعادة ربط السياق من الصفحة 1 إلى الصفحة ${_exercisePages.length}.';
    });
  }

  /// حذف صورة واحدة من السلسلة
  void _removePageAt(int index) {
    setState(() {
      _exercisePages.removeAt(index);
      _rebuildCombinedContextText();
    });
  }

  /// مسح جميع الصور والبدء بتمرين جديد
  void _clearAllPages() {
    setState(() {
      _exercisePages.clear();
      _combinedOcrController.clear();
      _aiSolution = '';
      _statusBanner = 'تم مسح الصور. يمكنك تصوير تمرين جديد الآن.';
    });
  }

  /// المرحلة الثانية: تمرير السياق المدمج لكافة الصور بالترتيب إلى النموذج المحلي
  Future<void> _solveExerciseWithStreaming() async {
    final String combinedText = _combinedOcrController.text.trim();
    if (combinedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إضافة صورة واحدة أو أكثر للتمرين أولاً.')),
      );
      return;
    }

    if (!_llmService.isModelLoaded) {
      if (_isModelDownloaded) {
        await _initializeLocalEngine();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى تحميل ملف النموذج (GGUF) أولاً ليعمل التطبيق بدون إنترنت.'),
          ),
        );
        return;
      }
    }

    setState(() {
      _isGeneratingSolution = true;
      _aiSolution = '';
      _statusBanner =
          'جاري تحليل السياق المتسلسل لـ (${_exercisePages.isEmpty ? 1 : _exercisePages.length}) صفحات وتوليد الحل...';
    });

    try {
      final Stream<String> tokenStream = _llmService.solveExerciseStream(
        combinedExerciseText: combinedText,
        totalPagesCount: _exercisePages.isEmpty ? 1 : _exercisePages.length,
        modelInfo: _selectedModel,
        temperature: _temperature,
      );

      await for (final String token in tokenStream) {
        if (!mounted) break;
        setState(() {
          _aiSolution += token;
        });
      }

      if (!mounted) return;
      setState(() {
        _isGeneratingSolution = false;
        _statusBanner = 'اكتمل حل التمرين متعدد الصفحات وشرح القواعد بنجاح!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingSolution = false;
        _statusBanner = 'حدث خطأ أثناء تشغيل النموذج المحلي: $e';
      });
    }
  }

  @override
  void dispose() {
    _combinedOcrController.dispose();
    _ocrService.dispose();
    _llmService.unloadModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('معلم الإنجليزية الذكي (Offline AI)'),
          centerTitle: true,
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'إعدادات المحرك والحرارة',
              icon: const Icon(Icons.tune),
              onPressed: _showEngineSettingsSheet,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. بطاقة إدارة وتحميل نموذج الذكاء الاصطناعي
              _buildModelManagerCard(colorScheme),
              const SizedBox(height: 16),

              // 2. أزرار إضافة الصور (إضافة صورة بالكاميرا + اختيار عدة صور من المعرض)
              _buildCaptureButtonsRow(),
              const SizedBox(height: 16),

              // 3. قائمة الصور المرتبة القابلة لإعادة الترتيب بالسحب والإفلات أو الأسهم
              if (_exercisePages.isNotEmpty) ...[
                _buildOrderedPagesQueueCard(colorScheme),
                const SizedBox(height: 16),
              ],

              // 4. صندوق السياق المدمج لكافة الصور بالترتيب (قابل للتعديل اليدوي)
              _buildEditableCombinedContextSection(colorScheme),
              const SizedBox(height: 16),

              // 5. بطاقة الحل والشرح المتدفق (Streaming Solution Card)
              if (_isRunningOcr)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_aiSolution.isNotEmpty || _isGeneratingSolution)
                _buildStreamingSolutionCard(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelManagerCard(ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _llmService.isModelLoaded ? Icons.check_circle : Icons.memory,
                  color: _llmService.isModelLoaded ? Colors.green.shade700 : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'إدارة النموذج اللغوي المحلي (GGUF Q4_K_M)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<GgufModelInfo>(
              value: _selectedModel,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'اختر النموذج المناسب لهاتفك',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: GgufModelInfo.presets.map((model) {
                return DropdownMenuItem<GgufModelInfo>(
                  value: model,
                  child: Text(
                    '${model.name} (${model.expectedSizeGb} GB)',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                );
              }).toList(),
              onChanged: (_isDownloadingModel || _isLoadingModelIntoRam)
                  ? null
                  : (GgufModelInfo? newModel) async {
                      if (newModel == null) return;
                      setState(() => _selectedModel = newModel);
                      await _checkModelStatus();
                    },
            ),
            const SizedBox(height: 8),
            Text(
              _selectedModel.descriptionAr,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusBanner,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            if (_isDownloadingModel) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_downloadProgress * 100).toStringAsFixed(1)}% (${_downloadedSizeMb.toStringAsFixed(0)} MB)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'السرعة: ${_downloadSpeedMbPerSec.toStringAsFixed(2)} MB/s',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!_isModelDownloaded && !_isDownloadingModel)
                  FilledButton.icon(
                    onPressed: _startModelDownload,
                    icon: const Icon(Icons.download),
                    label: const Text('تحميل النموذج على الهاتف'),
                  ),
                if (_isDownloadingModel)
                  OutlinedButton.icon(
                    onPressed: _downloadService.cancelDownload,
                    icon: const Icon(Icons.pause),
                    label: const Text('إيقاف مؤقت'),
                  ),
                if (_isModelDownloaded && !_llmService.isModelLoaded && !_isLoadingModelIntoRam)
                  FilledButton.icon(
                    onPressed: _initializeLocalEngine,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('تشغيل المحرك في الذاكرة'),
                  ),
                if (_isModelDownloaded && !_isDownloadingModel)
                  TextButton.icon(
                    onPressed: () async {
                      await _llmService.unloadModel();
                      await _downloadService.deleteModel(_selectedModel);
                      await _checkModelStatus();
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('حذف الملف', style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureButtonsRow() {
    final bool busy = _isRunningOcr || _isGeneratingSolution || _isLoadingModelIntoRam;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: busy ? null : _addSinglePageFromCamera,
            icon: const Icon(Icons.add_a_photo),
            label: Text(
              _exercisePages.isEmpty ? 'تصوير صفحة (1)' : 'تصوير صفحة (${_exercisePages.length + 1})',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: busy ? null : _addMultiplePagesFromGallery,
            icon: const Icon(Icons.collections),
            label: const Text('اختيار عدة صور (المعرض)'),
          ),
        ),
      ],
    );
  }

  /// واجهة إدارة وترتيب الصور المتعددة (Drag-and-Drop + Up/Down + Role Selector)
  Widget _buildOrderedPagesQueueCard(ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.format_list_numbered_rtl, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'تسلسل صور التمرين (${_exercisePages.length} صفحات):',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _clearAllPages,
                  icon: const Icon(Icons.delete_sweep, size: 18, color: Colors.red),
                  label: const Text('مسح الكل', style: TextStyle(color: Colors.red, fontSize: 13)),
                ),
              ],
            ),
            const Text(
              'اسحب البطاقات أو استخدم الأسهم لترتيب الصور (مثلاً: قطعة القراءة أولاً ثم الأسئلة ثانياً) للحفاظ على السياق:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _exercisePages.length,
              onReorder: _reorderPages,
              itemBuilder: (BuildContext context, int index) {
                final ExercisePageItem page = _exercisePages[index];
                return Card(
                  key: ValueKey(page.id),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  color: Colors.grey.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // شارة رقم الصفحة في السياق
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: colorScheme.primary,
                          foregroundColor: Colors.white,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // صورة مصغرة للصفحة المقصوصة
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            page.imageFile,
                            width: 58,
                            height: 58,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 10),

                        // تفاصيل الدور السياقي ومعاينة النص المستخرج
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isDense: true,
                                  value: [
                                    'قطعة القراءة / السياق (Reading Passage)',
                                    'صندوق المفردات (Word Bank)',
                                    'أسئلة التمرين (Exercise Questions)',
                                    'الجزء ${index + 1} من التمرين',
                                  ].contains(page.pageRoleLabel)
                                      ? page.pageRoleLabel
                                      : 'أسئلة التمرين (Exercise Questions)',
                                  items: [
                                    'قطعة القراءة / السياق (Reading Passage)',
                                    'صندوق المفردات (Word Bank)',
                                    'أسئلة التمرين (Exercise Questions)',
                                    'الجزء ${index + 1} من التمرين',
                                  ].map((role) {
                                    return DropdownMenuItem<String>(
                                      value: role,
                                      child: Text(
                                        role,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (String? newRole) {
                                    if (newRole == null) return;
                                    setState(() {
                                      page.pageRoleLabel = newRole;
                                      _rebuildCombinedContextText();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                page.extractedText.isEmpty
                                    ? '(لا يوجد نص مستخرج)'
                                    : page.extractedText.replaceAll('\n', ' '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),

                        // أزرار التحكم السريع بالصفحة (أعلى، أسفل، إعادة قص، حذف)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'تحريك للأعلى (تقديم في السياق)',
                                  icon: const Icon(Icons.arrow_upward, size: 18),
                                  onPressed: index > 0
                                      ? () => _reorderPages(index, index - 1)
                                      : null,
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'تحريك للأسفل (تأخير في السياق)',
                                  icon: const Icon(Icons.arrow_downward, size: 18),
                                  onPressed: index < _exercisePages.length - 1
                                      ? () => _reorderPages(index, index + 2)
                                      : null,
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'إعادة قص هذه الصورة',
                                  icon: const Icon(Icons.crop, size: 18, color: Colors.indigo),
                                  onPressed: () => _recropExistingPage(index),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'حذف هذه الصورة',
                                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                                  onPressed: () => _removePageAt(index),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableCombinedContextSection(ColorScheme colorScheme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'النص السياقي المدمج لكافة الصور بالترتيب (قابل للتعديل):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ),
                IconButton(
                  tooltip: 'إعادة توليد الدمج من الصور',
                  icon: const Icon(Icons.sync, size: 20),
                  onPressed: () => setState(_rebuildCombinedContextText),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _combinedOcrController,
                maxLines: 8,
                minLines: 4,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
                decoration: InputDecoration(
                  hintText:
                      '=== [Page 1 of 2 - Reading Passage] ===\n...\n=== [Page 2 of 2 - Exercise Questions] ===\n...',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isGeneratingSolution ? null : _solveExerciseWithStreaming,
                    icon: const Icon(Icons.psychology),
                    label: Text(
                      _exercisePages.length > 1
                          ? 'حل التمرين المتسلسل (${_exercisePages.length} صفحات) الآن'
                          : 'حل التمرين وشرح القواعد الآن',
                    ),
                  ),
                ),
                if (_isGeneratingSolution) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _llmService.stopGeneration,
                    icon: const Icon(Icons.stop, color: Colors.red),
                    label: const Text('إيقاف'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingSolutionCard(ColorScheme colorScheme) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.school, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'الحل المتسلسل والشرح النحوي:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'نسخ الحل',
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _aiSolution));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ الشرح إلى الحافظة.')),
                    );
                  },
                ),
              ],
            ),
            const Divider(),
            SelectableText(
              _aiSolution.isEmpty ? 'جاري قراءة السياق المتعدد وتوليد الحل...' : _aiSolution,
              style: const TextStyle(fontSize: 15.5, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  void _showEngineSettingsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إعدادات محرك الذكاء الاصطناعي المحلي',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    const SizedBox(height: 16),
                    Text('درجة العشوائية (Temperature): ${_temperature.toStringAsFixed(2)}'),
                    const Text(
                      'يُنصح بقيمة بين 0.10 و 0.20 لضمان إجابات قواعدية صارمة ودقيقة بدون هلوسة.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Slider(
                      value: _temperature,
                      min: 0.05,
                      max: 0.80,
                      divisions: 15,
                      label: _temperature.toStringAsFixed(2),
                      onChanged: (double value) {
                        setModalState(() => _temperature = value);
                        setState(() => _temperature = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('واجهة الربط البرمجية (FFI Backend):'),
                    RadioListTile<LlmBackendEngine>(
                      title: const Text('flutter_llama (تسريع GPU Vulkan / Metal)'),
                      value: LlmBackendEngine.flutterLlamaGpu,
                      groupValue: _selectedBackend,
                      onChanged: (val) {
                        if (val == null) return;
                        setModalState(() => _selectedBackend = val);
                        setState(() => _selectedBackend = val);
                      },
                    ),
                    RadioListTile<LlmBackendEngine>(
                      title: const Text('llama_cpp_dart (Managed Isolate)'),
                      value: LlmBackendEngine.llamaCppDartIsolate,
                      groupValue: _selectedBackend,
                      onChanged: (val) {
                        if (val == null) return;
                        setModalState(() => _selectedBackend = val);
                        setState(() => _selectedBackend = val);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
