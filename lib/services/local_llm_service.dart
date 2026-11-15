import 'dart:async';
import 'dart:io';
import 'package:flutter_llama/flutter_llama.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import '../models/gguf_model_info.dart';
import 'prompt_builder_service.dart';

/// أوضاع تشغيل المحرك المحلي لدعم كل من flutter_llama (مع تسريع GPU) و llama_cpp_dart (Isolate)
enum LlmBackendEngine {
  flutterLlamaGpu, // تسريع Vulkan على أندرويد و Metal على iOS عبر مكتبة flutter_llama
  llamaCppDartIsolate, // تشغيل عبر Managed Isolate في مكتبة llama_cpp_dart
}

/// خدمة المرحلة الثانية (العقل - Local LLM Engine) مع سياق موسّع (4096 Tokens) لدعم الصور المتعددة
class LocalLlmService {
  final FlutterLlama _flutterLlama = FlutterLlama.instance;
  LlamaParent? _llamaIsolateParent;

  String? _loadedModelPath;
  LlmBackendEngine _activeBackend = LlmBackendEngine.flutterLlamaGpu;
  bool _isGenerating = false;

  bool get isModelLoaded => _loadedModelPath != null;
  bool get isGenerating => _isGenerating;
  String? get loadedModelPath => _loadedModelPath;
  LlmBackendEngine get activeBackend => _activeBackend;

  /// تهيئة وتحميل ملف GGUF في الذاكرة العشوائية (RAM/VRAM)
  /// تم رفع contextSize الافتراضي إلى 4096 لاستيعاب نصوص عدة صور متتالية مع الشرح المفصل
  Future<void> loadModel({
    required String modelPath,
    required GgufModelInfo modelInfo,
    LlmBackendEngine backend = LlmBackendEngine.flutterLlamaGpu,
    int contextSize = 4096,
    int threads = 4,
    bool useGpu = true,
  }) async {
    if (!await File(modelPath).exists()) {
      throw Exception('ملف النموذج غير موجود في المسار: $modelPath');
    }

    if (_loadedModelPath == modelPath && _activeBackend == backend) {
      return;
    }

    await unloadModel();
    _activeBackend = backend;

    if (backend == LlmBackendEngine.flutterLlamaGpu) {
      final config = LlamaConfig(
        modelPath: modelPath,
        nThreads: threads,
        nGpuLayers: useGpu ? -1 : 0,
        contextSize: contextSize,
        batchSize: 512,
        useGpu: useGpu,
        verbose: false,
      );

      final bool success = await _flutterLlama.loadModel(config);
      if (!success) {
        throw Exception('تعذر تحميل نموذج GGUF في الذاكرة. تأكد من توفر مساحة كافية في الـ RAM.');
      }
    } else {
      final modelParams = ModelParams();
      final contextParams = ContextParams()..nCtx = contextSize;
      final samplerParams = SamplerParams()
        ..temp = 0.15
        ..topP = 0.90
        ..topK = 40;

      final loadCommand = LlamaLoad(
        path: modelPath,
        modelParams: modelParams,
        contextParams: contextParams,
        samplingParams: samplerParams,
        format: modelInfo.templateFormat == PromptTemplateFormat.gemma2
            ? GemmaChatFormat()
            : ChatMLFormat(),
      );

      _llamaIsolateParent = LlamaParent(loadCommand);
      await _llamaIsolateParent!.init();
    }

    _loadedModelPath = modelPath;
  }

  /// توليد الحل بشكل متدفق كلمة بكلمة (Streaming Token Generation) مع الحفاظ على سياق الصور المرتبة
  Stream<String> solveExerciseStream({
    required String combinedExerciseText,
    required int totalPagesCount,
    required GgufModelInfo modelInfo,
    double temperature = 0.15,
    int maxTokens = 1200,
  }) async* {
    if (!isModelLoaded) {
      throw Exception('يرجى تحميل نموذج الذكاء الاصطناعي أولاً قبل بدء الحل.');
    }

    _isGenerating = true;
    final String fullPrompt = PromptBuilderService.buildPrompt(
      combinedExerciseText: combinedExerciseText,
      totalPagesCount: totalPagesCount,
      format: modelInfo.templateFormat,
    );

    try {
      if (_activeBackend == LlmBackendEngine.flutterLlamaGpu) {
        final params = GenerationParams(
          prompt: fullPrompt,
          temperature: temperature,
          topP: 0.90,
          topK: 40,
          maxTokens: maxTokens,
          repeatPenalty: 1.12,
          stopSequences: const ['<|end|>', '<|user|>', '<end_of_turn>', '</s>'],
        );

        await for (final String token in _flutterLlama.generateStream(params)) {
          if (!_isGenerating) break;
          yield token;
        }
      } else {
        if (_llamaIsolateParent == null) {
          throw Exception('محرك LlamaParent Isolate غير مهيأ.');
        }

        final StreamController<String> controller = StreamController<String>();
        late StreamSubscription<String> sub;

        sub = _llamaIsolateParent!.stream.listen(
          (String token) {
            if (!_isGenerating) {
              sub.cancel();
              controller.close();
              return;
            }
            controller.add(token);
          },
          onError: (Object err) {
            controller.addError(err);
            controller.close();
          },
          onDone: () {
            controller.close();
          },
        );

        _llamaIsolateParent!.sendPrompt(fullPrompt);

        await for (final String token in controller.stream) {
          yield token;
        }
        await sub.cancel();
      }
    } finally {
      _isGenerating = false;
    }
  }

  void stopGeneration() {
    _isGenerating = false;
  }

  Future<void> unloadModel() async {
    _isGenerating = false;
    if (_loadedModelPath != null) {
      if (_activeBackend == LlmBackendEngine.flutterLlamaGpu) {
        await _flutterLlama.unloadModel();
      } else {
        _llamaIsolateParent = null;
      }
      _loadedModelPath = null;
    }
  }
}
