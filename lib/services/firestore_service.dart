// FirestoreService for Watchlist & Portfolio
// This service uses a hardcoded test user ID for now.
// Replace `test-user-id` with actual authenticated user ID when auth is added.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/watchlist_item.dart';
import '../models/portfolio_item.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _userId = 'test-user-id'; // TODO: replace with real user ID

  // ---------- Watchlist ----------
  CollectionReference get _watchlistCol =>
      _db.collection('users').doc(_userId).collection('watchlist');

  Future<void> addWatchlistItem(WatchlistItem item) async {
    await _watchlistCol.doc(item.id).set(item.toMap());
  }

  Future<void> removeWatchlistItem(String id) async {
    await _watchlistCol.doc(id).delete();
  }

  Stream<List<WatchlistItem>> watchlistStream() {
    return _watchlistCol.snapshots().map((snapshot) => snapshot.docs
        .map((doc) =>
            WatchlistItem.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList());
  }

  // ---------- Portfolio ----------
  CollectionReference get _portfolioCol =>
      _db.collection('users').doc(_userId).collection('portfolio');

  Future<void> addPortfolioItem(PortfolioItem item) async {
    await _portfolioCol.doc(item.id).set(item.toMap());
  }

  Stream<List<PortfolioItem>> portfolioStream() {
    return _portfolioCol.snapshots().map((snapshot) => snapshot.docs
        .map((doc) =>
            PortfolioItem.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList());
  }
}
