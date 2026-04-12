// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unnecessary_null_comparison

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ocr_processing_screen.dart';
import '../../shared/widgets/system_popup.dart';
import '../../shared/widgets/background_wrapper.dart';
import '../../core/utils/responsive_helper.dart';

class CameraPickerScreen extends StatefulWidget {
  // PARAMETER BARU UNTUK SESI GURU
  final String? activeStudentUid;
  final String? activeStudentName;

  const CameraPickerScreen({
    super.key,
    this.activeStudentUid,
    this.activeStudentName,
  });

  @override
  State<CameraPickerScreen> createState() =>
      _CameraPickerScreenState();
}

class _CameraPickerScreenState
    extends State<CameraPickerScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<File> _selectedImages = [];

  // OPTIMIZATION: Cache static const delegate — tidak berubah
  static const SliverGridDelegateWithFixedCrossAxisCount
      _gridDelegate =
      SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    childAspectRatio: 0.75,
  );

  // OPTIMIZATION: Cache EdgeInsets konstan → static const
  static const EdgeInsets _areaPadding =
      EdgeInsets.all(20.0);
  static const EdgeInsets _gridPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 10);

  // OPTIMIZATION: Cache BorderRadius konstan → static const
  static const BorderRadius _buttonRadius =
      BorderRadius.all(Radius.circular(16));

  // BUG FIX #5: Gunakan .shade800 non-nullable
  // Colors.blue[800] mengembalikan Color? → force-unwrap berbahaya
  static final Color _blueColor = Colors.blue.shade800;

  // OPTIMIZATION: Cache GoogleFonts base → static final
  // Eliminasi font lookup setiap build()
  static final TextStyle _comicNueBoldBase =
      GoogleFonts.comicNeue(fontWeight: FontWeight.bold);

  // OPTIMIZATION: Cache proses button style → static final
  // ElevatedButton.styleFrom() dipanggil setiap build()
  // setiap kali image ditambah/dihapus (setState)
  static final ButtonStyle _processButtonStyle =
      ElevatedButton.styleFrom(
    backgroundColor: Colors.blue.shade600,
    foregroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: _buttonRadius,
    ),
    elevation: 4,
  );

  Future<void> _scanWithSmartCamera() async {
    final DocumentScannerOptions options =
        DocumentScannerOptions(
      mode: ScannerMode.full,
      pageLimit: 10,
    );

    final DocumentScanner documentScanner =
        DocumentScanner(options: options);

    // BUG FIX #1: Pindah close() ke finally block
    // Sebelumnya hanya di happy path → resource leak jika exception
    try {
      final DocumentScanningResult result =
          await documentScanner.scanDocument();

      // BUG FIX #2: Hapus redundant `result != null` check
      // DocumentScanningResult adalah non-nullable return type
      // Gunakan ?. operator alih-alih ! force-unwrap
      final List<String>? images = result.images;
      if (images != null && images.isNotEmpty) {
        setState(() {
          _selectedImages
              .addAll(images.map((path) => File(path)));
        });
      }
    } catch (e) {
      debugPrint("Scanner Error: $e");
      if (mounted) {
        showSystemPopup(
          context: context,
          type: PopupType.error,
          title: "Scanner Gagal",
          message:
              "Terjadi kesalahan saat membuka scanner cerdas.",
        );
      }
    } finally {
      // BUG FIX #1: Guaranteed close — baik sukses maupun error
      try {
        await documentScanner.close();
      } catch (_) {
        // Abaikan error saat close — tidak kritikal
      }
    }
  }

  Future<File?> _cropImage(File imageFile) async {
    final Color primaryColor = Theme.of(context).primaryColor;

    try {
      final CroppedFile? croppedFile =
          await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        compressQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Potong Gambar',
            toolbarColor: primaryColor,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(title: 'Potong Gambar'),
        ],
      );
      return croppedFile != null
          ? File(croppedFile.path)
          : null;
    } catch (e) {
      debugPrint("Crop Error: $e");
      return null;
    }
  }

  Future<void> _pickGallery() async {
    try {
      final XFile? image =
          await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final File? cropped =
            await _cropImage(File(image.path));
        if (cropped != null) {
          setState(() => _selectedImages.add(cropped));
        }
      }
    } catch (e) {
      debugPrint("Gallery Error: $e");
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  void _processImages() {
    if (_selectedImages.isEmpty) {
      showSystemPopup(
        context: context,
        type: PopupType.warning,
        title: "Belum Ada Foto",
        message:
            "Ayo pilih atau foto ceritanya dulu sebelum dilanjutkan!",
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (c) => OcrProcessingScreen(
          imageFiles: _selectedImages,
          sourceType: 'camera',
          // TERUSKAN PARAMETER GURU KE OCR SCREEN
          activeStudentUid: widget.activeStudentUid,
          activeStudentName: widget.activeStudentName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // RESPONSIVENESS: Ambil helper sekali per build
    final r = context.r;
    final isTeacherMode = widget.activeStudentName != null;
    final shortName = isTeacherMode ? widget.activeStudentName!.split(' ').first : '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          isTeacherMode ? "Foto Cerita untuk $shortName" : "Foto Cerita",
          // OPTIMIZATION + RESPONSIVENESS: Base style cached,
          // fontSize responsive via copyWith
          style: _comicNueBoldBase.copyWith(
            color: _blueColor,
            fontSize: r.font(isTeacherMode ? 16 : 18),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: _blueColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: BackgroundWrapper(
        showBottomBlob: false,
        child: Column(
          children: [
            // --- AREA TOMBOL INPUT GAMBAR ---
            Padding(
              // RESPONSIVENESS: Responsive padding
              padding: EdgeInsets.all(r.spacing(20)),
              child: Row(
                children: [
                  Expanded(
                    child: _PickerButton(
                      icon: Icons.document_scanner_rounded,
                      label: "Scan Cerdas",
                      color: Colors.orange,
                      textColor: Colors.white,
                      onTap: _scanWithSmartCamera,
                      r: r,
                    ),
                  ),
                  SizedBox(width: r.spacing(12)),
                  Expanded(
                    child: _PickerButton(
                      icon: Icons.photo_library_rounded,
                      label: "Galeri Biasa",
                      color: Colors.white,
                      // BUG FIX #5: shade800 non-nullable
                      textColor: _blueColor,
                      onTap: _pickGallery,
                      r: r,
                    ),
                  ),
                ],
              ),
            ),

            // --- AREA PREVIEW GAMBAR ---
            Expanded(
              child: _selectedImages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.document_scanner_outlined,
                            // RESPONSIVENESS: Responsive size
                            size: r.size(80),
                            color: Colors.grey.shade300,
                          ),
                          SizedBox(height: r.spacing(16)),
                          Text(
                            "Belum ada foto.\nTekan 'Scan Cerdas' untuk memfoto buku\ndengan fitur auto-lurus.",
                            textAlign: TextAlign.center,
                            // OPTIMIZATION + RESPONSIVENESS
                            style: _comicNueBoldBase.copyWith(
                              color: Colors.grey,
                              fontSize: r.font(16),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      // OPTIMIZATION: Cached static const padding
                      padding: _gridPadding,
                      physics: const BouncingScrollPhysics(),
                      // OPTIMIZATION: Cached static const delegate
                      gridDelegate: _gridDelegate,
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        return _ImageGridItem(
                          key: ValueKey(
                            _selectedImages[index].path,
                          ),
                          imageFile: _selectedImages[index],
                          index: index,
                          onRemove: _removeImage,
                          r: r,
                        );
                      },
                    ),
            ),

            // --- AREA TOMBOL PROSES ---
            if (_selectedImages.isNotEmpty)
              Padding(
                // RESPONSIVENESS: Responsive padding
                padding: EdgeInsets.all(r.spacing(20)),
                child: SizedBox(
                  width: double.infinity,
                  // RESPONSIVENESS: Responsive button height
                  height: r.size(55),
                  child: ElevatedButton(
                    // OPTIMIZATION: Cached static ButtonStyle
                    style: _processButtonStyle,
                    onPressed: _processImages,
                    child: Text(
                      "Lanjut Baca Cerita (${_selectedImages.length} Hal)",
                      // OPTIMIZATION + RESPONSIVENESS
                      style: _comicNueBoldBase.copyWith(
                        fontSize: r.font(18),
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
}

// OPTIMIZATION: _ImageGridItem menerima ResponsiveHelper r
// Menghindari context.r lookup tambahan di dalam StatelessWidget
class _ImageGridItem extends StatelessWidget {
  final File imageFile;
  final int index;
  final ValueChanged<int> onRemove;
  final ResponsiveHelper r;

  // OPTIMIZATION: Cache BorderRadius → static const
  static const BorderRadius _imageRadius =
      BorderRadius.all(Radius.circular(16));
  static const BorderRadius _labelRadius =
      BorderRadius.all(Radius.circular(8));

  const _ImageGridItem({
    super.key,
    required this.imageFile,
    required this.index,
    required this.onRemove,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            // OPTIMIZATION: Cached const BorderRadius
            borderRadius: _imageRadius,
            child: Image.file(
              imageFile,
              fit: BoxFit.cover,
              cacheWidth: 600,
            ),
          ),
        ),
        Positioned(
          // RESPONSIVENESS: Responsive position
          top: r.spacing(8),
          right: r.spacing(8),
          child: GestureDetector(
            onTap: () => onRemove(index),
            child: Container(
              // RESPONSIVENESS: Responsive padding
              padding: EdgeInsets.all(r.spacing(4)),
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                color: Colors.white,
                // RESPONSIVENESS: Responsive icon size
                size: r.size(20),
              ),
            ),
          ),
        ),
        Positioned(
          // RESPONSIVENESS: Responsive position
          bottom: r.spacing(8),
          left: r.spacing(8),
          child: Container(
            padding: EdgeInsets.symmetric(
              // RESPONSIVENESS: Responsive padding
              horizontal: r.spacing(8),
              vertical: r.spacing(4),
            ),
            decoration: const BoxDecoration(
              color: Colors.black54,
              // OPTIMIZATION: Cached const BorderRadius
              borderRadius: _labelRadius,
            ),
            child: Text(
              "Hal ${index + 1}",
              style: TextStyle(
                color: Colors.white,
                // RESPONSIVENESS: Responsive font
                fontSize: r.font(12),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// OPTIMIZATION: _PickerButton menerima ResponsiveHelper r
// Style tidak bisa static final karena color berbeda per instance
// Namun BorderRadius di-cache static const
class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  final ResponsiveHelper r;

  // OPTIMIZATION: Cache BorderRadius → static const
  static const BorderRadius _buttonRadius =
      BorderRadius.all(Radius.circular(16));

  const _PickerButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: textColor),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            // RESPONSIVENESS: Responsive font
            fontSize: r.font(14),
          ),
        ),
      ),
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          // RESPONSIVENESS: Responsive padding
          vertical: r.spacing(16),
          horizontal: r.spacing(8),
        ),
        backgroundColor: color,
        foregroundColor: textColor,
        elevation: 2,
        shape: const RoundedRectangleBorder(
          // OPTIMIZATION: Cached const BorderRadius
          borderRadius: _buttonRadius,
        ),
      ),
    );
  }
}