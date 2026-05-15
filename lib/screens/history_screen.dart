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
  Set<int> _selectedIds = {};

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
    // Silme onayı iste
    final confirm = await _showDeleteConfirmation(1);
    if (confirm != true) return;

    await DbService.instance.deletePothole(id);
    _selectedIds.remove(id);
    _loadRecords();
  }

  Future<void> _deleteSelectedRecords() async {
    if (_selectedIds.isEmpty) return;

    final confirm = await _showDeleteConfirmation(_selectedIds.length);
    if (confirm != true) return;

    await DbService.instance.deletePotholes(_selectedIds.toList());
    setState(() {
      _selectedIds.clear();
    });
    _loadRecords();
  }

  Future<bool?> _showDeleteConfirmation(int count) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kayıtları Sil'),
        content: Text('$count adet kaydı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  void _onSelectAll(bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedIds = _records.map((r) => r.id!).toSet();
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _onSelectRow(int id, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geçmiş Kayıtlar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: ActionChip(
                backgroundColor: Colors.redAccent.withOpacity(0.2),
                side: const BorderSide(color: Colors.redAccent),
                avatar: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 20),
                label: Text(
                  'Seçilenleri Sil (${_selectedIds.length})',
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
                onPressed: _deleteSelectedRecords,
              ),
            ),
        ],
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
                            onSelectAll: _onSelectAll,
                            showCheckboxColumn: true,
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
                                selected: _selectedIds.contains(record.id),
                                onSelectChanged: (selected) => _onSelectRow(record.id!, selected),
                                cells: [
                                  DataCell(Text(record.id.toString())),
                                  DataCell(Text(record.date)),
                                  DataCell(Text(record.time)),
                                  DataCell(Text((record.confidence * 100).toStringAsFixed(1))),
                                  DataCell(Text('${record.latitude.toStringAsFixed(4)}, ${record.longitude.toStringAsFixed(4)}')),
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
