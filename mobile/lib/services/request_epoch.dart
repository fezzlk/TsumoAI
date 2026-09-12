/// Invalidates responses from asynchronous work started against older input.
class RequestEpoch {
  int _value = 0;

  int get current => _value;

  void invalidate() => _value++;

  bool isCurrent(int captured) => captured == _value;
}
