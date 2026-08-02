import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/db_service.dart';
import '../main.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _totalDetections = 0;
  bool _isDarkMode = true;
  String _userName = 'Ferhat Rammok';
  String _profileImage = '';
  double _scannedKm = 0.0;

  @override
  void initState() {
    super.initState();
    _isDarkMode = appThemeNotifier.value == ThemeMode.dark;
    _loadProfileData();
    _loadStats();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('userName') ?? 'Ferhat Rammok';
        _profileImage = prefs.getString('profileImage') ?? '';
      });
    }
  }

  Future<void> _saveProfileData(String name, String imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
    await prefs.setString('profileImage', imagePath);
  }

  Future<void> _loadStats() async {
    final records = await DbService.instance.fetchAllPotholes();

    double totalDistanceMeters = 0.0;

    if (records.length > 1) {
      for (int i = 0; i < records.length - 1; i++) {
        final current = records[i];
        final next = records[i + 1];

        if (current.latitude != 0.0 &&
            current.longitude != 0.0 &&
            next.latitude != 0.0 &&
            next.longitude != 0.0) {
          double distance = Geolocator.distanceBetween(
            current.latitude,
            current.longitude,
            next.latitude,
            next.longitude,
          );

          if (distance < 100000) {
            // Hatalı GPS atlamalarını önlemek için (100km altı)
            totalDistanceMeters += distance;
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _totalDetections = records.length;
      _scannedKm = totalDistanceMeters / 1000.0;
    });
  }

  Future<void> _resetStats() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verileri Sıfırla'),
        content: const Text(
          'Taranan KM ve tüm tespit geçmişi (veritabanı) silinecek. Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sıfırla', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DbService.instance.deleteAllPotholes();
      if (!mounted) return;
      setState(() {
        _scannedKm = 0.0;
      });
      await _loadStats();
    }
  }

  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: _userName);
    String? newImagePath = _profileImage;

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text('Profili Düzenle'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'İsim Soyisim',
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        FilePickerResult? pickResult = await FilePicker.platform
                            .pickFiles(type: FileType.image);
                        if (pickResult != null &&
                            pickResult.files.single.path != null) {
                          setStateDialog(() {
                            newImagePath = pickResult.files.single.path!;
                          });
                        }
                      },
                      icon: const Icon(Icons.image),
                      label: const Text('Bilgisayardan Resim Seç'),
                    ),
                    if (newImagePath != null &&
                        !newImagePath!.startsWith('http'))
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Seçilen: ${newImagePath!.split('\\').last}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('İptal'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Kaydet'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (result == true && mounted) {
        final finalName = nameCtrl.text.trim().isEmpty
            ? _userName
            : nameCtrl.text.trim();
        final finalImage = newImagePath ?? _profileImage;

        setState(() {
          _userName = finalName;
          _profileImage = finalImage;
        });

        await _saveProfileData(finalName, finalImage);
      }
    } finally {
      nameCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profilim',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Info Card
              Card(
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  onTap: _editProfile,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3), // Border width
                          decoration: const BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                          ),
                          child: CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.grey.shade300,
                            backgroundImage: _profileImage.isNotEmpty
                                ? (_profileImage.startsWith('http')
                                      ? NetworkImage(_profileImage)
                                            as ImageProvider
                                      : FileImage(File(_profileImage)))
                                : null,
                            child: _profileImage.isEmpty
                                ? Icon(
                                    Icons.person,
                                    size: 50,
                                    color: Colors.grey.shade600,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _userName,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: Colors.blueAccent,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Stats Row
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      context,
                      icon: Icons.my_location,
                      value: _totalDetections.toString(),
                      label: 'Tespiti',
                      iconColor: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      context,
                      icon: Icons.route,
                      value: _scannedKm == 0
                          ? "0"
                          : _scannedKm.toStringAsFixed(2),
                      label: 'KM Tarandı',
                      iconColor: Colors.blueAccent,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Theme Toggle Card
              Card(
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 20.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.dark_mode, color: Colors.blueAccent),
                          const SizedBox(width: 16),
                          Text(
                            'Karanlık Tema',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: _isDarkMode,
                        activeThumbColor: Colors.white,
                        activeTrackColor: Colors.blueAccent,
                        onChanged: (val) {
                          setState(() {
                            _isDarkMode = val;
                          });
                          appThemeNotifier.value = val
                              ? ThemeMode.dark
                              : ThemeMode.light;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Reset Button Card
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _resetStats,
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('Tespiti ve KM\'yi Sıfırla'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
  }) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Column(
          children: [
            Icon(icon, size: 36, color: iconColor),
            const SizedBox(height: 16),
            Text(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
