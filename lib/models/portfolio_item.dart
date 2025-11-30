class PortfolioItem {
  final String id;
  final String metal; // 'gold' or 'silver'
  final double amount; // quantity owned
  final double avgPrice; // average purchase price per unit
  final DateTime addedAt;

  PortfolioItem({
    required this.id,
    required this.metal,
    required this.amount,
    required this.avgPrice,
    required this.addedAt,
  });

  Map<String, dynamic> toMap() => {
        'metal': metal,
        'amount': amount,
        'avgPrice': avgPrice,
        'addedAt': addedAt.toIso8601String(),
      };

  factory PortfolioItem.fromMap(String id, Map<String, dynamic> map) =>
      PortfolioItem(
        id: id,
        metal: map['metal'] as String,
        amount: (map['amount'] as num).toDouble(),
        avgPrice: (map['avgPrice'] as num).toDouble(),
        addedAt: DateTime.parse(map['addedAt'] as String),
      );
}
