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
      appBar: AppBar(
        title: const Text('Tespit Haritası (Radar)'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(41.0082, 28.9784), // İstanbul merkezi
          initialZoom: 11.0,
        ),
        children: [
          TileLayer(
            // Koyu temalı (CartoDB Dark Matter)
            urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
            subdomains: const ['a', 'b', 'c', 'd'],
          ),
          MarkerLayer(
            markers: _potholes.map((pothole) {
              return Marker(
                point: LatLng(pothole.latitude, pothole.longitude),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () {
                    _showPotholeDetails(pothole);
                  },
                  child: const Icon(
                    Icons.warning_rounded,
                    color: Colors.redAccent,
                    size: 36,
                  ),
                ),
              );
            }).toList(),
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
