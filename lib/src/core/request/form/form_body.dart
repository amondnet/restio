import 'dart:convert';

import 'package:restio/src/common/helpers.dart';
import 'package:restio/src/common/item_list.dart';
import 'package:restio/src/core/request/form/form_builder.dart';
import 'package:restio/src/core/request/form/form_item.dart';
import 'package:restio/src/core/request/header/media_type.dart';
import 'package:restio/src/core/request/request_body.dart';

class FormBody extends ItemList<FormItem> implements RequestBody {
  @override
  final MediaType contentType;
  @override
  final int contentLength;

  FormBody({
    List<FormItem> items,
    String charset,
  })  : contentType = MediaType.formUrlEncoded.copyWith(charset: charset),
        contentLength = null,
        super(items ?? const []);

  factory FormBody.fromMap(
    Map<String, dynamic> items, [
    String charset,
  ]) {
    final builder = FormBuilder();
    builder.charset = charset;
    items.forEach(builder.add);
    return builder.build();
  }

  @override
  Stream<List<int>> write() async* {
    final encoding = contentType.encoding;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      if (i > 0) {
        yield encoding.encode('&');
      }

      yield _encodeForm(item.name, encoding);
      yield encoding.encode('=');
      yield _encodeForm(item.value, encoding);
    }
  }

  static List<int> _encodeForm(
    String input,
    Encoding encoding,
  ) {
    return canonicalize(
      input,
      formEncodeSet,
      plusIsSpace: true,
      encoding: encoding,
    );
  }

  @override
  FormBuilder toBuilder() {
    return FormBuilder(items);
  }

  @override
  List<Object> get props => [items, contentType];

  @override
  String toString() {
    return 'FormBody { contentType: $contentType, items: $items }';
  }
}
