// lib/screens/home_screen.dart
// ─────────────────────────────
// Universal screen: secure snapshot/upload → supports Web & Emulator layouts & Offline Queue.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/analysis_result.dart';
import '../utils/app_theme.dart';
import '../widgets/result_card.dart';
import '../widgets/severity_badge.dart';
import 'offline_queue_screen.dart';


/// One corner bracket of the scanning viewfinder reticle.
class _ScanCorner extends StatelessWidget {
  final Alignment alignment;
  const _ScanCorner({required this.alignment});

  @override
  Widget build(BuildContext context) {
    final isTop   = alignment == Alignment.topLeft || alignment == Alignment.topRight;
    final isLeft  = alignment == Alignment.topLeft || alignment == Alignment.bottomLeft;
    const double size = 18;
    const double thickness = 2.5;
    const color = Colors.white;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            top:    isTop ? 0 : null,
            bottom: isTop ? null : 0,
            left:   isLeft ? 0 : null,
            right:  isLeft ? null : 0,
            child: Container(width: size, height: thickness, color: color),
          ),
          Positioned(
            top:    isTop ? 0 : null,
            bottom: isTop ? null : 0,
            left:   isLeft ? 0 : null,
            right:  isLeft ? null : 0,
            child: Container(width: thickness, height: size, color: color),
          ),
        ],
      ),
    );
  }
}

