import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../models/pothole_record.dart';
import 'package:path_provider/path_provider.dart';

class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({super.key});

  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isDetecting = false;
  bool _isServerActive = false;
  bool _isCheckingServer = false;
  String? _cameraError;
  DateTime _lastSaveTime = DateTime.now();
  List<dynamic> _detections = [];

  Map<String, double>? _currentPosition;
  Map<String, double>? _lastSavedPosition;
  Timer? _locationTimer;
  Timer? _serverCheckTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_initCamera());
    unawaited(_initLocation());
    unawaited(_checkServer());

    // Sunucu durumunu her 2 saniyede bir kontrol et
    _serverCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      unawaited(_checkServer());
    });
  }

  Future<void> _checkServer() async {
    if (_isCheckingServer) return;
    _isCheckingServer = true;
    try {
      final isActive = await ApiService.checkServerStatus();
      if (mounted && _isServerActive != isActive) {
        setState(() {
          _isServerActive = isActive;
        });
      }
    } finally {
      _isCheckingServer = false;
    }
  }

  Future<void> _initLocation() async {
    // 1. Önce cihazın gerçek GPS/Konum servisini deniyoruz.
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );
      _currentPosition = {'latitude': pos.latitude, 'longitude': pos.longitude};
      debugPrint('Windows konumu başarıyla alındı.');
    } catch (e) {
      debugPrint(
        "Windows konumu alınamadı, IP tabanlı yaklaşık konum deneniyor: $e",
      );
      // 2. Eğer Windows Konum izni verilmemişse veya çip yoksa IP üzerinden gerçek konuma en yakın şehri alıyoruz.
      _currentPosition = await ApiService.getLocationFromIP();
    }

    // Her 2 saniyede bir konumu güncelle (Daha hassas takip için)
    _locationTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 2),
        );
        _currentPosition = {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
        };
      } catch (_) {
        // Sessizce yoksay ve eski konumu tut
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw CameraException('camera_not_found', 'Kamera bulunamadı');
      }
      final controller = CameraController(
        _cameras![0],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() {
          _cameraError = 'Kamera başlatılamadı: $error';
        });
      }
    }
  }

  void _toggleDetection() {
    if (_isDetecting) {
      setState(() {
        _isDetecting = false;
        _detections = [];
      });
    } else {
      setState(() {
        _isDetecting = true;
      });
      // Start async loop
      unawaited(_startDetectionLoop());
    }
  }

  Future<void> _startDetectionLoop() async {
    while (_isDetecting && mounted) {
      if (_controller == null ||
          !_controller!.value.isInitialized ||
          _controller!.value.isTakingPicture) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      XFile? picture;
      try {
        picture = await _controller!.takePicture();

        final now = DateTime.now();

        // 1. Gelişmiş Mükerrer Kontrolü ve Cooldown Akıllı Algoritması
        bool isDuplicate = false;
        if (_lastSavedPosition != null && _currentPosition != null) {
          double distance = Geolocator.distanceBetween(
            _lastSavedPosition!['latitude']!,
            _lastSavedPosition!['longitude']!,
            _currentPosition!['latitude']!,
            _currentPosition!['longitude']!,
          );

          final secondsSinceLastSave = now.difference(_lastSaveTime).inSeconds;

          // - Araç tamamen duruyorsa/trafik ışığındaysa (mesafe < 2m), 30 saniye boyunca tekrar kaydetme.
          // - Araç çok yavaş hareket ediyorsa (mesafe < 8m), 6 saniye boyunca tekrar kaydetme.
          // - Araç normal hızda seyrediyorsa (mesafe >= 8m), her yeni çukuru anında kaydet.
          if (distance < 2.0 && secondsSinceLastSave < 30) {
            isDuplicate = true;
          } else if (distance < 8.0 && secondsSinceLastSave < 6) {
            isDuplicate = true;
          }
        }

        // Mükerrer değilse ve en az 1 saniye geçmişse kaydetmeye izin ver
        bool shouldSave =
            !isDuplicate && now.difference(_lastSaveTime).inSeconds >= 1;

        final results = await ApiService.detectPotholesFile(
          picture.path,
          saveRecord: shouldSave,
          latitude: _currentPosition?['latitude'],
          longitude: _currentPosition?['longitude'],
        );

        // Tek kare içindeki çakışan (aynı çukuru temsil eden) mükerrer kutuları temizle
        final cleanResults = _cleanOverlappingDetections(results);

        if (shouldSave && cleanResults.isNotEmpty) {
          _lastSaveTime = now;
          if (_currentPosition != null) {
            _lastSavedPosition = {
              'latitude': _currentPosition!['latitude']!,
              'longitude': _currentPosition!['longitude']!,
            };
          }

          // Resmi yerel kalici klasore kopyala
          final directory = await getApplicationDocumentsDirectory();
          final String dirPath = '${directory.path}/RoadGuard/Images';
          await Directory(dirPath).create(recursive: true);
          final permanentImagePath =
              '$dirPath/${DateTime.now().millisecondsSinceEpoch}.jpg';
          await File(picture.path).copy(permanentImagePath);

          final dateStr =
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
          final timeStr =
              "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

          for (var det in cleanResults) {
            final conf = det['confidence'] ?? 0.0;
            final record = PotholeRecord(
              date: dateStr,
              time: timeStr,
              confidence: conf,
              latitude: _currentPosition?['latitude'] ?? 0.0,
              longitude: _currentPosition?['longitude'] ?? 0.0,
              imagePath: permanentImagePath,
              className: det['class'] ?? 'minor_pothole',
            );
            await DbService.instance.insertPothole(record);
          }
        }

        if (mounted && _isDetecting) {
          setState(() {
            _detections = cleanResults;
          });
        }
      } catch (e) {
        debugPrint('Kare işleme hatası: $e');
        await Future.delayed(const Duration(milliseconds: 500));
      } finally {
        if (picture != null) {
          final temporaryFile = File(picture.path);
          if (await temporaryFile.exists()) {
            try {
              await temporaryFile.delete();
            } on FileSystemException catch (error) {
              debugPrint('Geçici kamera dosyası silinemedi: $error');
            }
          }
        }
      }
    }
  }

  /// Aynı nesneyi temsil eden üst üste binmiş kutuları eler, yüksek olanı tutar
  List<dynamic> _cleanOverlappingDetections(List<dynamic> rawDetections) {
    if (rawDetections.isEmpty) return [];

    List<dynamic> clean = [];
    for (var det in rawDetections) {
      final bbox = det['bbox'];
      if (bbox == null || bbox.length < 4) continue;

      bool isOverlapping = false;
      int replaceIndex = -1;

      for (int i = 0; i < clean.length; i++) {
        final existing = clean[i];
        final existingBbox = existing['bbox'];
        if (existingBbox == null || existingBbox.length < 4) continue;

        double overlap = _calculateOverlap(bbox, existingBbox);
        if (overlap > 0.4) {
          // %40'tan fazla üst üste binme varsa aynı çukurdur
          isOverlapping = true;
          // Güven skoru daha yüksek olanı tercih et
          if ((det['confidence'] ?? 0.0) > (existing['confidence'] ?? 0.0)) {
            replaceIndex = i;
          }
          break;
        }
      }

      if (!isOverlapping) {
        clean.add(det);
      } else if (replaceIndex != -1) {
        clean[replaceIndex] = det;
      }
    }
    return clean;
  }

  /// İki sınırlayıcı kutu arasındaki çakışma oranını kesişim / en küçük alan şeklinde hesaplar
  double _calculateOverlap(List<dynamic> boxA, List<dynamic> boxB) {
    double ax1 = (boxA[0] as num).toDouble();
    double ay1 = (boxA[1] as num).toDouble();
    double ax2 = (boxA[2] as num).toDouble();
    double ay2 = (boxA[3] as num).toDouble();

    double bx1 = (boxB[0] as num).toDouble();
    double by1 = (boxB[1] as num).toDouble();
    double bx2 = (boxB[2] as num).toDouble();
    double by2 = (boxB[3] as num).toDouble();

    double xMin = ax1 > bx1 ? ax1 : bx1;
    double yMin = ay1 > by1 ? ay1 : by1;
    double xMax = ax2 < bx2 ? ax2 : bx2;
    double yMax = ay2 < by2 ? ay2 : by2;

    if (xMax <= xMin || yMax <= yMin) {
      return 0.0;
    }

    double intersectionArea = (xMax - xMin) * (yMax - yMin);

    double areaA = (ax2 - ax1) * (ay2 - ay1);
    double areaB = (bx2 - bx1) * (by2 - by1);

    double minArea = areaA < areaB ? areaA : areaB;
    if (minArea <= 0.0) return 0.0;

    return intersectionArea / minArea;
  }

  @override
  void dispose() {
    _isDetecting = false;
    _locationTimer?.cancel();
    _serverCheckTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_cameraError!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Canlı Tespit Sistemi',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _isServerActive
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isServerActive ? Colors.green : Colors.red,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isServerActive ? Icons.check_circle : Icons.error,
                      color: _isServerActive ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isServerActive ? 'Sunucu Aktif' : 'Sunucu Çevrimdışı',
                      style: TextStyle(
                        color: _isServerActive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: 1000 * _controller!.value.aspectRatio,
                    height: 1000,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        // Bounding Box Çizimi
                        CustomPaint(
                          painter: BoundingBoxPainter(
                            detections: _detections,
                            imageSize:
                                _controller!.value.previewSize ??
                                const Size(1280, 720),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: _isServerActive ? _toggleDetection : null,
              icon: Icon(_isDetecting ? Icons.stop : Icons.play_arrow),
              label: Text(_isDetecting ? 'Tespiti Durdur' : 'Tespiti Başlat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDetecting
                    ? Colors.red
                    : Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 20,
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<dynamic> detections;
  final Size imageSize;

  static const Map<String, String> classTranslations = {
    'minor_pothole': 'Hafif Çukur',
    'medium_pothole': 'Orta Çukur',
    'major_pothole': 'Ağır Çukur',
    'speed_bump': 'Kasis',
  };

  static const Map<String, Color> classColors = {
    'minor_pothole': Colors.amber,
    'medium_pothole': Colors.orange,
    'major_pothole': Colors.redAccent,
    'speed_bump': Colors.blueAccent,
  };

  BoundingBoxPainter({required this.detections, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var det in detections) {
      final rect = det['bbox']; // [nx1, ny1, nx2, ny2] (normalized 0 to 1)
      if (rect == null) continue;

      final conf = det['confidence'] ?? 0.0;
      final className = det['class'] ?? 'minor_pothole';
      final translatedName = classTranslations[className] ?? className;
      final color = classColors[className] ?? Colors.red;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      // Since coordinates from backend are normalized (0.0 to 1.0)
      // On Windows desktop, the CameraPreview is typically mirrored horizontally (like a mirror),
      // but the raw frames sent to the backend are NOT mirrored.
      // Therefore, we must mirror the bounding box horizontally to match the preview.
      final left = (1.0 - rect[2]) * size.width;
      final top = rect[1] * size.height;
      final right = (1.0 - rect[0]) * size.width;
      final bottom = rect[3] * size.height;

      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);

      textPainter.text = TextSpan(
        text: '$translatedName ${(conf * 100).toStringAsFixed(1)}%',
        style: TextStyle(
          color: Colors.white,
          backgroundColor: color,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(left, top - textPainter.height));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
