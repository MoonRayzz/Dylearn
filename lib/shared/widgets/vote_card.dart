// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/services/vote_service.dart';
import '../../core/utils/responsive_helper.dart';

class VoteCard extends StatefulWidget {
  final DocumentSnapshot doc;

  const VoteCard({super.key, required this.doc});

  @override
  State<VoteCard> createState() => _VoteCardState();
}

class _VoteCardState extends State<VoteCard> {
  final VoteService _voteService = VoteService();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  FlutterTts? _flutterTts;

  final ValueNotifier<bool> _isVotingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier(false);

  late Map<String, dynamic> _data;
  late String _cleanContent;
  late String _snippetContent;
  late List<String> _previewSentences;
  late bool _isUploader;
  late bool _hasVoted;
  late int _voteCount;
  late int _approveCount;
  late int _requiredVotes;

  bool _isInitialized = false;

  static final RegExp _pageBreakRegex = RegExp(r'<PAGE_BREAK>');
  static final RegExp _slashCommandRegex = RegExp(r'\\[a-zA-Z]+');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _sentenceSplitRegex = RegExp(r'(?<=[.!?])\s+');

  @override
  void initState() {
    super.initState();
    _processData();
    _isInitialized = true;
  }

  @override
  void didUpdateWidget(VoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // FIX: bandingkan referensi objek DocumentSnapshot, bukan Map hasil data()
    // data() selalu menghasilkan Map baru sehingga != selalu true (false positive)
    if (widget.doc != oldWidget.doc) {
      _flutterTts?.stop();
      if (mounted) _isPlayingNotifier.value = false;
      _processData();
    }
  }

  void _processData() {
    _data = widget.doc.data() as Map<String, dynamic>;
    final String rawContent = _data['content'] ?? '';
    final String uploadBy = _data['uploadBy'] ?? '';
    final List<dynamic> voters = _data['voters'] ?? [];

    _isUploader = _currentUser != null && uploadBy == _currentUser.uid;
    _hasVoted = _currentUser != null && voters.contains(_currentUser.uid);

    _voteCount = _data['voteCount'] ?? 0;
    _approveCount = _data['approveCount'] ?? 0;
    _requiredVotes = _data['requiredVotes'] ?? 3;

    _cleanContent = _cleanTextLogic(rawContent);
    _previewSentences =
        _cleanContent.split(_sentenceSplitRegex).take(2).toList();

    final List<String> words = _cleanContent.split(_whitespaceRegex);
    _snippetContent = words.length > 50
        ? "${words.take(50).join(' ')}..."
        : _cleanContent;

    if (_isInitialized && mounted) setState(() {});
  }

  Future<void> _initAndPlayTts() async {
    if (_flutterTts == null) {
      _flutterTts = FlutterTts();
      await _flutterTts!.setLanguage("id-ID");
      await _flutterTts!.setSpeechRate(0.5);
      await _flutterTts!.awaitSpeakCompletion(true);

      _flutterTts!.setCompletionHandler(() {
        if (mounted) _isPlayingNotifier.value = false;
      });

      _flutterTts!.setErrorHandler((msg) {
        if (mounted) _isPlayingNotifier.value = false;
      });
    }

    if (_snippetContent.isEmpty) return;

    if (mounted) _isPlayingNotifier.value = true;
    await _flutterTts!.speak("Berikut cuplikan ceritanya. $_snippetContent");
  }

  @override
  void dispose() {
    // FIX: null-kan referensi agar GC bisa reclaim native TTS engine resources
    _flutterTts?.stop();
    _flutterTts = null;
    _isVotingNotifier.dispose();
    _isPlayingNotifier.dispose();
    super.dispose();
  }

  String _cleanTextLogic(String rawText) {
    return rawText
        .replaceAll(_pageBreakRegex, ' ')
        .replaceAll(_slashCommandRegex, '')
        .replaceAll(_whitespaceRegex, ' ')
        .trim();
  }

  Future<void> _toggleAudioSnippet() async {
    if (_isPlayingNotifier.value) {
      if (_flutterTts != null) await _flutterTts!.stop();
      if (mounted) _isPlayingNotifier.value = false;
    } else {
      await _initAndPlayTts();
    }
  }

