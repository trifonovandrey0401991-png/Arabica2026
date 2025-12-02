// Stub для dart:html на мобильных платформах
// Этот файл используется вместо dart:html когда платформа не поддерживает его

import 'dart:async';

class HttpRequest {
  int? status;
  String? responseText;
  String? statusText;
  
  void open(String method, String url, [bool? async, String? user, String? password]) {}
  void setRequestHeader(String name, String value) {}
  void send([dynamic data]) {}
  void abort() {}
  
  Stream<dynamic> get onLoad => const Stream<dynamic>.empty();
  Stream<dynamic> get onError => const Stream<dynamic>.empty();
}

class FormData {
  void appendBlob(String name, Blob blob, [String? fileName]) {}
  void append(String name, String value) {}
}

class Blob {
  final List<int> data;
  final String type;
  
  Blob(this.data, this.type);
}

