// MedCheckupScreen — Day 12 UI Refinement
// Logic/API unchanged from Day 10. UI polished per Day 12 spec.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';

class MedCheckupScreen extends StatefulWidget {
  const MedCheckupScreen({super.key});
  @override
  State<MedCheckupScreen> createState() => _MedCheckupScreenState();
}

class _MedMessage {
  final String text;
  final bool isUser;
  _MedMessage({required this.text, required this.isUser});
}

class _MedCheckupScreenState extends State<MedCheckupScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _scanCtrl;
  late AnimationController _dot1Ctrl;
  late AnimationController _dot2Ctrl;
  late AnimationController _dot3Ctrl;

  final TextEditingController _ctrl   = TextEditingController();
  final ScrollController      _scroll = ScrollController();
  bool _chatMode = false;
  bool _loading  = false;

  final List<_MedMessage> _messages = [
    _MedMessage(
      text: 'Hello! I\'m your Predoc health companion. Describe your symptoms or ask a general health question and I\'ll offer helpful guidance.\n\n⚠️ I provide suggestions only — always consult a qualified doctor for medical decisions.',
      isUser: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _scanCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _dot1Ctrl = _makeDotCtrl(0);
    _dot2Ctrl = _makeDotCtrl(200);
    _dot3Ctrl = _makeDotCtrl(400);
  }

  AnimationController _makeDotCtrl(int delayMs) {
    final ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) ctrl.repeat(reverse: true);
    });
    return ctrl;
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    _dot1Ctrl.dispose();
    _dot2Ctrl.dispose();
    _dot3Ctrl.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<String> _callPollinations(String userMsg) async {
    const systemPrompt =
        'You are a highly intelligent, empathetic health companion. '
        'STRICT RULES:\n'
        '1. Keep responses VERY short, crisp, and engaging (1-3 sentences).\n'
        '2. NEVER use markdown like ** or #. Use plain text and emojis.\n'
        '3. NEVER diagnose or prescribe medication.\n'
        '4. Suggest practical lifestyle changes or home remedies concisely.\n'
        '5. Be conversational and human-like.';

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ..._messages.map((m) =>
          {'role': m.isUser ? 'user' : 'assistant', 'content': m.text}),
      {'role': 'user', 'content': userMsg},
    ];

    final body = jsonEncode({'messages': messages, 'model': 'openai'});

    try {
      final response = await http
          .post(Uri.parse('https://text.pollinations.ai/'),
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return response.body.trim().isNotEmpty
            ? response.body.trim()
            : 'No response.';
      }
      return 'Error ${response.statusCode}. Please try again.';
    } catch (e) {
      return 'Connection error. Check your internet and try again.';
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();
    setState(() { _messages.add(_MedMessage(text: text, isUser: true)); _loading = true; });
    _scrollToBottom();
    final reply = await _callPollinations(text);
    if (mounted) {
      setState(() { _messages.add(_MedMessage(text: reply, isUser: false)); _loading = false; });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      _chatMode ? _buildChatView() : _buildScannerView();

  // ── Scanner / Landing View ─────────────────────────────────

  Widget _buildScannerView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppColors.paddingH, vertical: AppColors.paddingV),
      child: Column(children: [
        const Text('Med Checkup',
            style: TextStyle(fontFamily: 'Nunito', fontSize: 24,
                fontWeight: FontWeight.w900, color: AppColors.textDark)),
        const SizedBox(height: 4),
        const Text('AI-powered health companion',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Nunito', fontSize: 14,
                fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        const SizedBox(height: 32),

        // ── Circular camera preview with scanning animation ──
        _buildCameraPreview(),

        const SizedBox(height: 28),

        // Overlay instruction chips
        _buildOverlayChips(),

        const SizedBox(height: 28),

        // Quick symptom chips
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Quick Start', style: TextStyle(
              fontFamily: 'Nunito', fontSize: 16,
              fontWeight: FontWeight.w800, color: AppColors.textDark)),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _chip('I have a cough'),
          _chip('I can\'t sleep'),
          _chip('I feel tired'),
          _chip('I have a headache'),
          _chip('My throat hurts'),
          _chip('I feel anxious'),
        ]),

        const SizedBox(height: 28),
        _TapScaleButton(
          onTap: () => setState(() => _chatMode = true),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppColors.radiusCard)),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.chat_rounded, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Text('Start Health Consultation',
                  style: TextStyle(fontFamily: 'Nunito', fontSize: 16,
                      fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '⚠️ This feature provides general wellness suggestions only.\n'
          'It does not replace professional medical advice.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Nunito', fontSize: 11,
              fontWeight: FontWeight.w600, color: AppColors.textMuted,
              height: 1.5),
        ),
      ]),
    );
  }

  Widget _buildCameraPreview() {
    return Stack(alignment: Alignment.center, children: [
      // Outer pulsing ring
      AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) => Container(
          width: 210 + _pulseCtrl.value * 16,
          height: 210 + _pulseCtrl.value * 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primary.withValues(
                  alpha: 0.08 + 0.22 * (1 - _pulseCtrl.value)),
              width: 2 + _pulseCtrl.value * 3,
            ),
          ),
        ),
      ),

      // Circular progress ring (scanning progress)
      AnimatedBuilder(
        animation: _scanCtrl,
        builder: (_, __) => SizedBox(
          width: 196,
          height: 196,
          child: CircularProgressIndicator(
            value: _scanCtrl.value,
            strokeWidth: 3,
            backgroundColor: AppColors.primaryLight,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ),

      // Circular camera view
      Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.45), width: 3),
          boxShadow: [BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.15),
              blurRadius: 20, spreadRadius: 4)],
        ),
        child: ClipOval(
          child: Stack(alignment: Alignment.center, children: [
            const Icon(Icons.face_rounded,
                color: AppColors.primaryMid, size: 80),

            // Scanning line sweeping across
            AnimatedBuilder(
              animation: _scanCtrl,
              builder: (_, __) => Positioned(
                top: _scanCtrl.value * 160,
                child: Container(
                  width: 140,
                  height: 2,
                  decoration: BoxDecoration(
                    color: AppColors.good,
                    boxShadow: [BoxShadow(
                        color: AppColors.good.withValues(alpha: 0.7),
                        blurRadius: 8, spreadRadius: 1)],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildOverlayChips() {
    const instructions = ['👁️ Look straight', '😉 Blink', '🔄 Move slightly'];
    return Wrap(
      spacing: 10,
      alignment: WrapAlignment.center,
      children: instructions.map((t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(t, style: const TextStyle(fontFamily: 'Nunito',
            fontSize: 13, fontWeight: FontWeight.w700,
            color: AppColors.primaryDark)),
      )).toList(),
    );
  }

  Widget _chip(String label) {
    return GestureDetector(
      onTap: () {
        setState(() => _chatMode = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ctrl.text = label;
          _send();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3))),
        child: Text(label, style: const TextStyle(fontFamily: 'Nunito',
            fontSize: 13, fontWeight: FontWeight.w700,
            color: AppColors.primaryDark)),
      ),
    );
  }

  // ── Chat View ──────────────────────────────────────────────

  Widget _buildChatView() {
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.divider))),
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _chatMode = false),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textDark, size: 18),
          ),
          const SizedBox(width: 14),
          Container(width: 40, height: 40,
              decoration: const BoxDecoration(
                  color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(Icons.medical_services_rounded,
                  color: AppColors.primary, size: 22)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Health Companion', style: TextStyle(fontFamily: 'Nunito',
                fontSize: 15, fontWeight: FontWeight.w800,
                color: AppColors.textDark)),
            Text('Suggestions only — not a diagnosis', style: TextStyle(
                fontFamily: 'Nunito', fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
          ])),
        ]),
      ),

      // Messages
      Expanded(child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(
            horizontal: AppColors.paddingH, vertical: AppColors.paddingV),
        itemCount: _messages.length + (_loading ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (_loading && i == _messages.length) return _buildTypingBubble();
          final msg = _messages[i];
          return Align(
            alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: msg.isUser ? AppColors.primary : const Color(0xFFF1F0F6),
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(18),
                  topRight:    const Radius.circular(18),
                  bottomLeft:  Radius.circular(msg.isUser ? 18 : 4),
                  bottomRight: Radius.circular(msg.isUser ? 4 : 18),
                ),
                boxShadow: [BoxShadow(
                    color: AppColors.shadow.withValues(alpha: 0.06),
                    blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Text(msg.text, style: TextStyle(fontFamily: 'Nunito',
                  fontSize: 14, fontWeight: FontWeight.w600, height: 1.55,
                  color: msg.isUser ? Colors.white : AppColors.textDark)),
            ),
          );
        },
      )),

      // Disclaimer
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        color: const Color(0xFFFFF7ED),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFFB45309)),
          SizedBox(width: 6),
          Expanded(child: Text('Suggestions only. Consult a qualified doctor.',
              style: TextStyle(fontFamily: 'Nunito', fontSize: 11,
                  color: Color(0xFFB45309), fontWeight: FontWeight.w600))),
        ]),
      ),

      // Input bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.divider))),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: AppColors.divider)),
              child: TextField(
                controller: _ctrl,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontFamily: 'Nunito', fontSize: 14,
                    fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: 'Describe your symptoms…',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            )),
            const SizedBox(width: 10),
            _TapScaleButton(
              onTap: _send,
              child: Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
                child: _loading
                    ? const Padding(padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          color: Color(0xFFF1F0F6),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18), topRight: Radius.circular(18),
            bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _AnimDot(controller: _dot1Ctrl),
          const SizedBox(width: 5),
          _AnimDot(controller: _dot2Ctrl),
          const SizedBox(width: 5),
          _AnimDot(controller: _dot3Ctrl),
        ]),
      ),
    );
  }
}

class _AnimDot extends StatelessWidget {
  final AnimationController controller;
  const _AnimDot({required this.controller});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, -4 * controller.value),
        child: Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.4 + 0.6 * controller.value),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ── Tap Scale Button ───────────────────────────────────────────

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
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

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
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}
