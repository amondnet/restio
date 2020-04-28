import 'dart:async';
import 'dart:convert';

import 'package:restio/src/core/push/sse/event.dart';

final _lineRegex = RegExp(r'^([^:]*)(?::)?(?: )?(.*)?$');

class SseTransformer implements StreamTransformer<List<int>, SseEvent> {
  final void Function(Duration reconnectInterval) retry;

  const SseTransformer({
    this.retry,
  });

  @override
  Stream<SseEvent> bind(Stream<List<int>> stream) {
    StreamController<SseEvent> controller;
    StreamSubscription<String> subscription;

    controller = StreamController(
      onListen: () {
        String id;
        final dataBuffer = <String>[];
        String event;

        // This stream will receive chunks of data that is not necessarily a
        // single event. So we build events on the fly and broadcast the event as
        // soon as we encounter a double newline, then we start a new one.
        subscription = stream
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())
            .listen((line) {
          if (line.isEmpty) {
            String data;

            // Event is done.
            if (dataBuffer.isNotEmpty) {
              data = dataBuffer.join('\n');
            }

            controller.add(SseEvent(id: id, data: data, event: event));

            dataBuffer.clear();
            id = null;
            event = null;

            return;
          }

          // Match the line prefix and the value using the regex.
          final match = _lineRegex.firstMatch(line);
          final field = match.group(1);
          final value = match.group(2);

          // Lines starting with a colon are to be ignored.
          if (field.isEmpty) {
            return;
          }

          switch (field) {
            case 'event':
              event = value;
              break;
            case 'data':
              dataBuffer.add(value ?? '');
              break;
            case 'id':
              id = value;
              break;
            case 'retry':
              try {
                retry?.call(Duration(milliseconds: int.parse(value)));
              } catch (e) {
                // nada.
              }
              break;
          }
        }, onError: (e, stackTrace) {
          controller.addError(e, stackTrace);
        });
      },
      onCancel: () async {
        await subscription?.cancel();
        await controller.close();
      },
    );

    return controller.stream;
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() {
    return StreamTransformer.castFrom<List<int>, SseEvent, RS, RT>(this);
  }
}
