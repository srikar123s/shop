import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceSearchService {
  VoiceSearchService._();
  static final VoiceSearchService instance = VoiceSearchService._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (err) => debugPrint('Speech recognition error: $err'),
        onStatus: (status) => debugPrint('Speech recognition status: $status'),
      );
      return _isInitialized;
    } catch (e) {
      debugPrint('Failed to initialize speech: $e');
      _isInitialized = false;
      return false;
    }
  }

  bool get isListening => _speech.isListening;

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  /// Opens an interactive animated dialog that listens for speech and returns the spoken text.
  Future<String?> recordSpeech(
    BuildContext context, {
    String title = 'Voice Search',
    String hint = 'Say product or customer name...',
    String initialLocale = 'en_IN',
  }) async {
    final available = await initialize();
    if (!context.mounted) return null;

    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice recognition not available. Please grant microphone permission.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return null;
    }

    final currentLang = Localizations.localeOf(context).languageCode;
    final defaultLocale = initialLocale != 'en_IN'
        ? initialLocale
        : (currentLang == 'te' ? 'te_IN' : 'en_IN');

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _VoiceSearchDialog(
        speech: _speech,
        title: title,
        hint: hint,
        initialLocale: defaultLocale,
      ),
    );
  }
}

class _VoiceSearchDialog extends StatefulWidget {
  const _VoiceSearchDialog({
    required this.speech,
    required this.title,
    required this.hint,
    this.initialLocale = 'en_IN',
  });

  final stt.SpeechToText speech;
  final String title;
  final String hint;
  final String initialLocale;

  @override
  State<_VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<_VoiceSearchDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String _recognizedText = '';
  bool _isListening = false;
  Timer? _silenceTimer;
  late String _selectedLocale;

  @override
  void initState() {
    super.initState();
    _selectedLocale = widget.initialLocale;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startListening();
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _pulseController.dispose();
    widget.speech.stop();
    super.dispose();
  }

  Future<void> _changeLocale(String loc) async {
    _silenceTimer?.cancel();
    await widget.speech.stop();
    setState(() {
      _selectedLocale = loc;
      _recognizedText = '';
    });
    await _startListening();
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _recognizedText = '';
    });

    try {
      await widget.speech.listen(
        // ignore: deprecated_member_use
        localeId: _selectedLocale,
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _recognizedText = result.recognizedWords;
          });

          // Reset silence timer on new words
          _silenceTimer?.cancel();
          if (result.finalResult && _recognizedText.trim().isNotEmpty) {
            _submit(_recognizedText.trim());
          } else {
            // Auto submit after 1.5 seconds of silence
            _silenceTimer = Timer(const Duration(milliseconds: 1500), () {
              if (mounted && _recognizedText.trim().isNotEmpty) {
                _submit(_recognizedText.trim());
              }
            });
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('Error starting listening: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  void _submit(String text) {
    widget.speech.stop();
    if (mounted) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mic, color: Color(0xFF0F766E), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    widget.speech.stop();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('English', style: TextStyle(fontSize: 11)),
                  selected: _selectedLocale == 'en_IN',
                  onSelected: (val) {
                    if (val) _changeLocale('en_IN');
                  },
                ),
                ChoiceChip(
                  label: const Text('తెలుగు', style: TextStyle(fontSize: 11)),
                  selected: _selectedLocale == 'te_IN',
                  onSelected: (val) {
                    if (val) _changeLocale('te_IN');
                  },
                ),
                ChoiceChip(
                  label: const Text('हिन्दी', style: TextStyle(fontSize: 11)),
                  selected: _selectedLocale == 'hi_IN',
                  onSelected: (val) {
                    if (val) _changeLocale('hi_IN');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: () {
                  if (_isListening) {
                    if (_recognizedText.trim().isNotEmpty) {
                      _submit(_recognizedText.trim());
                    } else {
                      widget.speech.stop();
                      setState(() => _isListening = false);
                    }
                  } else {
                    _startListening();
                  }
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _isListening
                        ? const Color(0xFF0F766E)
                        : Colors.grey.shade400,
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (_isListening)
                        BoxShadow(
                          color:
                              const Color(0xFF0F766E).withValues(alpha: 0.35),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _recognizedText.isNotEmpty
                  ? '"$_recognizedText"'
                  : (_isListening ? 'Listening... Speak now' : 'Tap mic to speak'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: _recognizedText.isNotEmpty
                    ? FontWeight.bold
                    : FontWeight.w500,
                color: _recognizedText.isNotEmpty
                    ? const Color(0xFF0F766E)
                    : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.hint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
            if (_recognizedText.isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _submit(_recognizedText.trim()),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('SEARCH NOW'),
              ),
          ],
        ),
      ),
    );
  }
}
