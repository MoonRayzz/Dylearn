import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class VoteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===========================================================================
  // 1. STREAM BUKU PENDING UNTUK JURI CILIK
  // ===========================================================================
  Stream<List<DocumentSnapshot>> getBooksToVoteStream(String currentUserId) {
    return _firestore
        .collection('library_books')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  // Stream hitungan untuk badge notifikasi di header library
  Stream<int> getPendingVotesCountStream(String currentUserId) {
    return _firestore
        .collection('library_books')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.where((doc) {
        final data   = doc.data();
        final String uploadBy      = data['uploadBy'] ?? '';
        final List<dynamic> voters = data['voters']   ?? [];
        // Hitung buku yang belum divote oleh user ini
        // dan bukan milik user sendiri
        return uploadBy != currentUserId &&
               !voters.contains(currentUserId);
      }).length;
    });
  }

  // ===========================================================================
  // 2. TRANSAKSI VOTING (LOGIKA UTAMA)
  // ===========================================================================
  Future<void> submitVote({
    required String bookId,
    required String userId,
    required bool isLike,
  }) async {
    final docRef = _firestore.collection('library_books').doc(bookId);

    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        throw Exception("Buku tidak ditemukan!");
      }

      final Map<String, dynamic> data =
          snapshot.data() as Map<String, dynamic>;

      final List<dynamic> voters     = List.from(data['voters']       ?? []);
      final int currentVoteCount     = data['voteCount']              ?? 0;
      final int currentApproveCount  = data['approveCount']           ?? 0;
      final int requiredVotes        = data['requiredVotes']          ?? 3;
      final String currentStatus     = data['status']                 ?? 'pending';
      final String uploadBy          = data['uploadBy']               ?? '';

      if (currentStatus != 'pending') {
        throw Exception("Voting untuk buku ini sudah ditutup.");
      }
      if (uploadBy == userId) {
        throw Exception("Kamu tidak bisa memvoting bukumu sendiri.");
      }
      if (voters.contains(userId)) {
        throw Exception("Kamu sudah memvoting buku ini.");
      }

      voters.add(userId);
      final int newVoteCount    = currentVoteCount + 1;
      final int newApproveCount = isLike
          ? (currentApproveCount + 1)
          : currentApproveCount;

      transaction.update(docRef, {
        'voteCount':    newVoteCount,
        'approveCount': newApproveCount,
        'voters':       voters,
      });

      if (newVoteCount >= requiredVotes) {
        _decideBookFate(
            transaction, docRef, newVoteCount, newApproveCount);
      }
    });
  }

  // ===========================================================================
  // 3. PENENTU NASIB BUKU (LIVE / REJECTED)
  // ===========================================================================
  void _decideBookFate(
    Transaction transaction,
    DocumentReference docRef,
    int totalVotes,
    int totalLikes,
  ) {
    if (totalVotes == 0) return;

    final double approvalRatio = totalLikes / totalVotes;
    final bool isPassed        = approvalRatio >= 0.6;

    if (isPassed) {
      transaction.update(docRef, {
        'status':      'live',
        'publishedAt': FieldValue.serverTimestamp(),
      });
      debugPrint("KEPUTUSAN: Buku LOLOS ke Library (Live) ✅");
    } else {
      transaction.update(docRef, {
        'status':     'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
      });
      debugPrint("KEPUTUSAN: Buku DITOLAK ❌");
    }
  }
}