class WatchlistItem {
  final String id;
  final String metal; // 'gold' or 'silver'
  final double targetPrice;
  final DateTime addedAt;

  WatchlistItem(
      {required this.id,
      required this.metal,
      required this.targetPrice,
      required this.addedAt});

  Map<String, dynamic> toMap() => {
        'metal': metal,
        'targetPrice': targetPrice,
        'addedAt': addedAt.toIso8601String(),
      };

  factory WatchlistItem.fromMap(String id, Map<String, dynamic> map) =>
      WatchlistItem(
        id: id,
        metal: map['metal'] as String,
        targetPrice: (map['targetPrice'] as num).toDouble(),
        addedAt: DateTime.parse(map['addedAt'] as String),
      );
}
