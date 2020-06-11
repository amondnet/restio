import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:restio/src/retrofit/annotations.dart' as annotations;
import 'package:restio/restio.dart';
import 'package:source_gen/source_gen.dart';

class RetrofitGenerator extends GeneratorForAnnotation<annotations.Api> {
  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    // Must be a class.
    if (element is! ClassElement) {
      final name = element.name;
      throw RetrofitError('Generator can not target `$name`.', element);
    }
    // Returns the generated API class.
    return _generate(element, annotation);
  }

  /// Returns the generated API class as [String].
  static String _generate(
    ClassElement element,
    ConstantReader annotation,
  ) {
    final classBuilder = _generateApi(element, annotation);
    final emitter = DartEmitter();
    final text = classBuilder.accept(emitter).toString();
    return DartFormatter().format(text);
  }

  /// Returns the generated API class.
  static Class _generateApi(
    ClassElement element,
    ConstantReader annotation,
  ) {
    // Name.
    final className = element.name;
    final name = '_$className';
    // Base URI.
    final baseUri = annotation.peek('baseUri')?.stringValue;

    return Class((c) {
      // Name.
      c.name = name;
      // Fields.
      c.fields.addAll([
        _generateField(
          name: 'client',
          type: refer('Restio'),
          modifier: FieldModifier.final$,
        ),
        _generateField(
          name: 'baseUri',
          type: refer('String'),
          modifier: FieldModifier.final$,
        ),
      ]);
      // Constructors.
      c.constructors.add(_generateConstructor(baseUri));
      // Implementents.
      c.implements.addAll([refer(className)]);
      // Methods.
      c.methods.addAll(_generateMethods(element));
    });
  }

  /// Returns the generated API class' constructor.
  static Constructor _generateConstructor(String baseUri) {
    return Constructor((c) {
      // Parameters.
      c.optionalParameters
          .add(_generateParameter(name: 'client', type: refer('Restio')));

      if (baseUri != null) {
        c.optionalParameters.add(_generateParameter(
            name: 'baseUri', type: refer('String'), named: true));
      } else {
        c.optionalParameters.add(
            _generateParameter(name: 'baseUri', toThis: true, named: true));
      }
      // Initializers.
      c.initializers.addAll([
        refer('client')
            .assign(refer('client')
                .ifNullThen(refer('Restio').newInstance(const [])))
            .code,
        if (baseUri != null) Code("baseUri = baseUri ?? '$baseUri'"),
      ]);
    });
  }

  /// Returns a generic parameter.
  static Parameter _generateParameter({
    String name,
    bool named,
    bool required,
    bool toThis,
    Reference type,
    Code defaultTo,
  }) {
    return Parameter((p) {
      if (name != null) p.name = name;
      if (named != null) p.named = named;
      if (required != null) p.required = required;
      if (toThis != null) p.toThis = toThis;
      if (type != null) p.type = type;
      if (defaultTo != null) p.defaultTo = defaultTo;
    });
  }

  /// Returns a generic field.
  static Field _generateField({
    String name,
    FieldModifier modifier,
    bool static,
    Reference type,
    Code assignment,
  }) {
    return Field((f) {
      if (name != null) f.name = name;
      if (modifier != null) f.modifier = modifier;
      if (static != null) f.static = static;
      if (type != null) f.type = type;
      if (assignment != null) f.assignment = assignment;
    });
  }

  static const _methodAnnotations = [
    annotations.Get,
    annotations.Post,
    annotations.Put,
    annotations.Delete,
    annotations.Head,
    annotations.Patch,
    annotations.Options,
    annotations.Method,
  ];

  /// Checks if the method is valid.
  static bool _isValidMethod(MethodElement m) {
    return m.isAbstract &&
        (m.returnType.isDartAsyncFuture || m.returnType.isDartAsyncStream);
  }

  /// Checks if the method has a @Method annotation.
  static bool _hasMethodAnnotation(MethodElement m) {
    return _methodAnnotation(m) != null;
  }

  /// Returns the all generated methods.
  static List<Method> _generateMethods(ClassElement element) {
    return [
      for (final m in element.methods)
        if (_isValidMethod(m) && _hasMethodAnnotation(m)) _generateMethod(m),
    ];
  }

  /// Returns the generated method for an API endpoint method.
  static Method _generateMethod(MethodElement element) {
    // The HTTP method annotation.
    final httpMethod = _methodAnnotation(element);

    return Method((m) {
      // Name.
      m.name = element.displayName;
      // Async method.
      m.modifier = MethodModifier.async;
      // Override.
      m.annotations.addAll(const [CodeExpression(Code('override'))]);
      // Parameters.
      m.requiredParameters.addAll(
        element.parameters
            .where((p) => p.isRequiredPositional || p.isRequiredNamed)
            .map(
              (p) => _generateParameter(
                name: p.name,
                named: p.isNamed,
                type: refer(p.type.getDisplayString()),
              ),
            ),
      );

      m.optionalParameters.addAll(
        element.parameters.where((p) => p.isOptional).map(
              (p) => _generateParameter(
                name: p.name,
                named: p.isNamed,
                defaultTo: p.defaultValueCode == null
                    ? null
                    : Code(p.defaultValueCode),
              ),
            ),
      );
      // Body.
      m.body = _generateRequest(element, httpMethod);
    });
  }

  /// Returns the all parameters from a method with your
  /// first [type] annotation.
  static Map<ParameterElement, ConstantReader> _parametersOfAnnotation(
    MethodElement element,
    Type type,
  ) {
    final annotations = <ParameterElement, ConstantReader>{};

    for (final p in element.parameters) {
      final a = type.toTypeChecker().firstAnnotationOf(p);

      if (a != null) {
        annotations[p] = ConstantReader(a);
      }
    }

    return annotations;
  }

  /// Returns the generated path from @Path annotated parameters.
  static Expression _generatePath(
    MethodElement element,
    ConstantReader method,
  ) {
    // Parameters annotated with @Path.
    final paths = _parametersOfAnnotation(element, annotations.Path);
    // Path value from the @Method annotation.
    var path = method.peek("path")?.stringValue ?? '';
    // Replaces the path named-segments by the @Path parameter.
    if (path.isNotEmpty) {
      paths.forEach((p, a) {
        final name = a.peek("name")?.stringValue ?? p.displayName;
        path = path.replaceFirst("{$name}", "\$${p.displayName}");
      });
    }
    // Returns the path as String literal.
    return literal(path);
  }

  /// ```dart
  /// final request = Request(method: 'GET', uri: RequestUri.parse(path));
  /// final call = restio.newCall(request);
  /// final response = await call.execute();
  /// return response;
  /// ```
  static Code _generateRequest(
    MethodElement element,
    ConstantReader method,
  ) {
    final blocks = <Code>[];

    // Request.
    final requestMethod = _generateRequestMethod(method);
    final requestUri = _generateRequestUri(element, method);
    final requestHeaders = _generateRequestHeaders(element);
    final requestQueries = _generateRequestQueries(element);
    final requestBody = _generateRequestBody(element);

    if (requestHeaders != null) {
      blocks.add(requestHeaders);
    }

    if (requestQueries != null) {
      blocks.add(requestQueries);
    }

    final request = refer('Request')
        .call(
          const [],
          {
            'method': requestMethod,
            'uri': requestUri,
            if (requestHeaders != null)
              'headers': refer('_headers.build').call(const []).expression,
            if (requestQueries != null)
              'queries': refer('_queries.build').call(const []).expression,
            if (requestBody != null) 'body': requestBody,
          },
        )
        .assignFinal('_request')
        .statement;
    blocks.add(request);
    // Call.
    final call = refer('client.newCall')
        .call([refer('_request')])
        .assignFinal('_call')
        .statement;
    blocks.add(call);
    // Response.
    final response = refer('await _call.execute')
        .call(const [])
        .assignFinal('_response')
        .statement;
    blocks.add(response);

    return Block.of(blocks);
  }

  static Expression _generateRequestMethod(ConstantReader method) {
    return literal(method.peek('name').stringValue);
  }

  static Expression _generateRequestUri(
    MethodElement element,
    ConstantReader method,
  ) {
    final path = _generatePath(element, method);
    return refer('RequestUri.parse').call(
      [path],
      {
        'baseUri': refer('baseUri').expression,
      },
    ).expression;
  }

  // TODO: Header com valor padrão, caso o parâmetro seja nulo.
  // TODO: Passar Header no método, necessita do TODO acima.
  static Code _generateRequestHeaders(MethodElement element) {
    final blocks = <Code>[];

    blocks.add(
      refer('HeadersBuilder')
          .newInstance(const [])
          .assignFinal('_headers')
          .statement,
    );

    var headers = _parametersOfAnnotation(element, annotations.Header);

    headers?.forEach((p, a) {
      final name = a.peek('name')?.stringValue ?? p.displayName;
      blocks.add(refer('_headers.add')
          .call([literal(name), literal('\$${p.displayName}')]).statement);
    });

    headers = _parametersOfAnnotation(element, annotations.Headers);

    if (headers.length > 1) {
      throw RetrofitError(
          'Only should have one @Headers-annotated parameter', element);
    }

    headers.forEach((p, a) {
      // Map<String, dynamic>.
      if (p.type.isExactlyType(Map, [String, dynamic])) {
        blocks.add(
            refer('_headers.addMap').call([refer(p.displayName)]).statement);
      }
      // Headers.
      else if (p.type.isExactlyType(Headers)) {
        blocks.add(refer('_headers.addItemList')
            .call([refer(p.displayName)]).statement);
      }
      // List<Header>.
      else if (p.type.isExactlyType(List, [Header])) {
        blocks.add(
            refer('_headers.addAll').call([refer(p.displayName)]).statement);
      } else {
        throw RetrofitError('Invalid type: ${p.type}', p);
      }
    });

    if (blocks.length > 1) {
      return Block.of(blocks);
    } else {
      return null;
    }
  }

  // TODO: Query com valor padrão, caso o parâmetro seja nulo.
  // TODO: Passar Query no método, necessita do TODO acima.
  static Code _generateRequestQueries(MethodElement element) {
    final blocks = <Code>[];

    blocks.add(refer('QueriesBuilder')
        .newInstance(const [])
        .assignFinal('_queries')
        .statement);

    var queries = _parametersOfAnnotation(element, annotations.Query);

    queries?.forEach((p, a) {
      final name = a.peek('name')?.stringValue ?? p.displayName;
      blocks.add(refer('_queries.add')
          .call([literal(name), literal('\$${p.displayName}')]).statement);
    });

    queries = _parametersOfAnnotation(element, annotations.Queries);

    if (queries.length > 1) {
      throw RetrofitError(
          'Only should have one @Queries-annotated parameter', element);
    }

    queries.forEach((p, a) {
      // Map<String, dynamic>.
      if (p.type.isExactlyType(Map, [String, dynamic])) {
        blocks.add(
            refer('_queries.addMap').call([refer(p.displayName)]).statement);
      }
      // Queries.
      else if (p.type.isExactlyType(Queries)) {
        blocks.add(refer('_queries.addItemList')
            .call([refer(p.displayName)]).statement);
      }
      // List<Query>.
      else if (p.type.isExactlyType(List, [Query])) {
        blocks.add(
            refer('_queries.addAll').call([refer(p.displayName)]).statement);
      } else {
        throw RetrofitError('Invalid type: ${p.type}', p);
      }
    });

    if (blocks.length > 1) {
      return Block.of(blocks);
    } else {
      return null;
    }
  }

  static Expression _generateRequestBody(MethodElement element) {
    // @Multipart.
    final multipart = _multiPartAnnotation(element);

    if (multipart != null) {
      return _generateRequestMultipartBody(element, multipart);
    }

    // @Form.
    final form = _formAnnotation(element);

    if (form != null) {
      return _generateRequestFormBody(element, form);
    }

    // @Body.
    final body = _parametersOfAnnotation(element, annotations.Body);

    if (body != null && body.isNotEmpty) {
      final parameters = body.keys;

      for (final p in parameters) {
        final a = body[p];
        final contentType = _generateMediaType(a);
        // String, List<int>, Stream<List<int>>, File.
        final type = p.type.isExactlyType(String)
            ? 'string'
            : p.type.isExactlyType(List, [int])
                ? 'bytes'
                : p.type.isExactlyType(Stream, [List, int])
                    ? 'stream'
                    : p.type.isExactlyType(File) ? 'file' : null;

        if (type != null) {
          return refer('RequestBody.$type').call(
            [refer(p.displayName)],
            {
              if (contentType != null) 'contentType': contentType,
            },
          );
        } else {
          throw RetrofitError('Invalid type: ${p.type}', p);
        }
      }
    }

    return null;
  }

  static Expression _generateRequestFormBody(
    MethodElement element,
    ConstantReader annotation,
  ) {
    // @Field.
    var form = _parametersOfAnnotation(element, annotations.Field);

    if (form.isNotEmpty) {
      final values = [];
      final parameters = form.keys;

      for (final p in parameters) {
        final a = form[p];

        final name = a.peek('name')?.stringValue ?? p.displayName;
        final header = refer('FormItem')
            .newInstance([literal(name), literal('\$${p.displayName}')]);
        values.add(header);
      }

      return refer('FormBody').newInstance(
        const [],
        {
          'items': literalList(values),
        },
      );
    }

    form = _parametersOfAnnotation(element, annotations.Form);

    if (form.length > 1) {
      throw RetrofitError(
          'Only should have one @Form-annotated parameter', element);
    }

    if (form.isNotEmpty) {
      final parameters = form.keys;

      for (final p in parameters) {
        // Map<String, dynamic>.
        if (p.type.isExactlyType(Map, [String, dynamic])) {
          return refer('FormBody.fromMap').call([refer(p.displayName)]);
        }
        // FormBody.
        else if (p.type.isExactlyType(FormBody)) {
          return refer(p.displayName);
        } else {
          throw RetrofitError('Invalid type: ${p.type}', p);
        }
      }
    }

    return null;
  }

  static Expression _generateRequestMultipartBody(
    MethodElement element,
    ConstantReader annotation,
  ) {
    // @Part.
    var parts = _parametersOfAnnotation(element, annotations.Part);
    final contentType = _generateMediaType(annotation);
    final boundary = annotation.peek('boundary')?.stringValue;

    if (parts.isNotEmpty) {
      final values = [];
      final parameters = parts.keys;

      for (final p in parameters) {
        final a = parts[p];

        final displayName = p.displayName;
        final name = a.peek('name')?.stringValue ?? displayName;
        final filename = a.peek('filename')?.stringValue;
        final contentType = _generateMediaType(a);
        Expression part;

        // String.
        if (p.type.isExactlyType(String)) {
          part = refer('Part.form')
              .newInstance([literal(name), literal('\$$displayName')]);
        }
        // File.
        else if (p.type.isExactlyType(File)) {
          // TODO: Charset.
          part = refer('Part.fromFile').newInstance(
            [
              literal(name),
              refer('$displayName'),
            ],
            {
              'filename': literal(filename),
              if (contentType != null) 'contentType': contentType,
            },
          );
        }
        // Part.
        else if (p.type.isExactlyType(Part)) {
          part = refer(displayName);
        }
        // List<Part>.
        else if (p.type.isExactlyType(List, [Part])) {
          part = refer('...$displayName');
        } else {
          throw RetrofitError('Invalid type: ${p.type}', p);
        }

        values.add(part);
      }

      return refer('MultipartBody').newInstance(
        const [],
        {
          'parts': literalList(values),
          if (contentType != null) 'contentType': contentType,
          if (boundary != null) 'boundary': literal(boundary),
        },
      );
    }

    parts = _parametersOfAnnotation(element, annotations.MultiPart);

    if (parts.length > 1) {
      throw RetrofitError(
          'Only should have one @MultiPart-annotated parameter', element);
    }

    if (parts.isNotEmpty) {
      final parameters = parts.keys;

      for (final p in parameters) {
        final a = parts[p];
        final pContentType = _generateMediaType(a) ?? contentType;
        final pBoundary = a.peek('boundary')?.stringValue ?? boundary;

        // List<Part>.
        if (p.type.isExactlyType(List, [Part])) {
          return refer('MultipartBody').newInstance(
            [],
            {
              'parts': refer(p.displayName),
              if (pContentType != null) 'contentType': pContentType,
              if (pBoundary != null) 'boundary': literal(pBoundary),
            },
          );
        }
        // MultipartBody.
        else if (p.type.isExactlyType(MultipartBody)) {
          return refer(p.displayName);
        }
        // Map<String, dynamic>.
        else if (p.type.isExactlyType(Map, [String, dynamic])) {
          return refer('MultipartBody.fromMap').call(
            [refer(p.displayName)],
            {
              if (pContentType != null) 'contentType': pContentType,
              if (pBoundary != null) 'boundary': literal(pBoundary),
            },
          );
        } else {
          throw RetrofitError('Invalid type: ${p.type}', p);
        }
      }
    }

    return null;
  }

  static Expression _generateMediaType(
    ConstantReader annotation, [
    String defaultValue,
  ]) {
    final contentType =
        annotation.peek('contentType')?.stringValue ?? defaultValue;

    switch (contentType?.toLowerCase()) {
      case 'application/x-www-form-urlencoded':
        return refer('MediaType.formUrlEncoded');
      case 'multipart/mixed':
        return refer('MediaType.multipartMixed');
      case 'multipart/alternative':
        return refer('MediaType.multipartAlternative');
      case 'multipart/digest':
        return refer('MediaType.multipartDigest');
      case 'multipart/parallel':
        return refer('MediaType.multipartParallel');
      case 'multipart/form-data':
        return refer('MediaType.multipartFormData');
      case 'application/json':
        return refer('MediaType.json');
      case 'application/octet-stream':
        return refer('MediaType.octetStream');
      case 'text/plain':
        return refer('MediaType.text');
    }

    if (contentType != null) {
      return refer('MediaType.parse').call([refer(contentType)]);
    } else {
      return null;
    }
  }

  static ConstantReader _findAnnotation(
    MethodElement element,
    Type type,
  ) {
    final a = type
        .toTypeChecker()
        .firstAnnotationOf(element, throwOnUnresolved: false);

    if (a != null) {
      return ConstantReader(a);
    } else {
      return null;
    }
  }

  static ConstantReader _methodAnnotation(MethodElement element) {
    ConstantReader a;

    for (var i = 0; a == null && i < _methodAnnotations.length; i++) {
      a = _findAnnotation(element, _methodAnnotations[i]);
    }

    return a;
  }

  static ConstantReader _formAnnotation(MethodElement element) {
    return _findAnnotation(element, annotations.Form);
  }

  static ConstantReader _multiPartAnnotation(MethodElement element) {
    return _findAnnotation(element, annotations.MultiPart);
  }
}

