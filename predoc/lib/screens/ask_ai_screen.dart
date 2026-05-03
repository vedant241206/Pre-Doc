// AskAiScreen — Network Fixed: real errors + retry
//
// RULE: Only send a short summary string to Pollinations — NO full health history.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/insight_service.dart';

class AskAiScreen extends StatefulWidget {
  final String? initialQuery;
  const AskAiScreen({super.key, this.initialQuery});
  @override
  State<AskAiScreen> createState() => _AskAiScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}

class _AskAiScreenState extends State<AskAiScreen>
    with TickerProviderStateMixin {
  final TextEditingController _ctrl   = TextEditingController();
  final ScrollController      _scroll = ScrollController();
  final List<_ChatMessage> _messages = [
    _ChatMessage(
      text:
          'Hello! I\'m your Predoc health assistant. Ask me anything about general wellness, symptoms, or healthy habits. I\'m here to help — but not to diagnose.',
      isUser: false,
    ),
  ];
  bool _loading = false;

  // ── Typing indicator animation ────────────────────────────
  late AnimationController _dot1Ctrl;
  late AnimationController _dot2Ctrl;
  late AnimationController _dot3Ctrl;

  @override
  void initState() {
    super.initState();
    _dot1Ctrl = _makeDotCtrl(0);
    _dot2Ctrl = _makeDotCtrl(200);
    _dot3Ctrl = _makeDotCtrl(400);

    if (widget.initialQuery != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ctrl.text = widget.initialQuery!;
        _send();
      });
    }
  }

  AnimationController _makeDotCtrl(int delayMs) {
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) ctrl.repeat(reverse: true);
    });
    return ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _dot1Ctrl.dispose();
    _dot2Ctrl.dispose();
    _dot3Ctrl.dispose();
    super.dispose();
  }

  // ── Build a short health summary (NOT full history) ──────
  String _buildSummary() {
    final counts = StorageService.getDailyLiveCounts();
    final cough  = counts['cough']  ?? 0;
    final sneeze = counts['sneeze'] ?? 0;
    final snore  = counts['snore']  ?? 0;

    final passive = StorageService.getPassiveDataToday();
    final result  = const InsightService().computeCombined(
      liveCoughCount:  cough,
      liveSneezeCount: sneeze,
      liveSnoreCount:  snore,
      nightUsageRisk:  passive?.sleepRisk   ?? false,
      screenTimeRisk:  passive?.screenRisk  ?? false,
      lowActivity:     passive?.sedentary   ?? false,
    );
    return 'Health score: ${result.score}/100 '
        '(${result.severityLabel}). '
        'Today — coughs: $cough, sneezes: $sneeze, snores: $snore.';
  }

  // ── Internet connectivity check ───────────────────────────
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Call Pollinations with retry ──────────────────────────
  Future<String> _callPollinations(String userQuestion) async {
    // Step 1: Check internet
    final online = await _hasInternet();
    if (!online) {
      return '📡 No internet connection. Please check your Wi-Fi or mobile data and try again.';
    }

    final summary = _buildSummary();
    final systemPrompt =
        'You are Predoc AI, an extremely smart, engaging health assistant. '
        'RULES:\n'
        '1. Keep responses VERY short, punchy, and easy to read (2-3 sentences max).\n'
        '2. NEVER use markdown (no ** or #). Use plain text and emojis to format.\n'
        '3. Be friendly and conversational.\n'
        '4. Never diagnose or prescribe.\n'
        '''
You are a helpful assistant inside the "Predoc" mobile app.

About the app:
Predoc is an offline-first health monitoring app that analyzes user behavior and sensor data to give early lifestyle-based health insights (not medical diagnosis).

Core features of Predoc:
* Audio Monitoring: Detects cough, sneeze, and snoring using on-device audio analysis
* Health Score: Calculated using fixed rule-based logic based on daily activity
* Habit Tracking: Detects patterns like late-night usage, inactivity, and worsening trends
* Notifications: Sends smart daily alerts based on health data
* Your Tree: A gamified plant that grows when the user maintains good health
* Device Test: Tests microphone and camera to ensure sensors are working properly
* Med Check: AI-based conversational assistant for general guidance (not diagnosis)
* Nearby Doctor: Helps find nearby doctors using location and opens maps

Safety rules:
* Do NOT give medical diagnosis
* Do NOT give emergency or critical medical advice
* Use safe language like "possible", "may indicate", "consider"
* Keep answers simple, clear, and practical
'''
        'User context (do NOT repeat this to user): $summary\n'
        'Random Seed to force variety: ${DateTime.now().millisecondsSinceEpoch}';

    final body = jsonEncode({
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userQuestion},
      ],
      'model': 'openai',
      'seed': DateTime.now().millisecondsSinceEpoch % 100000,
    });

    // Step 2: First attempt
    String? result = await _doPost(body);
    // Step 3: Retry once if first attempt failed
    result ??= await _doPost(body);

    return result ?? '🔧 Server error. The AI service is temporarily unavailable. Please try again in a moment.';
  }

  /// Makes a single POST attempt. Returns null on any failure.
  Future<String?> _doPost(String body) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://text.pollinations.ai/'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final text = response.body.trim();
        return text.isNotEmpty ? text : null;
      } else {
        // 4xx / 5xx
        return '🔧 Server error (${response.statusCode}). Please try again.';
      }
    } on SocketException {
      return null; // no connection — will retry
    } catch (_) {
      return null; // timeout or other — will retry
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _loading = true;
    });
    _scrollToBottom();

    final reply = await _callPollinations(text);

    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(text: reply, isUser: false));
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildChatBody()),
            _buildDisclaimer(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppColors.paddingH, vertical: AppColors.paddingV),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
            bottom: BorderSide(color: AppColors.divider, width: 1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (Navigator.canPop(context)) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textDark),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
          ],
          // Avatar with online dot
          Stack(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.smart_toy_rounded,
                    color: AppColors.primary, size: 28),
              ),
              Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: AppColors.good,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask Predoc AI',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  'General wellness assistant — not a doctor',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Chat body ──────────────────────────────────────────────
  Widget _buildChatBody() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
          horizontal: AppColors.paddingH, vertical: AppColors.paddingV),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (_loading && i == _messages.length) return _buildTypingIndicator();
        return _buildBubble(_messages[i]);
      },
    );
  }

  // ── Disclaimer banner ──────────────────────────────────────
  Widget _buildDisclaimer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: const Color(0xFFFFF7ED),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFB45309)),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'This is not medical advice. Always consult a doctor.',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: AppColors.divider),
                ),
                child: TextField(
                  controller: _ctrl,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Ask me anything health-related…',
                    hintStyle: TextStyle(
                        color: AppColors.textMuted, fontSize: 13),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _TapScaleButton(
              onTap: _send,
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Chat bubble ────────────────────────────────────────────
  Widget _buildBubble(_ChatMessage msg) {
    return Align(
      alignment:
          msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: msg.isUser
              ? AppColors.primary
              : const Color(0xFFF1F0F6),
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(18),
            topRight:    const Radius.circular(18),
            bottomLeft:  Radius.circular(msg.isUser ? 18 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.55,
            color: msg.isUser ? Colors.white : AppColors.textDark,
          ),
        ),
      ),
    );
  }

  // ── Typing indicator (3 bouncing dots) ────────────────────
  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F0F6),
          borderRadius: const BorderRadius.only(
            topLeft:     Radius.circular(18),
            topRight:    Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft:  Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AnimatedDot(controller: _dot1Ctrl),
            const SizedBox(width: 5),
            _AnimatedDot(controller: _dot2Ctrl),
            const SizedBox(width: 5),
            _AnimatedDot(controller: _dot3Ctrl),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ANIMATED DOT — typing indicator
// ─────────────────────────────────────────────────────────────

class _AnimatedDot extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedDot({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, -4 * controller.value),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(
                alpha: 0.4 + 0.6 * controller.value),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TAP SCALE BUTTON — 1 → 0.97 → 1, 120 ms
// ─────────────────────────────────────────────────────────────

class _TapScaleButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _TapScaleButton({required this.onTap, required this.child});

  @override
  State<_TapScaleButton> createState() => _TapScaleButtonState();
}

class _TapScaleButtonState extends State<_TapScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    await _ctrl.forward();
    await _ctrl.reverse();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}
