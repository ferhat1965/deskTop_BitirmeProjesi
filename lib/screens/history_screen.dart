import 'dart:io';
import 'package:flutter/material.dart';
import '../models/pothole_record.dart';
import '../services/db_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<PotholeRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await DbService.instance.fetchAllPotholes();
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  Future<void> _deleteRecord(int id) async {
    await DbService.instance.deletePothole(id);
    _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geçmiş Kayıtlar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const Center(child: Text('Henüz kayıt bulunmamaktadır.'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListView(
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('ID')),
                              DataColumn(label: Text('Tarih')),
                              DataColumn(label: Text('Saat')),
                              DataColumn(label: Text('Güven (%)')),
                              DataColumn(label: Text('Konum (Lat, Lng)')),
                              DataColumn(label: Text('Görsel')),
                              DataColumn(label: Text('İşlem')),
                            ],
                            rows: _records.map((record) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(record.id.toString())),
                                  DataCell(Text(record.date)),
                                  DataCell(Text(record.time)),
                                  DataCell(Text((record.confidence * 100).toStringAsFixed(1))),
                                  DataCell(Text('\${record.latitude.toStringAsFixed(4)}, \${record.longitude.toStringAsFixed(4)}')),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.image, color: Colors.blueAccent),
                                      onPressed: () {
                                        _showImageDialog(record.imagePath);
                                      },
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                                      onPressed: () => _deleteRecord(record.id!),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  void _showImageDialog(String imagePath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: imagePath.isNotEmpty && File(imagePath).existsSync()
            ? Image.file(File(imagePath))
            : const Text('Görsel bulunamadı.'),
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
