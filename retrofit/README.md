# Retrofit

HTTP client generator for Restio ispired by [Retrofit](https://square.github.io/retrofit/).

## Installation

In `pubspec.yaml` add the following dev_dependencies:

```yaml
dev_dependencies:
  restio_retrofit: ^0.1.0
  build_runner: ^1.10.0
```

## Usage

### Define and Generate your API

```dart
import 'package:restio/restio.dart';
import 'package:restio/retrofit.dart' as retrofit;

part 'httpbin.g.dart';

@retrofit.Api('https://httpbin.org')
abstract class HttpbinApi {
  factory HttpbinApi({Restio client, String baseUri}) = _HttpbinApi;

  @retrofit.Get('/get')
  Future<String> get();
}
```

> It is **highly recommended** that you prefix the retrofit library.

Then run the generator
```bash
# Dart
pub run build_runner build

# Flutter
flutter pub run build_runner build
```

### Use It

```dart
import 'package:restio/restio.dart';

import 'httpbin.dart';

void main(List<String> args) async {
  final client = Restio();
  final api = HttpbinApi(client: client);
  final data = await api.get();
  print(data);
}
```

## API Declaration

Annotations on the methods and its parameters indicate how a request will be handled.

### Http Methods

Every method must have an HTTP Method annotation that provides the request method and relative URL. There are eight built-in annotations: `Method`, `Get`, `Post`, `Put`, `Patch`, `Delete`, `Options` and `Head`. The relative URL of the resource is specified in the annotation.

```dart
@retrofit.Get('/get')
```

You can also specify query parameters in the URL.

```dart
@retrofit.Get('users/list?sort=desc')
```

### URL Manipulation

A request URL can be updated dynamically using replacement blocks and parameters on the method. A replacement block is an alphanumeric name surrounded by `{` and `}`. A corresponding parameter must be annotated with `Path`. If the `Path` name is omitted the parameter name is used instead.

```dart
@retrofit.Get('group/{id}/users')
Future<List<User>> groupList(@retrofit.Path('id') int groupId);
```

Query parameters can also be added.

```dart
@retrofit.Get('group/{id}/users')
Future<List<User>> groupList(@retrofit.Path('id') int groupId, @retrofit.Query() String sort);
```

For complex query parameter combinations a `Map<String, ?>`, `Queries`, `List<Query>` can be used. In this case, annotate the parameters with `Queries`.

You can set static queries for a method using the `Query` annotation.

```dart
@retrofit.Query('sort' ,'desc')
Future<List<User>> groupList(@retrofit.Path('id') int groupId);
```

Note that queries do not overwrite each other. All queries with the same name will be included in the request.

```dart
@retrofit.Get('group/{id}/users')
Future<List<User>> groupList(@retrofit.Path('id') int groupId, @retrofit.Queries() Map<String, dynamic> options);
```

If you desire add queries with no values, you can use `List<String>`.

```dart
@retrofit.Get('group/{id}/users')
Future<List<User>> groupList(@retrofit.Path('id') int groupId, @retrofit.Queries() List<String> flags);
```

### Request Body

An object can be specified for use as an HTTP request body with the `Body` annotation.

```dart
@retrofit.Get('group/{id}/users')
Future<void> createUser(@retrofit.Body() User user);
```

The object will also be converted using a converter specified on the Api instance. If no converter is added, only `File`, `String`, `List<int>`, `Stream<List<int>>` or `RequestBody` can be used.

### Form and Multipart

Methods can also be declared to send form-encoded and multipart data.

Form-encoded data is sent when `Form` annotation is present on the method. Each key-value pair (field) is annotated with `Field` containing the name (optional, the parameter name will be sed instead) and the object providing the value.

```dart
@retrofit.Form()
@retrofit.Post('user/edit')
Future<User> updateUser(@retofit.Field("first_name") String first, @retrofit.Field("last_name") String last);
```

You can set static field for a method using the `Field` annotation.

```dart
@retrofit.Field('first_name' ,'Tiago')
@retrofit.Field('last_name' ,'Melo')
Future<User> updateUserEmail(@retofit.Field() String email);
```

Note that fields do not overwrite each other. All fields with the same name will be included in the request.

Multipart requests are used when `Multipart` annotation is present on the method. Parts are declared using the `Part` annotation.

```dart
@retrofit.Multipart()
@retrofit.Put('user/photo')
Future<User> updateUser(@retrofit.Part() File photo);
```

The parameter type can be only `File`, `String`, `Part` or `List<Part>`. For `File` parameter type you can set the `filename` and `contentType` properties.

### Header Manipulation

You can set static headers for a method using the `Header` annotation.

```dart
@retrofit.Header('Accept' ,'application/vnd.github.v3.full+json')
@retrofit.Header('User-Agent' ,'Retrofit')
@retrofit.Get('users/{username}')
Future<User> getUser(@retrofit.Path() String username);
```

Note that headers do not overwrite each other. All headers with the same name will be included in the request.

A request Header can be updated dynamically using the `Header` annotation. A corresponding parameter must be provided to the `Header`. If the name is omitted, the parameter name will be used instead.

```dart
@retrofit.Get('user')
Future<User> getUser(@retrofit.Header('Authorization') String authorization);
```

Similar to query parameters, for complex header combinations a `Map<String, ?>`, `Headers`, `List<Header>` can be used. In this case, annotate the parameters with `Headers`.

```dart
@retrofit.Get('user')
Future<User> getUser(@retrofit.Headers() Map<String, dynamic> headers);
```

Headers that need to be added to every request can be specified using an interceptor.

### Converters

Annotate the API class with `Converter` to register the complex class and your converter. The converter class must implement the `decode`, `decodeList` and `encode` as static method.

```dart
class User {
  final String name;

  const User(this.name);

  // You can use json_serializable package if you wish.
  factory User.fromJson(dynamic data) {
    return User(data['name']);
  }

  Map<String, dynamic> toJson() {
    return {'name': name};
  }
}

// You can use Flutter compute method!
class UserConverter {
  static Future<String> encode(User data) async {
    return json.encode(data);
  }

  static Future<User> decode(String data) async {
    return User.fromJson(json.decode(data));
  }

  static Future<List<User>> decodeList(String data) async {
    return [for (final item in json.decode(data)) User.fromJson(item)];
  }
}

@retrofit.Api('https://httpbin.org')
@retrofit.Converter(User, UserConverter)
abstract class HttpbinApi {
  // ...

  @retrofit.Get('users/{id}')
  Future<User> getUser(@retrofit.Path() int id);

  @retrofit.Get('users')
  Future<List<User>> getUsers();
}
```

List of complex classes is supported too.

```dart
@retrofit.Get('user')
Future<List<User>> getUsers();
```

### Response

The method return type can be `Future<List<int>>` for decompressed data, `Future<String>`, `Future<dynamic>` to JSON decoded data, `Future<int>` for the response code, `Future<Response>`, `Stream<List<int>>` or `Future<?>` for complex class conversion.

You can get the uncompressed data annotating the method with `Raw` e using `Future<List<int>>`.

```dart
@retrofit.Raw()
@retrofit.Get('/gzip')
Future<List<int>> gzip();
```

If you use `Future<Response>` or `Stream<List<int>>` you are responsible for closing the response.

### Response Status Exception

For default, if the response status is not between 200-299, will be throw the `HttpStatusException`.

You can specify the status code range annotating the method with `Throws`.

```dart
@retrofit.Throws(400, 600)
@retrofit.Get('/users/{id}')
Future<User> getUser(@retrofit.Path() int id)
```

There are seven built-in Throws annotations:

 * `@retrofit.Throws.only(int code)`: Specify the status code that throws the exception.
 * `@retrofit.Throws.not(int code)`: Specify the status code that not throws the exception.
 * `@retrofit.Throws.redirect()`: Throws the exception only if the response code is from redirects.
 * `@retrofit.Throws.notRedirect()`: Throws the exception only  if the response code is not from redirects.
 * `@retrofit.Throws.error()`: Throws the exception  only if the response code is a client error or server error.
 * `@retrofit.Throws.clientError()`: Throws the exception only if the response code is a client error.
 * `@retrofit.Throws.serverError()`: Throws the exception only if the response code is a server error.

You are responsible for closing the response on catch block.

```dart
try {
  final user = await api.getUser(0);
} on HttpStatusException catch(e) {
  final code = e.code;
  final response = e.response;
  await response.close();
}
```

`Future<int>` and `Future<Response>` does not throws the exception even if annotating the method with `Throws`.

If you want to prevent the exception from being thrown, annotate the method with `NotThrows`.

### Request Options & Extra

If you want pass `RequestOptions` to the request, just add the parameter to the method.

```dart
@retrofit.Get('/')
Future<dynamic> get(RequestOptions options);
```

If you want pass `Map<String, dynamic>` as extra property to the request, annotate the parameter with `Extra`.

```dart
@retrofit.Get('/')
Future<dynamic> get(@retrofit.Extra() Map<String, dynamic> extra);
```