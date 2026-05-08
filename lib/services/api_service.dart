import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // FastAPI sunucusu localhost'ta çalışıyorsa (Desktop)
  static const String baseUrl = 'http://127.0.0.1:8000';

  /// Görüntü çerçevesini Base64 formatında gönderir ve çukur koordinatlarını alır.
  static Future<List<dynamic>> detectPotholes(String base64Image) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/predict_base64'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['detections'] ?? [];
      } else {
        print('API Hatası: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Bağlantı Hatası: $e');
      return [];
    }
  }

  /// Görüntü dosyasını doğrudan (Multipart) gönderir. Base64 encode yükünden kurtarır.
  static Future<List<dynamic>> detectPotholesFile(String filePath, {bool saveRecord = false}) async {
    try {
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('$baseUrl/predict?save_record=$saveRecord')
      );
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['detections'] ?? [];
      } else {
        print('API Hatası (File): ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Bağlantı Hatası (File): $e');
      return [];
    }
  }

  /// Görüntü çerçevesini ham Byte formatında (BGRA8888) gönderir. (0 Gecikme)
  static Future<List<dynamic>> detectPotholesRaw(List<int> bytes, int width, int height, {bool saveRecord = false}) async {
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/predict_raw'));
      request.headers['Content-Type'] = 'application/octet-stream';
      request.headers['X-Image-Width'] = width.toString();
      request.headers['X-Image-Height'] = height.toString();
      if (saveRecord) {
        request.headers['X-Save-Record'] = 'true';
      }
      request.bodyBytes = bytes;

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['detections'] ?? [];
      } else {
        print('API Hatası: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Bağlantı Hatası (Raw): $e');
      return [];
    }
  }

  /// Sunucu durumunu kontrol eder.
  static Future<bool> checkServerStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
