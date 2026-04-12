// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

class PageSelectionScreen extends StatefulWidget {
  final File pdfFile;
  final String fileHash;
  final bool isReturningResult;

  const PageSelectionScreen({
    super.key,
    required this.pdfFile,
    required this.fileHash,
    this.isReturningResult = true,
  });

  @override
  State<PageSelectionScreen> createState() => _PageSelectionScreenState();
}

class _PageSelectionScreenState extends State<PageSelectionScreen> {
  final Set<int> _selectedPages = {};
  List<int> _allPages = [];

  PdfDocument? _document;
  bool _isLoading = true;
  int _totalPageCount = 0;

  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    childAspectRatio: 0.7,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
  );

  @override
  void initState() {
    super.initState();
    _initializePdf();
  }

  Future<void> _initializePdf() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    try {
      if (!widget.pdfFile.existsSync()) {
        throw "File tidak ditemukan di path: ${widget.pdfFile.path}";
      }

      Pdfrx.getCacheDirectory = () async {
        final dir = await getTemporaryDirectory();
        return dir.path;
      };

      final doc = await PdfDocument.openFile(widget.pdfFile.path);

      if (mounted) {
        setState(() {
          _document       = doc;
          _totalPageCount = doc.pages.length;
          _allPages       = List<int>.generate(_totalPageCount, (i) => i);
          _selectedPages.addAll(_allPages);
          _isLoading      = false;
        });
      }
    } catch (e) {
      debugPrint("Gagal memuat PDF: $e");
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Gagal Memuat PDF"),
            content: Text("Terjadi kesalahan saat membuka file: $e"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.pop(context);
                },
                child: const Text("Kembali"),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _document?.dispose();
    super.dispose();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedPages.length == _totalPageCount) {
        _selectedPages.clear();
      } else {
        _selectedPages.clear();
        _selectedPages.addAll(_allPages);
      }
    });
  }

  void _onPageTap(int index) {
    setState(() {
      if (_selectedPages.contains(index)) {
        _selectedPages.remove(index);
      } else {
        _selectedPages.add(index);
      }
    });
  }

  void _onPageLongPress(int index) {
    _showZoomedPage(index + 1);
  }

  void _showZoomedPage(int pageNumber) {
    if (_document == null) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            SizedBox(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Center(
                      child: RepaintBoundary(
                        child: PdfPageView(
                          document: _document!,
                          pageNumber: pageNumber,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: CloseButton(color: Colors.white),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Text(
                      "Halaman $pageNumber",
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleProcess() {
    final List<int> sortedIndices = _selectedPages.toList()..sort();
    Navigator.pop(context, sortedIndices);
  }

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Pilih Halaman",
          style: GoogleFonts.comicNeue(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _toggleSelectAll,
            child: Text(
              _selectedPages.length == _totalPageCount
                  ? "Batal Semua"
                  : "Pilih Semua",
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.orange[800]),
            ),
          )
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.orange),
                  const SizedBox(height: 16),
                  Text("Membuka PDF...",
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            )
          : Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: Colors.orange.shade50),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                  fontSize: 12, color: Colors.orange[900]),
                              children: const [
                                TextSpan(text: "Ketuk untuk memilih. "),
                                TextSpan(
                                  text: "Tahan untuk memperbesar.",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    key: const PageStorageKey('pdf_page_selection_grid'),
                    padding: const EdgeInsets.all(12),
                    gridDelegate: _gridDelegate,
                    itemCount: _totalPageCount,
                    addAutomaticKeepAlives: false,
                    cacheExtent: 200,
                    itemBuilder: (context, index) {
                      final isSelected = _selectedPages.contains(index);
                      return _PageGridItem(
                        key: ValueKey(index),
                        document: _document!,
                        index: index,
                        isSelected: isSelected,
                        onTap: _onPageTap,
                        onLongPress: _onPageLongPress,
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, -5))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SafeArea(
            child: ElevatedButton(
              onPressed:
                  _selectedPages.isEmpty || _isLoading ? null : _handleProcess,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: Text(
                _selectedPages.isEmpty
                    ? "Pilih minimal 1 halaman"
                    : "Proses ${_selectedPages.length} Halaman",
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageGridItem extends StatelessWidget {
  final PdfDocument document;
  final int index;
  final bool isSelected;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onLongPress;

  // FIX: BoxShadow dengan withOpacity dipindahkan ke static final
  // sebelumnya dibuat ulang setiap build() saat isSelected = true
  static final BoxDecoration _selectedDecoration = BoxDecoration(
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.green, width: 3),
    boxShadow: [
      BoxShadow(
          color: Colors.green.withOpacity(0.3),
          blurRadius: 8,
          spreadRadius: 1)
    ],
  );

  static final BoxDecoration _unselectedDecoration = BoxDecoration(
    color: Colors.white.withOpacity(0.5),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.grey.shade300),
  );

  const _PageGridItem({
    super.key,
    required this.document,
    required this.index,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(index),
      onLongPress: () => onLongPress(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AbsorbPointer(
                  child: PdfPageView(
                    document: document,
                    pageNumber: index + 1,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),

          // FIX: gunakan static final decoration — tidak alokasikan BoxShadow baru tiap rebuild
          DecoratedBox(
            decoration:
                isSelected ? _selectedDecoration : _unselectedDecoration,
          ),

          Positioned(
            bottom: 4,
            left: 0,
            right: 0,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    "${index + 1}",
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            top: 4,
            right: 4,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? Colors.green : Colors.grey,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}