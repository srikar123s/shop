import 'dart:async';
import 'package:flutter/material.dart';

class TopNotificationService {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void showTopNotification({
    required BuildContext context,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    final overlayState = Overlay.of(context, rootOverlay: true);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return _TopNotificationCard(
          message: message,
          actionLabel: actionLabel,
          onAction: () {
            _dismissTimer?.cancel();
            entry.remove();
            _currentEntry = null;
            if (onAction != null) onAction();
          },
          onClose: () {
            _dismissTimer?.cancel();
            entry.remove();
            _currentEntry = null;
          },
        );
      },
    );

    _currentEntry = entry;
    overlayState.insert(entry);

    _dismissTimer = Timer(duration, () {
      if (_currentEntry == entry) {
        entry.remove();
        _currentEntry = null;
      }
    });
  }
}

class _TopNotificationCard extends StatefulWidget {
  const _TopNotificationCard({
    required this.message,
    this.actionLabel,
    this.onAction,
    required this.onClose,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClose;

  @override
  State<_TopNotificationCard> createState() => _TopNotificationCardState();
}

class _TopNotificationCardState extends State<_TopNotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) => widget.onClose());
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top + 10;

    return Positioned(
      top: topPadding,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF1E293B), // Dark Slate
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.tealAccent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (widget.actionLabel != null && widget.onAction != null) ...[
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.tealAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.onAction,
                    child: Text(
                      widget.actionLabel!,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: _dismiss,
                  tooltip: 'Dismiss',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
