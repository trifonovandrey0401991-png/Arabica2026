// Stub для dart:html на мобильных платформах
// Этот файл используется вместо dart:html когда платформа не поддерживает его

import 'dart:async';

class HttpRequest {
  int? status;
  String? responseText;
  
  void open(String method, String url, bool async) {}
  void setRequestHeader(String name, String value) {}
  void send([dynamic data]) {}
  
  Stream<dynamic> get onLoad => const Stream<dynamic>.empty();
  Stream<dynamic> get onError => const Stream<dynamic>.empty();
}

class FormData {
  void appendBlob(String name, Blob blob, String fileName) {}
  void append(String name, String value) {}
}

class Blob {
  Blob(List<int> data, String type);
}

