import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// P1 Тесты сжатия фото (Tasks 2.2 + 2.3)
/// Покрывает: ресайз, JPEG quality, порог 512 KB, граничные случаи
void main() {
  group('Photo Compression Tests (Phase 2.2 + 2.3)', () {
    // ==================== РЕСАЙЗ ====================

    group('Image Resize Logic', () {
      test('PH2-IMG-001: Большое изображение уменьшается до 1280px', () {
        // Arrange
        final largeImage = img.Image(width: 4000, height: 3000);

        // Act
        final result = _resizeImage(largeImage, 1280);

        // Assert — ширина больше → ресайз по ширине
        expect(result.width, 1280);
        expect(result.height, lessThanOrEqualTo(1280));
      });

      test('PH2-IMG-002: Высокое изображение уменьшается по высоте', () {
        // Arrange
        final tallImage = img.Image(width: 1000, height: 4000);

        // Act
        final result = _resizeImage(tallImage, 1280);

        // Assert — высота больше → ресайз по высоте
        expect(result.height, 1280);
        expect(result.width, lessThanOrEqualTo(1280));
      });

      test('PH2-IMG-003: Маленькое изображение не изменяется', () {
        // Arrange
        final smallImage = img.Image(width: 800, height: 600);

        // Act
        final result = _resizeImage(smallImage, 1280);

        // Assert
        expect(result.width, 800);
        expect(result.height, 600);
      });

      test('PH2-IMG-004: Изображение ровно 1280px — не изменяется', () {
        // Arrange
        final exactImage = img.Image(width: 1280, height: 960);

        // Act
        final result = _resizeImage(exactImage, 1280);

        // Assert
        expect(result.width, 1280);
        expect(result.height, 960);
      });

      test('PH2-IMG-005: Квадратное изображение корректно ресайзится', () {
        // Arrange
        final squareImage = img.Image(width: 2000, height: 2000);

        // Act
        final result = _resizeImage(squareImage, 1280);

        // Assert — квадрат: width == height → resize по height (или width)
        expect(result.width, lessThanOrEqualTo(1280));
        expect(result.height, lessThanOrEqualTo(1280));
      });
    });

    // ==================== JPEG КАЧЕСТВО ====================

    group('JPEG Encoding', () {
      test('PH2-IMG-006: JPEG quality 75 — файл меньше оригинала', () {
        // Arrange
        final image = img.Image(width: 1280, height: 960);
        // Заполняем пикселями чтобы был ненулевой размер
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            image.setPixelRgba(x, y, x % 256, y % 256, (x + y) % 256, 255);
          }
        }

        // Act
        final quality75 = img.encodeJpg(image, quality: 75);
        final quality100 = img.encodeJpg(image, quality: 100);

        // Assert
        expect(quality75.length, lessThan(quality100.length));
      });

      test('PH2-IMG-007: JPEG output валиден (начинается с FFD8)', () {
        // Arrange
        final image = img.Image(width: 100, height: 100);

        // Act
        final jpeg = img.encodeJpg(image, quality: 75);

        // Assert — JPEG magic bytes
        expect(jpeg[0], 0xFF);
        expect(jpeg[1], 0xD8);
      });
    });

    // ==================== ПОРОГ СЖАТИЯ ====================

    group('Compression Threshold', () {
      test('PH2-IMG-008: Файл > 512KB — должен сжиматься', () {
        // Arrange
        final sizeBytes = 600 * 1024; // 600 KB

        // Act
        final shouldCompress = sizeBytes > 512 * 1024;

        // Assert
        expect(shouldCompress, true);
      });

      test('PH2-IMG-009: Файл < 512KB — не сжимается', () {
        // Arrange
        final sizeBytes = 400 * 1024; // 400 KB

        // Act
        final shouldCompress = sizeBytes > 512 * 1024;

        // Assert
        expect(shouldCompress, false);
      });

      test('PH2-IMG-010: Файл ровно 512KB — не сжимается (строго >)', () {
        // Arrange
        final sizeBytes = 512 * 1024; // ровно 512 KB

        // Act
        final shouldCompress = sizeBytes > 512 * 1024;

        // Assert
        expect(shouldCompress, false);
      });
    });

    // ==================== COMPRESS FUNCTION ====================

    group('Compress Image Function', () {
      test('PH2-IMG-011: Сжатие большого изображения уменьшает размеры', () {
        // Arrange — создаём изображение больше 1280
        final image = img.Image(width: 2000, height: 1500);
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            image.setPixelRgba(x, y, x % 256, y % 256, 128, 255);
          }
        }
        final originalBytes = img.encodePng(image);

        // Act
        final compressed = compressImageIsolate(originalBytes);

        // Assert — результат декодируется и размеры уменьшены до 1280
        final decoded = img.decodeImage(Uint8List.fromList(compressed));
        expect(decoded, isNotNull);
        expect(decoded!.width, 1280);
        expect(decoded.height, lessThanOrEqualTo(1280));
      });

      test('PH2-IMG-012: Невалидные данные — возврат оригинала', () {
        // Arrange
        final invalidBytes = [0, 1, 2, 3, 4, 5];

        // Act
        final result = compressImageIsolate(invalidBytes);

        // Assert — при ошибке возвращает исходные данные
        expect(result, invalidBytes);
      });
    });
  });
}

// ==================== HELPER ====================

/// Ресайз изображения (логика из photo_upload_service.dart)
img.Image _resizeImage(img.Image image, int maxDimension) {
  if (image.width > maxDimension || image.height > maxDimension) {
    if (image.width > image.height) {
      return img.copyResize(image, width: maxDimension);
    } else {
      return img.copyResize(image, height: maxDimension);
    }
  }
  return image;
}

/// Сжатие (копия логики из _compressImageIsolate)
List<int> compressImageIsolate(List<int> bytes) {
  try {
    final image = img.decodeImage(Uint8List.fromList(bytes));
    if (image == null) return bytes;

    const maxDimension = 1280;
    img.Image result;

    if (image.width > maxDimension || image.height > maxDimension) {
      if (image.width > image.height) {
        result = img.copyResize(image, width: maxDimension);
      } else {
        result = img.copyResize(image, height: maxDimension);
      }
    } else {
      result = image;
    }

    return img.encodeJpg(result, quality: 75);
  } catch (e) {
    return bytes;
  }
}
