enum IOVInteractionState { idle, listening, processing, speaking, paused }

enum IOVInteractionEvent { listen, process, speak, pause, resume, stop, finish }

class IOVInteractionStateMachine {
  IOVInteractionState _state = IOVInteractionState.idle;

  IOVInteractionState get state => _state;

  bool dispatch(IOVInteractionEvent event) {
    final next = switch ((_state, event)) {
      (_, IOVInteractionEvent.stop) => IOVInteractionState.idle,
      (_, IOVInteractionEvent.listen) => IOVInteractionState.listening,
      (IOVInteractionState.listening, IOVInteractionEvent.process) =>
        IOVInteractionState.processing,
      (IOVInteractionState.processing, IOVInteractionEvent.speak) =>
        IOVInteractionState.speaking,
      (IOVInteractionState.idle, IOVInteractionEvent.speak) =>
        IOVInteractionState.speaking,
      (IOVInteractionState.listening, IOVInteractionEvent.speak) =>
        IOVInteractionState.speaking,
      (IOVInteractionState.speaking, IOVInteractionEvent.pause) =>
        IOVInteractionState.paused,
      (IOVInteractionState.paused, IOVInteractionEvent.resume) =>
        IOVInteractionState.speaking,
      (IOVInteractionState.speaking, IOVInteractionEvent.finish) =>
        IOVInteractionState.idle,
      (IOVInteractionState.processing, IOVInteractionEvent.finish) =>
        IOVInteractionState.idle,
      _ => null,
    };
    if (next == null) return false;
    _state = next;
    return true;
  }
}
