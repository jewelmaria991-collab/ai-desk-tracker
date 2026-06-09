import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:js' as js;
import 'dart:async';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Error fetching cameras: $e");
  }
  runApp(const ClutterTrackerApp());
}

class ClutterTrackerApp extends StatelessWidget {
  const ClutterTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desk Clutter Tracker',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: const TrackerDashboard(),
    );
  }
}

class TrackerDashboard extends StatefulWidget {
  const TrackerDashboard({super.key});

  @override
  State<TrackerDashboard> createState() => _TrackerDashboardState();
}

class _TrackerDashboardState extends State<TrackerDashboard> {
  CameraController? _cameraController;
  int _objectCount = 0;
  List<String> _detectedLabels = []; 
  final int _clutterThreshold = 5; 
  bool _isCameraInitialized = false;
  bool _isModelLoading = true;
  Timer? _detectionTimer;

  bool get _isCluttered => _objectCount > _clutterThreshold;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadAIModel();
  }

  void _loadAIModel() {
    js.context.callMethod('eval', [
      '''
      window.loadModel = async function() {
        try {
          window.detector = await cocoSsd.load();
          console.log("COCO-SSD Model Loaded Successfully!");
        } catch(e) {
          console.log("Model loading error: " + e);
        }
      }
      window.loadModel();
      '''
    ]);
    
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _isModelLoading = false;
        });
        _startDetectionLoop();
      }
    });
  }

  void _startDetectionLoop() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      _runObjectDetection();
    });
  }

  void _runObjectDetection() {
    if (!_isCameraInitialized || _cameraController == null) return;

    try {
      js.context.callMethod('eval', [
        '''
        (async function() {
          var videoElements = document.getElementsByTagName('video');
          if (videoElements.length > 0 && videoElements[0] && window.detector) {
            var video = videoElements[0];
            try {
              var predictions = await window.detector.detect(video);
              var labels = predictions ? predictions.map(p => p.class) : [];
              
              if (window.updateFlutterData) {
                window.updateFlutterData(predictions.length, labels);
              }
            } catch (err) {
              console.log("Detection frame skipped: " + err);
            }
          }
        })();
        '''
      ]);
    } catch (e) {
      debugPrint("Detection error: $e");
    }
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) return;

    // Standard camera controller setup
    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      js.context['updateFlutterData'] = (int count, dynamic labels) {
        if (mounted) {
          setState(() {
            _objectCount = count;
            if (labels != null) {
              _detectedLabels = List<String>.from(labels);
            } else {
              _detectedLabels = [];
            }
          });
        }
      };

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Camera failed: $e");
    }
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🛒 AI Desk Clutter Tracker'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Alert Banner
            Container(
              padding: const EdgeInsets.all(20),
              color: _isCluttered ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3),
              child: Column(
                children: [
                  Text(
                    _isCluttered ? '⚠️ CLUTTER DETECTED' : '✅ DESK IS CLEAN',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isCluttered ? 'Clear some items!' : 'Workspace looks great!',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Item Counter Stats Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  'Objects Detected: $_objectCount', 
                  style: const TextStyle(fontSize: 20, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Limit: $_clutterThreshold', 
                  style: const TextStyle(fontSize: 20, color: Colors.orangeAccent),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // List of detected item names
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _detectedLabels.isEmpty 
                    ? 'Scanning for items...' 
                    : 'AI Sees: ${_detectedLabels.join(", ")}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.white70, fontStyle: FontStyle.italic),
              ),
            ),
            const SizedBox(height: 20),

            // Stable, sharp Video Feed Layer
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isCameraInitialized && _cameraController != null
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          // Using standard preview but fitting it neatly to eliminate double-blur
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: CameraPreview(_cameraController!),
                            ),
                          ),
                          if (_isModelLoading)
                            Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 15),
                                    Text('Waking up AI Brain (COCO-SSD)...', style: TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      )
                    : const Center(child: Text('Starting Live Stream...')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}