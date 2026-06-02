class PotholeRecord {
  final int? id;
  final String date;
  final String time;
  final double confidence;
  final double latitude;
  final double longitude;
  final String imagePath;
  final String className;

  PotholeRecord({
    this.id,
    required this.date,
    required this.time,
    required this.confidence,
    required this.latitude,
    required this.longitude,
    required this.imagePath,
    this.className = 'minor_pothole',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'time': time,
      'confidence': confidence,
      'latitude': latitude,
      'longitude': longitude,
      'imagePath': imagePath,
      'className': className,
    };
  }

  factory PotholeRecord.fromMap(Map<String, dynamic> map) {
    return PotholeRecord(
      id: map['id'],
      date: map['date'] ?? '',
      time: map['time'] ?? '',
      confidence: map['confidence'] ?? 0.0,
      latitude: map['latitude'] ?? 0.0,
      longitude: map['longitude'] ?? 0.0,
      imagePath: map['imagePath'] ?? '',
      className: map['className'] ?? 'minor_pothole',
    );
  }
}
