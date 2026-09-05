import 'package:emotion_app/core/app_colors.dart';
import 'package:emotion_app/core/daily_check_in_service.dart';
import 'package:emotion_app/core/emotion_label_extractor.dart';
import 'package:emotion_app/services/daily_reminder_service.dart';
import 'package:emotion_app/services/liara_emotion_service.dart';
import 'package:emotion_app/widgets/app_text_field.dart';
import 'package:emotion_app/widgets/daily_check_in_sheet.dart';
import 'package:emotion_app/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import 'analysis_loading_screen.dart';
import 'analysis_result_screen.dart';
import 'about_screen.dart';
import 'emotion_trends_screen.dart';
import 'help_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final textCtrl = TextEditingController();
  final historyBox = Hive.box('history');
  final _emotionService = LiaraEmotionService();
  final _imagePicker = ImagePicker();
  final _checkInService = DailyCheckInService();
  final _reminderService = DailyReminderService();

  DailyCheckInSnapshot _checkIn = const DailyCheckInSnapshot(
    streak: 0,
    checkedInToday: false,
    longestStreak: 0,
  );
  bool _didPromptCheckIn = false;

  @override
  void initState() {
    super.initState();
    _bootstrapCheckIn();
  }

  Future<void> _bootstrapCheckIn() async {
    final snap = await _checkInService.snapshot();
    if (mounted) setState(() => _checkIn = snap);

    // Soft-enable daily reminder once; ignore failures (permission denied).
    try {
      await _reminderService.enableReminders();
    } catch (_) {}

    if (!mounted) return;
    if (!snap.checkedInToday && !_didPromptCheckIn) {
      _didPromptCheckIn = true;
      // Light prompt once after frame so home is visible first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openCheckIn();
      });
    }
  }

  Future<void> _refreshCheckIn() async {
    final snap = await _checkInService.snapshot();
    if (mounted) setState(() => _checkIn = snap);
  }

  Future<void> _openCheckIn() async {
    final snap = await showDailyCheckInSheet(
      context,
      service: _checkInService,
    );
    if (snap != null && mounted) {
      setState(() => _checkIn = snap);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            snap.streak > 1
                ? 'ثبت شد! استریک ${snap.streak} روزه داری.'
                : 'احساس امروزت ثبت شد.',
          ),
        ),
      );
    } else {
      await _refreshCheckIn();
    }
  }

  Future<void> _runAnalysisWithLoading({
    required Future<EmotionAnalysisResult> analysisFuture,
    required Future<void> Function(EmotionAnalysisResult result) onSuccess,
  }) async {
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AnalysisLoadingScreen()),
    );

    try {
      final result = await analysisFuture;
      if (!mounted) return;
      await onSuccess(result);
    } on LiaraEmotionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطای غیرمنتظره. دوباره تلاش کنید.')),
      );
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> analyze() async {
    final text = textCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً متن احساس خود را بنویسید.')),
      );
      return;
    }

    await _runAnalysisWithLoading(
      analysisFuture: _emotionService.analyze(text),
      onSuccess: (result) async {
        if (!result.isRefusal) {
          await historyBox.add({
            'text': text,
            'emotion': result.content,
            'dominantEmotion': EmotionLabelExtractor.extract(
              result.content,
              fallbackText: text,
            ),
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });
          final snap =
              await _checkInService.markDayCompletedFromAnalysis();
          if (mounted) setState(() => _checkIn = snap);
        }

        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AnalysisResultScreen(
              inputText: text,
              aiResponse: result.content,
              showEmergencyCall: result.showEmergencyCall,
            ),
          ),
        );
      },
    );
  }

  Future<void> analyzeFromFace() async {
    final XFile? photo;
    try {
      photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1024,
        imageQuality: 80,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'دسترسی به دوربین برقرار نشد. مجوز دوربین را در تنظیمات فعال کنید.',
          ),
        ),
      );
      return;
    }

    if (photo == null) return;

    final bytes = await photo.readAsBytes();

    await _runAnalysisWithLoading(
      analysisFuture: _emotionService.analyzeFromFace(bytes),
      onSuccess: (result) async {
        if (!result.isRefusal) {
          await historyBox.add({
            'type': 'face',
            'text': 'تحلیل از روی چهره',
            'emotion': result.content,
            'dominantEmotion': EmotionLabelExtractor.extract(result.content),
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });
          final snap =
              await _checkInService.markDayCompletedFromAnalysis();
          if (mounted) setState(() => _checkIn = snap);
        }

        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AnalysisResultScreen(
              inputText: 'تحلیل از روی سلفی',
              aiResponse: result.content,
              showEmergencyCall: result.showEmergencyCall,
              selfieImageBytes: bytes,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: const Text('تحلیل احساسات'),
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'راهنما',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _CheckInBanner(
              snapshot: _checkIn,
              onTap: _openCheckIn,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'متن احساس',
              hint: 'متن احساس خود را بنویسید',
              controller: textCtrl,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'تحلیل کن',
              onPressed: analyze,
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'تحلیل با چهره',
              onPressed: analyzeFromFace,
            ),
            const Spacer(),
            PrimaryButton(
              label: 'روند احساسات',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EmotionTrendsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'تاریخچه',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: 'درباره ما',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckInBanner extends StatelessWidget {
  const _CheckInBanner({
    required this.snapshot,
    required this.onTap,
  });

  final DailyCheckInSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = snapshot.checkedInToday;
    return Material(
      color: const Color(0xFF1C1D21),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Row(
            children: [
              Icon(
                done ? Icons.check_circle_outline : Icons.favorite_outline,
                color: done
                    ? AppColors.contentSuccess
                    : AppColors.primaryDefault,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done
                          ? 'امروز چک‌اینت انجام شد'
                          : 'الان حالت چطوره؟',
                      style: const TextStyle(
                        color: AppColors.contentDefault,
                        fontFamily: 'Peyda',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snapshot.streak > 0
                          ? 'استریک ${snapshot.streak} روزه'
                          : 'هر روز احساس‌ات را ثبت کن',
                      style: const TextStyle(
                        color: AppColors.contentSoft,
                        fontFamily: 'Peyda',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_left,
                color: AppColors.contentSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
