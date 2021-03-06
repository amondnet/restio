part of 'cache.dart';

class CacheRequest {
  final Editor editor;
  final List<int> metaData;

  CacheRequest(this.editor, this.metaData);

  Future<StreamSink<List<int>>> body() async {
    final metaDataSink = editor.newSink(Cache.entryMetaData);
    metaDataSink.add(metaData);
    await metaDataSink.close();

    return _BodySink(editor, editor.newSink(Cache.entryBody));
  }

  Future<void> commit() {
    return editor.commit();
  }

  Future<void> abort() {
    return editor.abort();
  }
}

class _BodySink implements StreamSink<List<int>> {
  final Editor editor;
  final StreamSink<List<int>> sink;

  _BodySink(this.editor, this.sink);

  @override
  void add(List<int> event) {
    sink.add(event);
  }

  @override
  void addError(
    Object error, [
    StackTrace stackTrace,
  ]) async {
    sink.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    return sink.addStream(stream);
  }

  @override
  Future<void> close() async {
    try {
      await sink.close();
    } catch (e) {
      await editor.abort();
      return;
    }

    try {
      await editor.commit();
    } catch (e) {
      // nada.
    }
  }

  @override
  Future get done => sink.done;
}