/// Faint horizontal grid lines drawn behind the scan line for a
/// "scanner"/sci-fi feel.
class _ScanGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;
    const gap = 20.0;
    for (double y = gap; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _api         = ApiService();
  final _picker      = ImagePicker();

  XFile?          _pickedFile;
  AnalysisResult? _result;
  bool            _loading = false;
  String?         _error;

  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;

  late AnimationController _scanController;
  late Animation<double>   _scanAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  // ── Secure Camera Capture ──────────────────────────────────────────────────
  Future<void> _pickImage() async {
    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (xFile == null) return;
      setState(() {
        _pickedFile    = xFile;
        _result        = null;
        _error         = null;
      });
    } catch (e) {
      _showError('Could not access device camera input: $e');
    }
  }


  Future<void> _pickImageFromGallery() async {
    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );

      if (xFile == null) return;
      setState(() {
        _pickedFile    = xFile;
        _result        = null;
        _error         = null;
      });
    } catch (e) {
      _showError('Could not access storage explorer: $e');
    }
  }


  // Each signed-in user has their own offline queue.
  Future<void> _saveToOfflineQueue() async {
    if (_pickedFile == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueKey = AuthService.instance.scopedKey('offline_pests_queue');
      List<String> queue = prefs.getStringList(queueKey) ?? [];

      if (!queue.contains(_pickedFile!.path)) {
        queue.add(_pickedFile!.path);
        await prefs.setStringList(queueKey, queue);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to Offline Queue! Upload it when internet is available.'),
            backgroundColor: Colors.orange,
          ),
        );
        _reset();
      }
    } catch (e) {
      _showError('Failed to cache offline capture: $e');
    }
  }


  void _showOfflineOptionDialog(String originalError) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.signal_wifi_off_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('You are Offline'),
          ],
        ),
        content: Text('Maaaring mahina o walang signal sa iyong pwesto.\n\nGusto mo bang i-save muna itong nakatagong larawan sa "Offline Saved Captures" para ma-analyze kapag may internet ka na?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(context);
              _saveToOfflineQueue();
            },
            child: const Text('Save Offline', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }


  Future<void> _analyzeImage() async {
    if (_pickedFile == null) return;
    setState(() { _loading = true; _error = null; _result = null; });

    try {
      File fileToUpload = File(_pickedFile!.path);
      final result = await _api.analyzeImage(fileToUpload);
      setState(() { _result = result; });
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      _showError('Connection issue: $e');

      if (errorString.contains('socketexception') ||
          errorString.contains('network') ||
          errorString.contains('timeout') ||
          errorString.contains('connection failed')) {
        _showOfflineOptionDialog(e.toString());
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    setState(() => _error = msg);
  }

  void _reset() => setState(() {
    _pickedFile    = null;
    _result        = null;
    _error         = null;
  });


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_icon.png',
              height: 28,
              width: 28,
            ),
            const SizedBox(width: 8),
            const Text('Rice Pest Detector', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_special_rounded),
            tooltip: 'Offline Captures',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OfflineQueueScreen()),
              );
            },
          ),
          if (_pickedFile != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset Tracker',
              onPressed: _reset,
            ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out (${AuthService.instance.displayName ?? ''})',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Greeting ───────────────────────────────────────────────────
            if (AuthService.instance.displayName != null) ...[
              Text(
                'Hello, ${AuthService.instance.displayName}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Image preview ──────────────────────────────────────────────
            _buildImageSection(),
            const SizedBox(height: 20),

            // ── Error Message Display ──────────────────────────────────────
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
            ],


            if (_pickedFile == null) ...[
              Column(

                crossAxisAlignment: CrossAxisAlignment.stretch, //
                children: [
                  _sourceButton(
                    icon:    Icons.photo_camera_rounded,
                    label:   kIsWeb ? 'Start Desktop Webcam' : 'Capture Your Rice Field ',
                    onTap:   _pickImage,
                    primary: true,
                  ),
                  const SizedBox(height: 12),

                  _sourceButton(
                    icon:    Icons.photo_library_rounded,
                    label:   'Upload from Gallery',
                    onTap:   _pickImageFromGallery,
                    primary: false,
                  ),
                  const SizedBox(height: 20),
                  _buildTipsCard(),
                ],
              ),
            ],


            if (_pickedFile != null && _result == null && !_loading) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _analyzeImage,
                icon:  const Icon(Icons.analytics_rounded),
                label: const Text('Analyze Image'),
              ),
            ],

            // ── Loading indicator ──────────────────────────────────────────
            // The scanning-line animation over the photo itself now carries
            // the primary "in progress" feedback, so this is just a short
            // status line underneath.
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(
                child: Text('Running model inference…',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ],

            // ── Result card ────────────────────────────────────────────────
            if (_result != null) ...[
              const SizedBox(height: 20),
              ResultCard(result: _result!),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _reset,
                icon:  const Icon(Icons.add_a_photo_outlined),
                label: const Text('Scan Another Crop'),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Ask before signing out so it isn't tapped by accident.
  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'Your scans stay saved. Sign in again with your mobile number and PIN to see them.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AuthService.instance.logout();
    }
  }

  static const double _imageHeight = 280;

  Widget _buildImageSection() {
    if (_pickedFile == null) {
      return _emptyImagePlaceholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          kIsWeb
              ? Image.network(
            _pickedFile!.path,
            width: double.infinity,
            height: _imageHeight,
            fit: BoxFit.cover,
          )
              : Image.file(
            File(_pickedFile!.path),
            width: double.infinity,
            height: _imageHeight,
            fit: BoxFit.cover,
          ),
          if (_loading) _buildScanOverlay(),
          if (_result != null)
            Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(8),
              child: SeverityBadge(severity: _result!.severity),
            ),
        ],
      ),
    );
  }

  /// Sci-fi style scanning effect: a glowing line sweeps up and down over
  /// the captured photo while the backend is analyzing it.
  Widget _buildScanOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          // Subtle dark scrim so the glowing line reads clearly against
          // any photo.
          Container(color: Colors.black.withOpacity(0.25)),

          // Faint horizontal grid lines for a "scanner" feel.
          Positioned.fill(
            child: CustomPaint(painter: _ScanGridPainter()),
          ),

          // The moving scan line itself.
          AnimatedBuilder(
            animation: _scanAnimation,
            builder: (_, __) {
              final top = _scanAnimation.value * (_imageHeight - 3);
              return Positioned(
                top: top,
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryLight.withOpacity(0),
                        AppTheme.primaryLight,
                        AppTheme.primaryLight.withOpacity(0),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryLight.withOpacity(0.9),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Scanning corner brackets, like a viewfinder reticle.
          const Positioned(top: 10, left: 10, child: _ScanCorner(alignment: Alignment.topLeft)),
          const Positioned(top: 10, right: 10, child: _ScanCorner(alignment: Alignment.topRight)),
          const Positioned(bottom: 10, left: 10, child: _ScanCorner(alignment: Alignment.bottomLeft)),
          const Positioned(bottom: 10, right: 10, child: _ScanCorner(alignment: Alignment.bottomRight)),

          // Status pill.
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Scanning for pests…',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyImagePlaceholder() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, child) => Transform.scale(
        scale: _pulseAnimation.value,
        child: child,
      ),
      child: Container(
        height: 320,
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryLight.withOpacity(0.3), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/app_logo_full.png',
              height: 190,
            ),
            const SizedBox(height: 12),
            const Text('Camera Viewfinder Ready',
                style: TextStyle(fontSize: 16, color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Capture a real-time photo of a rice leaf field',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsCard() {
    const tips = [
      'Get close to a single leaf — fill most of the frame',
      'Shoot in daylight, avoid heavy shadows or glare',
      'Hold the camera steady to avoid blur',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryLight.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.tips_and_updates_rounded, color: AppTheme.primary, size: 18),
              SizedBox(width: 6),
              Text('Tips for best results',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          ...tips.map(
                (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle, color: AppTheme.primary, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tip,
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.3)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceButton({
    required IconData icon,
    required String   label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    if (primary) {
      return ElevatedButton.icon(
        onPressed: onTap,
        icon:  Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 2,
        ),
      );
    }
    // Secondary action — visually lighter so it doesn't compete with the
    // primary capture button, but still clearly tappable.
    return OutlinedButton.icon(
      onPressed: onTap,
      icon:  Icon(icon, color: AppTheme.primary),
      label: Text(label, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
    );
  }
}
