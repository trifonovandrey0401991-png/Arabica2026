class PhoneNormalizer {
  static String normalize(String phone) {
    return phone.replaceAll(RegExp(r'[\s\+]'), '');
  }
}
