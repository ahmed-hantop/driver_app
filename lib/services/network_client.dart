import 'package:http/http.dart' as http;

class DriverAppHttpClient {
  DriverAppHttpClient._();

  static final http.Client client = http.Client();
}