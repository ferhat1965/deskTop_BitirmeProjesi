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
                    return Marker(
                      point: LatLng(pothole.latitude, pothole.longitude),
                      width: 48,
                      height: 48,
                      child: GestureDetector(
                        onTap: () {
                          _showPotholeDetails(pothole);
                        },
                        child: const Icon(
                          Icons.warning,
                          color: Colors.redAccent,
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çukur Detayı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tarih: \${record.date} \${record.time}'),
            Text('Güven Skoru: % \${(record.confidence * 100).toStringAsFixed(1)}'),
            Text('Konum: \${record.latitude.toStringAsFixed(4)}, \${record.longitude.toStringAsFixed(4)}'),
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
