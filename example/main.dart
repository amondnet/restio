import 'package:restio/restio.dart';

final _client = Restio();

Future<void> main() async {
  final request = Request.get('https://api.ipify.org?format=json');
  final call = _client.newCall(request);
  final response = await call.execute();
  final data = await response.body.data.json();

  print(data['ip']);
}
