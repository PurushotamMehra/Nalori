import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

typedef ReadingDeckCardBuilder =
    Widget Function(
      BuildContext context,
      int index,
      double stackProgress,
      bool isCurrent,
    );

class ReadingCardDeckController {
  _ReadingCardDeckState? _state;

  bool animateToIndex(int targetIndex, Duration duration, Curve curve) {
    return _state?._animateToIndex(targetIndex, duration, curve) ?? false;
  }

  void _attach(_ReadingCardDeckState state) {
    _state = state;
  }

  void _detach(_ReadingCardDeckState state) {
    if (_state == state) _state = null;
  }
}

class ReadingCardDeck extends StatefulWidget {
  final int currentIndex;
  final int itemCount;
  final bool canSwipe;
  final Axis axis;
  final ReadingCardDeckController? controller;
  final ValueChanged<int> onIndexChanged;
  final ReadingDeckCardBuilder cardBuilder;

  const ReadingCardDeck({
    super.key,
    required this.currentIndex,
    required this.itemCount,
    required this.onIndexChanged,
    required this.cardBuilder,
    this.canSwipe = true,
    this.axis = Axis.vertical,
    this.controller,
  });

  @override
  State<ReadingCardDeck> createState() => _ReadingCardDeckState();
}

class _ReadingCardDeckState extends State<ReadingCardDeck>
    with SingleTickerProviderStateMixin {
  static const double _idleNextOffset = 26.0;
  static const double _idleThirdOffset = 48.0;
  static const double _idlePreviousOffset = -26.0;
  static const double _completionThreshold = 0.25;
  static const double _flingVelocityThreshold = 650.0;
  static const Duration _swipeStartTimeout = Duration(milliseconds: 220);

  late final AnimationController _settleController;
  Animation<double>? _settleAnimation;
  double _dragOffset = 0;
  int? _activePointer;
  Duration? _pointerDownTime;
  Offset? _lastPointerPosition;
  Offset _pointerDelta = Offset.zero;
  bool _isTrackingSwipe = false;
  VelocityTracker? _velocityTracker;
  Timer? _swipeStartTimer;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _settleController = AnimationController(vsync: this)
      ..addListener(() {
        final animation = _settleAnimation;
        if (animation == null) return;
        setState(() => _dragOffset = animation.value);
      });
  }

  @override
  void didUpdateWidget(covariant ReadingCardDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.itemCount != widget.itemCount) {
      _settleController.stop();
      _settleAnimation = null;
      _dragOffset = 0;
    }
  }

  @override
  void dispose() {
    _swipeStartTimer?.cancel();
    widget.controller?._detach(this);
    _settleController.dispose();
    super.dispose();
  }

  bool get _hasPrevious => widget.currentIndex > 0;
  bool get _hasNext => widget.currentIndex < widget.itemCount - 1;
  double get _touchSlop => 32.0;

  double _resistedOffset(double proposed) {
    if (proposed < 0 && !_hasNext) return proposed * 0.28;
    if (proposed > 0 && !_hasPrevious) return proposed * 0.28;
    return proposed;
  }

  double _primaryDelta(Offset delta) {
    return widget.axis == Axis.vertical ? delta.dy : delta.dx;
  }

  double _crossDelta(Offset delta) {
    return widget.axis == Axis.vertical ? delta.dx : delta.dy;
  }

  void _resetPointerTracking() {
    _swipeStartTimer?.cancel();
    _swipeStartTimer = null;
    _activePointer = null;
    _pointerDownTime = null;
    _lastPointerPosition = null;
    _pointerDelta = Offset.zero;
    _isTrackingSwipe = false;
    _velocityTracker = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.canSwipe || widget.itemCount <= 1 || _activePointer != null) {
      return;
    }

    _activePointer = event.pointer;
    _pointerDownTime = event.timeStamp;
    _lastPointerPosition = event.position;
    _pointerDelta = Offset.zero;
    _isTrackingSwipe = false;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _swipeStartTimer = Timer(_swipeStartTimeout, () {
      if (!_isTrackingSwipe) _resetPointerTracking();
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.canSwipe || widget.itemCount <= 1) return;
    if (event.pointer != _activePointer) return;

    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final lastPosition = _lastPointerPosition;
    if (lastPosition == null) {
      _lastPointerPosition = event.position;
      return;
    }

    final delta = event.position - lastPosition;
    _lastPointerPosition = event.position;
    _pointerDelta += delta;

    if (!_isTrackingSwipe) {
      final downTime = _pointerDownTime;
      if (downTime != null && event.timeStamp - downTime > _swipeStartTimeout) {
        _resetPointerTracking();
        return;
      }
      final primary = _primaryDelta(_pointerDelta).abs();
      final cross = _crossDelta(_pointerDelta).abs();
      if (primary < _touchSlop) return;
      if (primary < cross * 1.6) {
        _resetPointerTracking();
        return;
      }
      _swipeStartTimer?.cancel();
      _swipeStartTimer = null;
      _isTrackingSwipe = true;
    }

    _settleController.stop();
    setState(() {
      _dragOffset = _resistedOffset(_dragOffset + _primaryDelta(delta));
    });
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    final velocity = _velocityTracker?.getVelocity().pixelsPerSecond;
    final primaryVelocity = velocity == null ? 0.0 : _primaryDelta(velocity);
    final trackedSwipe = _isTrackingSwipe;
    _resetPointerTracking();
    if (!trackedSwipe && _dragOffset == 0) return;
    _handleDragEnd(primaryVelocity);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _resetPointerTracking();
    if (_dragOffset != 0) {
      _animateDragTo(0, const Duration(milliseconds: 180), Curves.easeOutCubic);
    }
  }

  void _handleDragEnd(double primaryVelocity) {
    if (!widget.canSwipe || widget.itemCount <= 1) {
      _animateDragTo(0, const Duration(milliseconds: 180), Curves.easeOutCubic);
      return;
    }

    final size = context.size ?? Size.zero;
    final extent = widget.axis == Axis.vertical ? size.height : size.width;
    final safeExtent = math.max(extent, 1).toDouble();
    final progress = (_dragOffset.abs() / safeExtent).clamp(0.0, 1.0);
    final wantsNext =
        _dragOffset < 0 &&
        _hasNext &&
        (progress >= _completionThreshold ||
            primaryVelocity <= -_flingVelocityThreshold);
    final wantsPrevious =
        _dragOffset > 0 &&
        _hasPrevious &&
        (progress >= _completionThreshold ||
            primaryVelocity >= _flingVelocityThreshold);

    if (wantsNext) {
      _completeTo(widget.currentIndex + 1, -safeExtent);
    } else if (wantsPrevious) {
      _completeTo(widget.currentIndex - 1, safeExtent);
    } else {
      _animateDragTo(0, const Duration(milliseconds: 210), Curves.easeOutCubic);
    }
  }

  void _completeTo(int targetIndex, double endOffset) {
    _animateDragTo(
      endOffset,
      const Duration(milliseconds: 260),
      Curves.easeOutCubic,
      onComplete: () {
        if (!mounted) return;
        _dragOffset = 0;
        widget.onIndexChanged(targetIndex);
      },
    );
  }

  bool _animateToIndex(int targetIndex, Duration duration, Curve curve) {
    if (widget.itemCount <= 1) return false;
    if (targetIndex < 0 || targetIndex >= widget.itemCount) return false;
    if ((targetIndex - widget.currentIndex).abs() != 1) return false;

    final size = context.size ?? Size.zero;
    final extent = widget.axis == Axis.vertical ? size.height : size.width;
    final safeExtent = math.max(extent, 1).toDouble();
    final endOffset = targetIndex > widget.currentIndex
        ? -safeExtent
        : safeExtent;
    _animateDragTo(
      endOffset,
      duration,
      curve,
      onComplete: () {
        if (!mounted) return;
        _dragOffset = 0;
        widget.onIndexChanged(targetIndex);
      },
    );
    return true;
  }

  void _animateDragTo(
    double target,
    Duration duration,
    Curve curve, {
    VoidCallback? onComplete,
  }) {
    _settleController.stop();
    _settleController.duration = duration;
    _settleAnimation = Tween<double>(
      begin: _dragOffset,
      end: target,
    ).animate(CurvedAnimation(parent: _settleController, curve: curve));
    _settleController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      if (onComplete != null) {
        onComplete();
      } else {
        setState(() => _dragOffset = target);
      }
    });
  }

  double _lerp(double begin, double end, double t) {
    return begin + (end - begin) * t;
  }

  Widget _transformedCard({
    required int index,
    required double translate,
    required double scale,
    required double progress,
    bool isCurrent = false,
    double rotationZ = 0,
  }) {
    final card = widget.cardBuilder(context, index, progress, isCurrent);
    final offset = widget.axis == Axis.vertical
        ? Offset(0, translate)
        : Offset(translate, 0);
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !isCurrent,
        child: Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: rotationZ,
            child: Transform.scale(scale: scale, child: card),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = widget.axis == Axis.vertical
            ? constraints.maxHeight
            : constraints.maxWidth;
        return _buildDeck(context, math.max(extent, 1).toDouble());
      },
    );
  }

  Widget _buildDeck(BuildContext context, double extent) {
    final forwardProgress = (-_dragOffset / extent).clamp(0.0, 1.0);
    final backwardProgress = (_dragOffset / extent).clamp(0.0, 1.0);
    final activeProgress = math.max(forwardProgress, backwardProgress);

    // Gesture math:
    // - Negative primary-axis drag means the top card is leaving forward:
    //   up in vertical mode, left in horizontal mode.
    // - Positive primary-axis drag mirrors that for the previous card:
    //   down in vertical mode, right in horizontal mode.
    // - Cards stay fully opaque. Depth comes from z-order, clipping, offset,
    //   scale, and shadow rather than fading text in/out.
    final currentScale = _lerp(1.0, 0.965, activeProgress);
    final currentRotation = _lerp(
      0,
      _dragOffset < 0 ? -0.012 : 0.012,
      activeProgress,
    );

    final children = <Widget>[];
    final thirdIndex = widget.currentIndex + 2;
    if (thirdIndex < widget.itemCount) {
      children.add(
        _transformedCard(
          index: thirdIndex,
          translate: _lerp(_idleThirdOffset, _idleNextOffset, forwardProgress),
          scale: _lerp(0.958, 0.978, forwardProgress),
          progress: forwardProgress,
        ),
      );
    }

    final nextIndex = widget.currentIndex + 1;
    if (nextIndex < widget.itemCount) {
      children.add(
        _transformedCard(
          index: nextIndex,
          translate: _lerp(_idleNextOffset, 0, forwardProgress),
          scale: _lerp(0.98, 1.0, forwardProgress),
          progress: forwardProgress,
        ),
      );
    }

    final previousIndex = widget.currentIndex - 1;
    if (previousIndex >= 0 && backwardProgress > 0) {
      children.add(
        _transformedCard(
          index: previousIndex,
          translate: _lerp(_idlePreviousOffset, 0, backwardProgress),
          scale: _lerp(0.98, 1.0, backwardProgress),
          progress: backwardProgress,
        ),
      );
    }

    if (widget.currentIndex >= 0 && widget.currentIndex < widget.itemCount) {
      children.add(
        _transformedCard(
          index: widget.currentIndex,
          translate: _dragOffset,
          scale: currentScale,
          rotationZ: currentRotation,
          progress: activeProgress,
          isCurrent: true,
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: ClipRect(child: Stack(children: children)),
    );
  }
}
