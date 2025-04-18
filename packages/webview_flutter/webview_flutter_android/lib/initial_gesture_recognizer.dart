import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gesture recognizer that can recognize gesture without arena.
/// It doesn't accept gesture but can handle it directly using
/// [AndroidViewController]. So gesture event is duplicated and works
/// irrespective of each other. Common use-case would be Android webview
/// with nested gestures.
class InitialGestureRecognizer extends OneSequenceGestureRecognizer {
  /// Initialize the object.
  InitialGestureRecognizer(this.androidViewController);

  /// controller for Android Event.
  AndroidViewController androidViewController;
  @override
  String get debugDescription => throw UnimplementedError();

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void handleEvent(PointerEvent event) {
    _dispatchPointerEvent(event);
    stopTrackingIfPointerNoLongerDown(event);
  }

  Future<void> _dispatchPointerEvent(PointerEvent event) async {
    if (event is PointerHoverEvent) {
      return;
    }

    if (event is PointerDownEvent) {
      _handlePointerDownEvent(event);
    }

    _updatePointerPositions(event);

    final AndroidMotionEvent? androidEvent = _toAndroidMotionEvent(event);

    if (event is PointerUpEvent) {
      _handlePointerUpEvent(event);
    } else if (event is PointerCancelEvent) {
      _handlePointerCancelEvent(event);
    }

    if (androidEvent != null) {
      await androidViewController.sendMotionEvent(androidEvent);
    }
  }

  final Map<int, AndroidPointerCoords> _pointerPositions =
      <int, AndroidPointerCoords>{};
  final Map<int, AndroidPointerProperties> _pointerProperties =
      <int, AndroidPointerProperties>{};
  final Set<int> _usedAndroidPointerIds = <int>{};

  int? _downTimeMillis;

  void _handlePointerDownEvent(PointerDownEvent event) {
    if (_pointerProperties.isEmpty) {
      _downTimeMillis = event.timeStamp.inMilliseconds;
    }
    int androidPointerId = 0;
    while (_usedAndroidPointerIds.contains(androidPointerId)) {
      androidPointerId++;
    }
    _usedAndroidPointerIds.add(androidPointerId);
    _pointerProperties[event.pointer] = _propertiesFor(event, androidPointerId);
  }

  void _updatePointerPositions(PointerEvent event) {
    final Offset position =
        androidViewController.pointTransformer(event.position);
    _pointerPositions[event.pointer] = AndroidPointerCoords(
      orientation: event.orientation,
      pressure: event.pressure,
      size: event.size,
      toolMajor: event.radiusMajor,
      toolMinor: event.radiusMinor,
      touchMajor: event.radiusMajor,
      touchMinor: event.radiusMinor,
      x: position.dx,
      y: position.dy,
    );
  }

  void _remove(int pointer) {
    _pointerPositions.remove(pointer);
    _usedAndroidPointerIds.remove(_pointerProperties[pointer]!.id);
    _pointerProperties.remove(pointer);
    if (_pointerProperties.isEmpty) {
      _downTimeMillis = null;
    }
  }

  void _handlePointerUpEvent(PointerUpEvent event) {
    _remove(event.pointer);
  }

  void _handlePointerCancelEvent(PointerCancelEvent event) {
    _remove(event.pointer);
  }

  AndroidMotionEvent? _toAndroidMotionEvent(PointerEvent event) {
    final List<int> pointers = _pointerPositions.keys.toList();
    final int pointerIdx = pointers.indexOf(event.pointer);
    final int numPointers = pointers.length;
    const int kPointerDataFlagBatched = 1;
    if (event.platformData == kPointerDataFlagBatched ||
        (_isSinglePointerAction(event) && pointerIdx < numPointers - 1)) {
      return null;
    }
    final int action;
    if (event is PointerDownEvent) {
      action = numPointers == 1
          ? AndroidViewController.kActionDown
          : AndroidViewController.pointerAction(
              pointerIdx, AndroidViewController.kActionPointerDown);
    } else if (event is PointerUpEvent) {
      action = numPointers == 1
          ? AndroidViewController.kActionUp
          : AndroidViewController.pointerAction(
              pointerIdx, AndroidViewController.kActionPointerUp);
    } else if (event is PointerMoveEvent) {
      action = AndroidViewController.kActionMove;
    } else if (event is PointerCancelEvent) {
      action = AndroidViewController.kActionCancel;
    } else {
      return null;
    }

    return AndroidMotionEvent(
      downTime: _downTimeMillis!,
      eventTime: event.timeStamp.inMilliseconds,
      action: action,
      pointerCount: _pointerPositions.length,
      pointerProperties: pointers
          .map<AndroidPointerProperties>((int i) => _pointerProperties[i]!)
          .toList(),
      pointerCoords: pointers
          .map<AndroidPointerCoords>((int i) => _pointerPositions[i]!)
          .toList(),
      metaState: 0,
      buttonState: 0,
      xPrecision: 1.0,
      yPrecision: 1.0,
      deviceId: 0,
      edgeFlags: 0,
      source: 0,
      flags: 0,
      motionEventId: event.embedderId,
    );
  }

  AndroidPointerProperties _propertiesFor(PointerEvent event, int pointerId) {
    int toolType = AndroidPointerProperties.kToolTypeUnknown;
    switch (event.kind) {
      case PointerDeviceKind.touch:
        toolType = AndroidPointerProperties.kToolTypeFinger;
        break;
      case PointerDeviceKind.mouse:
        toolType = AndroidPointerProperties.kToolTypeMouse;
        break;
      case PointerDeviceKind.stylus:
        toolType = AndroidPointerProperties.kToolTypeStylus;
        break;
      case PointerDeviceKind.invertedStylus:
        toolType = AndroidPointerProperties.kToolTypeEraser;
        break;
      case PointerDeviceKind.unknown:
        toolType = AndroidPointerProperties.kToolTypeUnknown;
        break;
    }
    return AndroidPointerProperties(id: pointerId, toolType: toolType);
  }

  bool _isSinglePointerAction(PointerEvent event) =>
      event is! PointerDownEvent && event is! PointerUpEvent;
}
