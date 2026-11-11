import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Shown under a button after a request has been running for a few seconds.
///
/// The free hosting plan puts the server to sleep after 15 minutes without
/// use, and waking it takes up to a minute. Without this, a slow first login
/// looks like the app froze.
class WaitingHint extends StatefulWidget {
  const WaitingHint({
    super.key,
    required this.active,
    this.after = const Duration(seconds: 5),
    this.message = 'Waking up the server… the first sign-in after a while can take up to a minute.',
  });

  final bool active;
  final Duration after;
  final String message;

  @override
  State<WaitingHint> createState() => _WaitingHintState();
}

class _WaitingHintState extends State<WaitingHint> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(WaitingHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    _timer?.cancel();
    if (widget.active) {
      _timer = Timer(widget.after, () {
        if (mounted) setState(() => _visible = true);
      });
    } else if (_visible) {
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: !_visible
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
    );
  }
}
