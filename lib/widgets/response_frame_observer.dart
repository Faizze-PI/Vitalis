import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Reports a response's painted frame; this is not display-panel timing.
class ResponseFrameObserver extends SingleChildRenderObjectWidget {
  const ResponseFrameObserver({
    super.key,
    required this.responseIdentity,
    required this.onFrame,
    required Widget child,
  }) : super(child: child);
  final Object responseIdentity;
  final void Function(Object) onFrame;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ResponseFrameRenderObject(responseIdentity, onFrame);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ResponseFrameRenderObject renderObject,
  ) {
    renderObject.onFrame = onFrame;
    renderObject.responseIdentity = responseIdentity;
  }
}

class _ResponseFrameRenderObject extends RenderProxyBox {
  _ResponseFrameRenderObject(this._responseIdentity, this.onFrame);
  Object _responseIdentity;
  Object? _pending;
  Object? _reported;
  void Function(Object) onFrame;

  set responseIdentity(Object value) {
    if (identical(value, _responseIdentity)) return;
    _responseIdentity = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final identity = _responseIdentity;
    if (identical(identity, _reported) || identical(identity, _pending)) return;
    _pending = identity;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (identical(_pending, identity)) _pending = null;
      if (!attached ||
          !identical(identity, _responseIdentity) ||
          identical(identity, _reported))
        return;
      _reported = identity;
      onFrame(identity);
    });
  }
}
