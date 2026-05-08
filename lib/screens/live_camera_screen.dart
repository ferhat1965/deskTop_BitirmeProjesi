import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../models/pothole_record.dart';

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
  bool _isProcessingFrame = false;
  DateTime _lastSaveTime = DateTime.now();
  List<dynamic> _detections = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
    _checkServer();
  }

  Future<void> _checkServer() async {
    final isActive = await ApiService.checkServerStatus();
    if (mounted) {
      setState(() {
        _isServerActive = isActive;
      });
    }
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _controller = CameraController(
        _cameras![0],
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) {
        setState(() {});
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
      _startDetectionLoop();
    }
  }

  Future<void> _startDetectionLoop() async {
    while (_isDetecting && mounted) {
      if (_controller == null || !_controller!.value.isInitialized || _controller!.value.isTakingPicture) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      try {
        final XFile picture = await _controller!.takePicture();
        
        final now = DateTime.now();
        final bool shouldSave = now.difference(_lastSaveTime).inSeconds >= 3;

        final results = await ApiService.detectPotholesFile(
          picture.path,
          saveRecord: shouldSave,
        );
        
        if (shouldSave && results.isNotEmpty) {
          _lastSaveTime = now;
        }
        
        if (mounted && _isDetecting) {
          setState(() {
            _detections = results;
          });
        }
        
        // İşlem bittikten sonra geçici resmi sil
        File(picture.path).deleteSync();
        
      } catch (e) {
        print("Kare işleme hatası: $e");
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  @override
  void dispose() {
    _isDetecting = false;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isServerActive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
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
              )
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller!),
                      // Bounding Box Çizimi
                      CustomPaint(
                        painter: BoundingBoxPainter(
                          detections: _detections,
                          imageSize: _controller!.value.previewSize!,
                        ),
                      ),
                    ],
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
                backgroundColor: _isDetecting ? Colors.red : Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<dynamic> detections;
  final Size imageSize;

  BoundingBoxPainter({required this.detections, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var det in detections) {
      final rect = det['bbox']; // [nx1, ny1, nx2, ny2] (normalized 0 to 1)
      if (rect == null) continue;

      final conf = det['confidence'] ?? 0.0;
      
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
        text: 'Pothole ${(conf * 100).toStringAsFixed(1)}%',
        style: const TextStyle(
          color: Colors.white,
          backgroundColor: Colors.red,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(left, top - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
