import 'dart:convert';
import 'dart:io';

import 'package:mime_type/mime_type.dart';
import 'package:path/path.dart';
import 'package:restio/src/common/encoding.dart';
import 'package:restio/src/common/item.dart';

class MediaType extends Item {
  final String type;
  final String subType;
  final Map<String, String> parameters;

  static const formUrlEncoded = MediaType._(
    type: 'application',
    subType: 'x-www-form-urlencoded',
  );

  static const multipartMixed = MediaType._(
    type: 'multipart',
    subType: 'mixed',
  );

  static const multipartAlternative = MediaType._(
    type: 'multipart',
    subType: 'alternative',
  );

  static const multipartDigest = MediaType._(
    type: 'multipart',
    subType: 'digest',
  );

  static const multipartParallel = MediaType._(
    type: 'multipart',
    subType: 'parallel',
  );

  static const multipartFormData = MediaType._(
    type: 'multipart',
    subType: 'form-data',
  );

  static const json = MediaType._(
    type: 'application',
    subType: 'json',
    parameters: {'charset': 'utf-8'},
  );

  static const octetStream = MediaType._(
    type: 'application',
    subType: 'octet-stream',
  );

  static const text = MediaType._(
    type: 'text',
    subType: 'plain',
    parameters: {'charset': 'utf-8'},
  );

  const MediaType._({
    this.type,
    this.subType,
    this.parameters = const {},
  });

  factory MediaType({
    String type,
    String subType,
    String charset,
    String boundary,
    Map<String, String> parameters,
  }) {
    parameters = {
      if (parameters != null) ...parameters,
      if (charset != null) 'charset': charset,
      if (boundary != null) 'boundary': boundary,
    };

    return MediaType._(
      type: type,
      subType: subType,
      parameters: parameters,
    );
  }

  factory MediaType.fromContentType(ContentType contentType) {
    return MediaType(
      type: contentType?.primaryType ?? 'application',
      subType: contentType?.subType ?? 'octet-stream',
      charset: contentType?.charset,
      parameters: contentType?.parameters,
    );
  }

  factory MediaType.parse(String text) {
    return text == null
        ? null
        : MediaType.fromContentType(ContentType.parse(text));
  }

  factory MediaType.fromFile(
    String path, [
    String charset,
  ]) {
    final ext = extension(path)?.replaceAll('.', '');
    final mimeType = mimeFromExtension(ext);
    return mimeType != null
        ? MediaType.parse(mimeType).copyWith(charset: charset)
        : MediaType.octetStream;
  }

  @override
  String get name => 'Content-Type';

  @override
  String get value => toHeaderString();

  MediaType copyWith({
    String type,
    String subType,
    String charset,
    String boundary,
    Map<String, String> parameters,
  }) {
    return MediaType(
      type: type ?? this.type,
      subType: subType ?? this.subType,
      charset: charset ?? this.parameters['charset'],
      boundary: boundary ?? this.parameters['boundary'],
      parameters: parameters ?? this.parameters,
    );
  }

  ContentType toContentType() {
    return ContentType(
      type,
      subType,
      parameters: parameters,
    );
  }

  String get mimeType => '$type/$subType';

  String get charset => parameters['charset'];

  String get boundary => parameters['boundary'];

  Encoding get encoding => encodingByName(
        parameters['charset'],
        type == 'multipart' ? utf8 : _defaultEncoding(mimeType),
      );

  static Encoding _defaultEncoding(String mimeType) {
    return mimeType == 'application/json' || mimeType == 'text/plain'
        ? utf8
        : latin1;
  }

  String toHeaderString() {
    final text = StringBuffer()..write('$mimeType');

    if (parameters != null) {
      for (final name in parameters.keys) {
        final value = parameters[name];

        if (value != null) {
          text.write('; $name=$value');
        }
      }
    }

    return text.toString();
  }

  @override
  String toString() {
    return 'MediaType { type: $type, subType: $subType,'
        ' parameters: $parameters }';
  }

  @override
  List<Object> get props => [type, subType, parameters];
}
