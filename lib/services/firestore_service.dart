// FirestoreService for Watchlist & Portfolio
// Data is scoped per signed-in user: users/<uid>/watchlist and
// users/<uid>/portfolio. The uid comes from Firebase Auth via the
// dashboard's auth gate; there is no shared fallback user anymore.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/watchlist_item.dart';
import '../models/portfolio_item.dart';

class FirestoreService {
  /// Signed-in user's UID. When null (signed out / tests), the streams emit
  /// empty lists and writes throw; the UI gates writes behind sign-in.
  final String? uid;

  FirestoreService({this.uid});

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ---------- Watchlist ----------
  CollectionReference get _watchlistCol =>
      _db.collection('users').doc(uid).collection('watchlist');

  Future<void> addWatchlistItem(WatchlistItem item) async {
    _requireUid();
    await _watchlistCol.doc(item.id).set(item.toMap());
  }

  Future<void> removeWatchlistItem(String id) async {
    _requireUid();
    await _watchlistCol.doc(id).delete();
  }

  Stream<List<WatchlistItem>> watchlistStream() {
    if (uid == null) return Stream.value(const []);
    return _watchlistCol.snapshots().map((snapshot) => snapshot.docs
        .map((doc) =>
            WatchlistItem.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList());
  }

  // ---------- Portfolio ----------
  CollectionReference get _portfolioCol =>
      _db.collection('users').doc(uid).collection('portfolio');

  Future<void> addPortfolioItem(PortfolioItem item) async {
    _requireUid();
    await _portfolioCol.doc(item.id).set(item.toMap());
  }

  Future<void> removePortfolioItem(String id) async {
    _requireUid();
    await _portfolioCol.doc(id).delete();
  }

  Stream<List<PortfolioItem>> portfolioStream() {
    if (uid == null) return Stream.value(const []);
    return _portfolioCol.snapshots().map((snapshot) => snapshot.docs
        .map((doc) =>
            PortfolioItem.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList());
  }

  void _requireUid() {
    if (uid == null) {
      throw StateError('Sign in to save watchlist and portfolio items.');
    }
  }
}
