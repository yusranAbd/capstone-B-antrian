import 'package:http/browser_client.dart';

BrowserClient createDisplayClient(Uri apiBase) =>
    BrowserClient()..withCredentials = true;
