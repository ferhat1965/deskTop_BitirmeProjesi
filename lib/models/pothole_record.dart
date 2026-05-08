class PotholeRecord {
  final int? id;
  final String date;
  final String time;
  final double confidence;
  final double latitude;
  final double longitude;
  final String imagePath;

  PotholeRecord({
    this.id,
    required this.date,
    required this.time,
    required this.confidence,
    required this.latitude,
    required this.longitude,
    required this.imagePath,
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
    };
  }

  factory PotholeRecord.fromMap(Map<String, dynamic> map) {
    return PotholeRecord(
      id: map['id'],
      date: map['date'],
      time: map['time'],
      confidence: map['confidence'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      imagePath: map['imagePath'],
    );
  }
}