  Future<void> _handleVote(bool isLike) async {
    if (_currentUser == null) return;

    if (_flutterTts != null) await _flutterTts!.stop();

    _isVotingNotifier.value = true;
    _isPlayingNotifier.value = false;

    try {
      await _voteService.submitVote(
          bookId: widget.doc.id,
          userId: _currentUser.uid,
          isLike: isLike);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isLike ? "Hore! Suara masuk! 👍" : "Oke, terima kasih infonya! 👌",
              style: GoogleFonts.comicNeue(fontWeight: FontWeight.bold),
            ),
            backgroundColor: isLike ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Gagal: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) _isVotingNotifier.value = false;
    }
  }

  void _showFullTextDialog(String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFFFFBE6),
        title: Text(title,
            style: GoogleFonts.comicNeue(
                fontWeight: FontWeight.bold, color: Colors.brown)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Text(
              _snippetContent,
              style: TextStyle(
                  fontFamily:
                      Theme.of(context).textTheme.bodyMedium?.fontFamily,
                  height: 1.6,
                  fontSize: context.r.font(16)),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Tutup Buku",
                  style: GoogleFonts.comicNeue(
                      fontWeight: FontWeight.bold,
                      fontSize: context.r.font(16)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) return const SizedBox.shrink();

    final String title = _data['title'] ?? 'Tanpa Judul';
    final String author = _data['author'] ?? 'Anonim';
    final String coverUrl = _data['coverUrl'] ?? '';
    final String category = _data['category'] ?? 'Umum';

    return Container(
      margin: EdgeInsets.only(
        bottom: context.r.spacing(20),
        left: context.r.spacing(16),
        right: context.r.spacing(16),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
              color: Colors.blue.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
        border: _isUploader
            ? Border.all(color: Colors.blue.shade200, width: 2)
            : _hasVoted
                ? Border.all(color: Colors.green.shade200, width: 2)
                : null,
      ),
      child: Column(
        children: [
          _BookHeaderWidget(
            title: title,
            author: author,
            category: category,
            coverUrl: coverUrl,
            isUploader: _isUploader,
            hasVoted: _hasVoted,
            isPlayingNotifier: _isPlayingNotifier,
            onToggleAudio: _toggleAudioSnippet,
          ),
          _PreviewSectionWidget(
            title: title,
            previewSentences: _previewSentences,
            onReadFullText: () => _showFullTextDialog(title),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _isVotingNotifier,
            builder: (context, isVoting, child) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: isVoting
                    ? Container(
                        key: const ValueKey('loading'),
                        padding: EdgeInsets.all(context.r.spacing(30)),
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(
                            color: Colors.orange))
                    : _isUploader
                        ? _UploaderStatusWidget(
                            key: const ValueKey('uploader'),
                            current: _voteCount,
                            likes: _approveCount,
                            target: _requiredVotes,
                          )
                        : _hasVoted
                            ? _VotedResultsWidget(
                                key: const ValueKey('voted'),
                                current: _voteCount,
                                likes: _approveCount,
                              )
                            : _BlindVoteUIWidget(
                                key: const ValueKey('blindVote'),
                                onVote: _handleVote,
                              ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BookHeaderWidget extends StatelessWidget {
  final String title;
  final String author;
  final String category;
  final String coverUrl;
  final bool isUploader;
  final bool hasVoted;
  final ValueNotifier<bool> isPlayingNotifier;
  final VoidCallback onToggleAudio;

  const _BookHeaderWidget({
    required this.title,
    required this.author,
    required this.category,
    required this.coverUrl,
    required this.isUploader,
    required this.hasVoted,
    required this.isPlayingNotifier,
    required this.onToggleAudio,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.r.spacing(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: CachedNetworkImage(
              imageUrl: coverUrl,
              width: context.r.size(85),
              height: context.r.size(115),
              fit: BoxFit.cover,
              memCacheWidth: 200,
              memCacheHeight: 300,
              placeholder: (context, url) =>
                  Container(color: Colors.grey[200]),
              errorWidget: (c, u, e) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.book)),
            ),
          ),
          SizedBox(width: context.r.spacing(16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _BadgeWidget(label: category, color: Colors.blue),
                    if (isUploader)
                      const _BadgeWidget(
                          label: "Buku Saya", color: Colors.purple),
                    if (hasVoted && !isUploader)
                      const _BadgeWidget(
                          label: "Sudah Dinilai", color: Colors.green),
                  ],
                ),
                SizedBox(height: context.r.spacing(8)),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily:
                        Theme.of(context).textTheme.bodyMedium?.fontFamily,
                    fontSize: context.r.font(16),
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                  maxLines: 2,
                ),
                Text(
                  "Oleh: $author",
                  style: GoogleFonts.comicNeue(
                    fontSize: context.r.font(14),
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: context.r.spacing(12)),
                ValueListenableBuilder<bool>(
                  valueListenable: isPlayingNotifier,
                  builder: (context, isPlaying, child) {
                    return InkWell(
                      onTap: onToggleAudio,
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: EdgeInsets.symmetric(
                          horizontal: context.r.spacing(12),
                          vertical: context.r.spacing(8),
                        ),
                        decoration: BoxDecoration(
                          color: isPlaying
                              ? Colors.red.shade50
                              : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: isPlaying
                                  ? Colors.red.shade200
                                  : Colors.orange.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPlaying
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                              size: context.r.size(20),
                              color: isPlaying ? Colors.red : Colors.orange,
                            ),
                            SizedBox(width: context.r.spacing(6)),
                            Flexible(
                              child: Text(
                                isPlaying ? "Stop Cerita" : "Dengar Cerita",
                                style: TextStyle(
                                  fontSize: context.r.font(12),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.fontFamily,
                                  color: isPlaying
                                      ? Colors.red
                                      : Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _BadgeWidget extends StatelessWidget {
  final String label;
  final Color color;

  const _BadgeWidget({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.r.spacing(10),
        vertical: context.r.spacing(4),
      ),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12)),
      child: Text(
        label,
        style: TextStyle(
          fontSize: context.r.font(10),
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PreviewSectionWidget extends StatelessWidget {
  final String title;
  final List<String> previewSentences;
  final VoidCallback onReadFullText;

  const _PreviewSectionWidget({
    required this.title,
    required this.previewSentences,
    required this.onReadFullText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: context.r.spacing(16)),
      padding: EdgeInsets.all(context.r.spacing(16)),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Intip isi cerita:",
            style: GoogleFonts.comicNeue(
              fontSize: context.r.font(14),
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
          SizedBox(height: context.r.spacing(10)),
          ...previewSentences.map((sentence) {
            return Padding(
              padding: EdgeInsets.only(bottom: context.r.spacing(8)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("✨ ",
                      style: TextStyle(fontSize: context.r.font(12))),
                  Expanded(
                    child: Text(
                      sentence,
                      style: TextStyle(
                        fontFamily: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.fontFamily,
                        fontSize: context.r.font(13),
                        height: 1.5,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReadFullText,
              icon: Icon(Icons.menu_book_rounded,
                  size: context.r.size(16)),
              label: Text(
                "Baca Cuplikan",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: context.r.font(12),
                ),
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploaderStatusWidget extends StatelessWidget {
  final int current;
  final int likes;
  final int target;

  const _UploaderStatusWidget({
    super.key,
    required this.current,
    required this.likes,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final int dislikes = current - likes;
    final double progress =
        (target > 0) ? (current / target).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: EdgeInsets.all(context.r.spacing(20)),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: context.r.size(20), color: Colors.blue),
              SizedBox(width: context.r.spacing(8)),
              Text(
                "Status Buku Kamu",
                style: GoogleFonts.comicNeue(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                  fontSize: context.r.font(16),
                ),
              ),
            ],
          ),
          SizedBox(height: context.r.spacing(15)),
          Stack(
            children: [
              Container(
                height: 12,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6)),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(6)),
                ),
              )
            ],
          ),
          SizedBox(height: context.r.spacing(8)),
          Text(
            current >= target
                ? "Sedang dinilai guru..."
                : "Butuh ${target - current} suara lagi",
            style: GoogleFonts.comicNeue(
              fontSize: context.r.font(12),
              color: Colors.blueGrey,
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: context.r.spacing(20)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatBoxWidget(
                  icon: Icons.favorite_rounded,
                  value: likes,
                  color: Colors.pink,
                  label: "Disukai"),
              _StatBoxWidget(
                  icon: Icons.thumb_down_rounded,
                  value: dislikes,
                  color: Colors.orange,
                  label: "Kurang"),
              _StatBoxWidget(
                  icon: Icons.group_rounded,
                  value: current,
                  color: Colors.blue,
                  label: "Total"),
            ],
          ),
        ],
      ),
    );
  }
}

class _VotedResultsWidget extends StatelessWidget {
  final int current;
  final int likes;

  const _VotedResultsWidget({
    super.key,
    required this.current,
    required this.likes,
  });

  @override
  Widget build(BuildContext context) {
    final int dislikes = current - likes;
    final double likePct = (current == 0) ? 0.5 : (likes / current);

    final int likeFlex = (likePct * 100).toInt().clamp(1, 99);
    final int dislikeFlex = (100 - likeFlex).clamp(1, 99);

    return Container(
      padding: EdgeInsets.all(context.r.spacing(20)),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(25)),
      ),
      child: Column(
        children: [
          Text(
            "🎉 Terima Kasih Juri Cilik! 🎉",
            style: GoogleFonts.comicNeue(
              fontWeight: FontWeight.bold,
              color: Colors.green[800],
              fontSize: context.r.font(16),
            ),
          ),
          SizedBox(height: context.r.spacing(4)),
          Text(
            "Ini hasil sementara pilihan teman-temanmu:",
            style: GoogleFonts.comicNeue(
              fontSize: context.r.font(12),
              color: Colors.green[700],
            ),
          ),
          SizedBox(height: context.r.spacing(15)),
          Row(
            children: [
              Expanded(
                flex: likeFlex,
                child: Container(
                  height: 30,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 8),
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(15)),
                  ),
                  child: const Icon(Icons.thumb_up_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
              Expanded(
                flex: dislikeFlex,
                child: Container(
                  height: 30,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(15)),
                  ),
                  child: const Icon(Icons.thumb_down_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
          SizedBox(height: context.r.spacing(15)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatBoxWidget(
                  icon: Icons.thumb_up_alt_rounded,
                  value: likes,
                  color: Colors.green,
                  label: "Teman Suka"),
              _StatBoxWidget(
                  icon: Icons.thumb_down_alt_rounded,
                  value: dislikes,
                  color: Colors.orange,
                  label: "Teman Kurang Suka"),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBoxWidget extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;
  final String label;

  const _StatBoxWidget({
    required this.icon,
    required this.value,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(context.r.spacing(10)),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: context.r.size(24)),
        ),
        SizedBox(height: context.r.spacing(4)),
        Text(
          value.toString(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: context.r.font(18),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.comicNeue(
            fontSize: context.r.font(11),
            color: Colors.grey[700],
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _BlindVoteUIWidget extends StatelessWidget {
  final Function(bool isLike) onVote;

  const _BlindVoteUIWidget({super.key, required this.onVote});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: context.r.spacing(10)),
      child: Row(
        children: [
          _VoteButtonWidget(
            isLike: false,
            label: "🤔 Kurang Pas",
            bg: Colors.grey.shade100,
            textCol: Colors.grey.shade700,
            radius: const BorderRadius.only(
                bottomLeft: Radius.circular(25)),
            onVote: onVote,
          ),
          _VoteButtonWidget(
            isLike: true,
            label: "😍 Suka Banget!",
            bg: Colors.orange.shade100,
            textCol: Colors.orange.shade900,
            radius: const BorderRadius.only(
                bottomRight: Radius.circular(25)),
            onVote: onVote,
          ),
        ],
      ),
    );
  }
}

class _VoteButtonWidget extends StatelessWidget {
  final bool isLike;
  final String label;
  final Color bg;
  final Color textCol;
  final BorderRadius radius;
  final Function(bool isLike) onVote;

  const _VoteButtonWidget({
    required this.isLike,
    required this.label,
    required this.bg,
    required this.textCol,
    required this.radius,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: bg,
        borderRadius: radius,
        child: InkWell(
          onTap: () => onVote(isLike),
          borderRadius: radius,
          splashColor: isLike
              ? Colors.orange.withOpacity(0.3)
              : Colors.grey.withOpacity(0.3),
          child: Container(
            padding: EdgeInsets.symmetric(
                vertical: context.r.spacing(22)),
            decoration: BoxDecoration(
              border: Border.all(
                  color: Colors.black.withOpacity(0.05)),
            ),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.comicNeue(
                  fontWeight: FontWeight.bold,
                  fontSize: context.r.font(16),
                  color: textCol,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}