Builder generatorFactoryBuilder(BuilderOptions options) => SharedPartBuilder(
      [RetrofitGenerator()],
      "retrofit",
    );

Builder retrofitBuilder(BuilderOptions options) =>
    generatorFactoryBuilder(options);

extension DartTypeExtension on DartType {
  bool get isDartStream {
    return element != null && element.name == "Stream";
  }

  bool get isDartAsyncStream {
    return isDartStream && element.library.isDartAsync;
  }
}

extension DartTypeExtenstion on DartType {
  TypeChecker toTypeChecker() {
    return TypeChecker.fromStatic(this);
  }

  bool isExactlyType(
    Type type, [
    List<Type> types = const [],
  ]) {
    final genericTypes = extractParameterTypes().sublist(1);

    if (!type.isExactlyType(this)) {
      return false;
    }

    if (genericTypes.length != types.length) {
      return false;
    }

    for (var i = 0; i < genericTypes.length; i++) {
      if (types[i] != null &&
          types[i] != dynamic &&
          !types[i].isExactlyType(genericTypes[i])) {
        return false;
      }
    }

    return true;
  }

  List<DartType> extractParameterTypes() {
    return _extractParameterTypes(this);
  }

  static List<DartType> _extractParameterTypes(DartType type) {
    if (type is ParameterizedType) {
      return [
        type,
        for (final a in type.typeArguments) ..._extractParameterTypes(a),
      ];
    } else {
      return [type];
    }
  }
}

extension TypeExtension on Type {
  TypeChecker toTypeChecker() {
    return TypeChecker.fromRuntime(this);
  }

  bool isExactlyType(DartType type) {
    return toTypeChecker().isExactlyType(type);
  }
}

class RetrofitError extends InvalidGenerationSourceError {
  RetrofitError(String message, Element element)
      : super(message, element: element);
}
