// lib/ui/scan_screen.dart
//
// Camera capture with a framing guide, plus gallery upload. Works on devices
// with no camera (gallery only) and when camera permission is denied.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/library_repository.dart';
import '../services/ocr_service.dart';
import 'review_screen.dart';

class ScanScreen extends StatefulWidget {
  final LibraryRepository repository;
  const ScanScreen({super.key, required this.repository});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  CameraController? _camera; // null = no camera or not ready
  String? _cameraError;
  bool _busy = false;
  final _ocr = OcrService();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No camera found. Use the gallery instead.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // "high" (720p-1080p) reads printed sheets well and is much faster than max.
      final controller = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraError = null;
      });
    } on CameraException catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera unavailable (${e.code}). Use the gallery instead.');
    }
  }

  // Release the camera when the app goes to the background, re-open on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _camera;
    if (state == AppLifecycleState.inactive && cam != null) {
      _camera = null;
      cam.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _initCamera();
    }
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final photo = await cam.takePicture();
      await _readAndReview(photo.path);
    } catch (e) {
      _showError('Could not take the photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      await _readAndReview(picked.path);
    } catch (e) {
      _showError('Could not read that image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readAndReview(String path) async {
    final text = await _ocr.readSheet(path);
    if (!mounted) return;
    if (text.trim().isEmpty) {
      _showError('No text found. Try more light or hold the phone flatter.');
      return;
    }
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ReviewScreen(rawText: text, repository: widget.repository),
    ));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _ocr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a chord sheet')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cam != null && cam.value.isInitialized)
            Center(child: CameraPreview(cam))
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _cameraError == null
                    ? const CircularProgressIndicator()
                    : Text(_cameraError!, textAlign: TextAlign.center),
              ),
            ),
          if (cam != null)
            IgnorePointer(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.9,
                  heightFactor: 0.7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.cyanAccent, width: 2.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          if (_busy)
            const ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Reading the sheet...'),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: 'gallery',
                  tooltip: 'Choose from gallery',
                  onPressed: _busy ? null : _pickFromGallery,
                  child: const Icon(Icons.photo_library),
                ),
                if (cam != null)
                  FloatingActionButton.large(
                    heroTag: 'shutter',
                    tooltip: 'Take photo',
                    onPressed: _busy ? null : _capture,
                    child: const Icon(Icons.camera_alt, size: 36),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
