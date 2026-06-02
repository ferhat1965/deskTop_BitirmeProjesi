import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/pothole_record.dart';
import '../services/db_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<PotholeRecord> _potholes = [];
  final MapController _mapController = MapController();

  static const Map<String, String> _classTranslations = {
    'minor_pothole': 'Hafif Çukur',
    'medium_pothole': 'Orta Çukur',
    'major_pothole': 'Ağır Çukur',
    'speed_bump': 'Kasis',
  };

  static const Map<String, Color> _classColors = {
    'minor_pothole': Colors.amber,
    'medium_pothole': Colors.orange,
    'major_pothole': Colors.redAccent,
    'speed_bump': Colors.blueAccent,
  };

  static const Map<String, IconData> _classIcons = {
    'minor_pothole': Icons.warning_amber_rounded,
    'medium_pothole': Icons.warning_rounded,
    'major_pothole': Icons.report_gmailerrorred_rounded,
    'speed_bump': Icons.linear_scale_rounded,
  };

  @override
  void initState() {
    super.initState();
    _loadPotholes();
  }

  Future<void> _loadPotholes() async {
    final records = await DbService.instance.fetchAllPotholes();
    if (mounted) {
      setState(() {
        _potholes = records;
      });
      if (_potholes.isNotEmpty) {
        _mapController.move(
          LatLng(_potholes.first.latitude, _potholes.first.longitude),
          13.0,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(38.6810, 39.2264), // Elazığ
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  // Google Haritalar Uydu + İsimler (Hybrid) - Türkçe diline zorlandı
                  urlTemplate: 'https://mt1.google.com/vt/lyrs=y&hl=tr&x={x}&y={y}&z={z}',
                ),
                MarkerLayer(
                  markers: _potholes.map((pothole) {
                    final className = pothole.className;
                    final color = _classColors[className] ?? Colors.redAccent;
                    final icon = _classIcons[className] ?? Icons.warning;

                    return Marker(
                      point: LatLng(pothole.latitude, pothole.longitude),
                      width: 48,
                      height: 48,
                      child: GestureDetector(
                        onTap: () {
                          _showPotholeDetails(pothole);
                        },
                        child: Icon(
                          icon,
                          color: color,
                          size: 48,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Positioned(
            top: 24.0,
            left: 24.0,
            right: 24.0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_potholes.length} Çukur',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold, 
                            color: Colors.black87,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Icon(Icons.satellite_alt, color: Colors.blue[600], size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Uydu Haritası',
                          style: TextStyle(
                            fontWeight: FontWeight.bold, 
                            color: Colors.black87,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPotholeDetails(PotholeRecord record) {
    final className = record.className;
    final translatedName = _classTranslations[className] ?? className;
    final color = _classColors[className] ?? Colors.grey;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _classIcons[className] ?? Icons.warning,
              color: color,
            ),
            const SizedBox(width: 8),
            const Text('Kayıt Detayı'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Tür: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color, width: 1.5),
                  ),
                  child: Text(
                    translatedName,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Tarih: ${record.date} ${record.time}'),
            const SizedBox(height: 4),
            Text('Güven Skoru: % ${(record.confidence * 100).toStringAsFixed(1)}'),
            const SizedBox(height: 4),
            Text('Konum: ${record.latitude.toStringAsFixed(6)}, ${record.longitude.toStringAsFixed(6)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          )
        ],
      ),
    );
  }
}
