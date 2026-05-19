import 'dart:convert';
import 'dart:io';
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
  static Future<List<dynamic>> detectPotholesFile(String filePath, {bool saveRecord = false, double? latitude, double? longitude}) async {
    try {
      var url = '$baseUrl/predict?save_record=$saveRecord';
      if (latitude != null) url += '&latitude=$latitude';
      if (longitude != null) url += '&longitude=$longitude';

      var request = http.MultipartRequest(
        'POST', 
        Uri.parse(url)
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

  static bool _isStartingBackend = false;

  /// Sunucu durumunu kontrol eder ve kapalıysa otomatik başlatmayı dener.
  static Future<bool> checkServerStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/')).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (e) {
      // Sunucu çevrimdışı, arka planda başlatmayı deneyelim (Sadece Windows)
      if (!_isStartingBackend) {
        _tryStartBackend();
      }
      return false;
    }
  }

  static void _tryStartBackend() async {
    _isStartingBackend = true;
    try {
      if (Platform.isWindows) {
        // Geliştirme (flutter run) ve Production (exe) dizinlerini idare etmek için:
        final currentDir = Directory.current.path;
        final exeDir = File(Platform.resolvedExecutable).parent.path;

        // Önce üretim (exe) ortamındaki konuma bak
        String backendDir = '$exeDir\\backend';
        String venvPython = '$backendDir\\.venv\\Scripts\\pythonw.exe';
        String appPy = '$backendDir\\app.py';

        if (!(await File(appPy).exists())) {
          // Bulunamazsa geliştirme (flutter run) ortamındaki konuma bak
          backendDir = '$currentDir\\backend';
          venvPython = '$backendDir\\.venv\\Scripts\\pythonw.exe';
          appPy = '$backendDir\\app.py';
        }

        if (await File(venvPython).exists()) {
          // Virtual environment python'u ile başlat
          await Process.start(venvPython, [appPy], workingDirectory: backendDir, runInShell: false, mode: ProcessStartMode.detached);
          print('Backend otomatik başlatıldı (Venv). Yol: $appPy');
        } else if (await File(appPy).exists()) {
          // Sistem python'u ile başlat
          await Process.start('pythonw', [appPy], workingDirectory: backendDir, runInShell: false, mode: ProcessStartMode.detached);
          print('Backend otomatik başlatıldı (Sistem Python). Yol: $appPy');
        } else {
          print('Backend scripti (app.py) bulunamadı!');
        }
      }
    } catch (e) {
      print('Backend otomatik başlatılamadı: $e');
    } finally {
      // Çok sık denememek için bekleme süresi
      await Future.delayed(const Duration(seconds: 10));
      _isStartingBackend = false;
    }
  }

  /// IP adresi üzerinden yaklaşık konumu (Enlem, Boylam) çeker. Windows'taki Geolocator çökmesini önler.
  static Future<Map<String, double>?> getLocationFromIP() async {
    try {
      final response = await http.get(Uri.parse('http://ip-api.com/json/'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return {
            'latitude': (data['lat'] as num).toDouble(),
            'longitude': (data['lon'] as num).toDouble(),
          };
        }
      }
    } catch (e) {
      print('IP Konum Hatası: $e');
    }
    return null;
  }
}
