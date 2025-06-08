import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import '../services/gemini_service.dart';
import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../services/friends_service.dart';
import '../screens/conversations_screen.dart';
import '../screens/friends_screen.dart';
import '../screens/eco_challenges_screen.dart';
import '../screens/food_locator.dart';
import '../widgets/message_button.dart';
import '../widgets/friend_button.dart';
import '../widgets/modern_bottom_nav.dart';

class PollutionTrackerScreen extends StatefulWidget {
  @override
  _PollutionTrackerScreenState createState() => _PollutionTrackerScreenState();
}

class _PollutionTrackerScreenState extends State<PollutionTrackerScreen> {
  GoogleMapController? _mapController;
  Location _location = Location();
  LocationData? _currentLocation;
  Set<Marker> _markers = {};
  bool _isLoading = true;
  String _errorMessage = '';

  // Add clustering related variables
  static const double _clusterRadius = 0.1; // 0.1 miles for clustering
  Map<String, List<Map<String, dynamic>>> _clusteredMarkers = {};
  Set<Marker> _displayedMarkers = {};

  // Add marker icon cache
  final Map<String, BitmapDescriptor> _markerIconCache = {};
  final GeminiService _geminiService = GeminiService();
  bool _isAnalyzing = false;
  bool _aiAnalysisComplete = false;
  String _aiAnalysisResult = '';
  String _aiAnalysisError = '';
  String _aiAnalysisStatus = '';
  String _aiAnalysisProgress = '';
  String _aiAnalysisImage = '';
  String _aiAnalysisImageUrl = '';
  DatabaseReference? _database;
  DatabaseReference? _pollutionMarkersRef;
  bool _firebaseConnected = false;

  final ImagePicker _imagePicker = ImagePicker();

  final AuthService _authService = AuthService();
  final MessagingService _messagingService = MessagingService();
  final FriendsService _friendsService = FriendsService();

  StreamSubscription<LocationData>? _locationSubscription;
  StreamSubscription<DatabaseEvent>? _firebaseSubscription;

  String get _currentUserId => _authService.currentUserId ?? 'unknown';
  String get _currentUserName => _authService.currentUserDisplayName;
  bool get _isAnonymous => false;

  final Map<String, Map<String, dynamic>> _pollutionTypes = {
    'Air Pollution': {
      'color': Colors.grey[700]!,
      'hue': BitmapDescriptor.hueViolet,
      'icon': Icons.air,
    },
    'Water Pollution': {
      'color': Colors.blue[800]!,
      'hue': BitmapDescriptor.hueBlue,
      'icon': Icons.water_drop,
    },
    'Noise Pollution': {
      'color': Colors.orange[700]!,
      'hue': BitmapDescriptor.hueOrange,
      'icon': Icons.volume_up,
    },
    'Littering/Trash': {
      'color': Colors.brown[600]!,
      'hue': BitmapDescriptor.hueRed,
      'icon': Icons.delete,
    },
    'Chemical Spill': {
      'color': Colors.purple[700]!,
      'hue': BitmapDescriptor.hueMagenta,
      'icon': Icons.dangerous,
    },
    'Light Pollution': {
      'color': Colors.yellow[700]!,
      'hue': BitmapDescriptor.hueYellow,
      'icon': Icons.lightbulb,
    },
    'Soil Contamination': {
      'color': Colors.green[900]!,
      'hue': BitmapDescriptor.hueGreen,
      'icon': Icons.grass,
    },
    'Other': {
      'color': Colors.pink[600]!,
      'hue': BitmapDescriptor.hueRose,
      'icon': Icons.report_problem,
    },
  };

  bool _useMiles = true;
  String _searchQuery = '';
  String _sortBy = 'distance';
  double _radius = 10.0; // Default radius in miles
  final TextEditingController _radiusController = TextEditingController();

  // Constants for radius limits
  static const double _maxRadiusMiles = 100.0;
  static const double _maxRadiusKm = 160.0;
  static const double _minRadius = 0.1;

  // Cache for marker data to avoid repeated Firebase calls
  final Map<String, Map<String, dynamic>> _markerDataCache = {};

  int _currentIndex = 2;

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    
    switch (index) {
      case 0:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => FoodLocatorScreen(),
          ),
        );
        break;
      case 1:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => EcoChallengesScreen(),
          ),
        );
        break;
      case 2:
        // Already on Pollution Tracker
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _radiusController.text = _radius.toString();
    _createMarkerIcons();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _firebaseSubscription?.cancel();
    _mapController?.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  Future<void> _initializeApp() async {
    await _initializeFirebase();
    await _setupLocation();
    if (_firebaseConnected) {
      await _loadPollutionMarkers();
      _setupRealtimeListener();
    }
  }

  Future<void> _initializeFirebase() async {
    try {
      _database = FirebaseDatabase.instance.ref();
      _pollutionMarkersRef = _database!.child('pollutionMarkers');
      _firebaseConnected = true;
    } catch (e) {
      _firebaseConnected = false;
      _showSnackBar('Running in offline mode - markers won\'t be shared', Colors.orange);
    }
  }

  Future<void> _setupLocation() async {
    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          _setError('Location services are disabled');
          return;
        }
      }
      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          _setError('Location permission denied');
          return;
        }
      }
      LocationData locationData = await _location.getLocation();
      _safeSetState(() {
        _currentLocation = locationData;
        _isLoading = false;
      });
      _locationSubscription?.cancel();
      _locationSubscription = _location.onLocationChanged.listen((LocationData newLocation) {
        _safeSetState(() {
          _currentLocation = newLocation;
        });
        _animateToLocation(newLocation);
      });
    } catch (e) {
      _setError('Failed to get location: $e');
    }
  }

  Future<void> _animateToLocation(LocationData location) async {
    if (_mapController != null && location.latitude != null && location.longitude != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(location.latitude!, location.longitude!),
            zoom: 16.0,
          ),
        ),
      );
    }
  }

  Future<void> _loadPollutionMarkers() async {
    if (!_firebaseConnected || _pollutionMarkersRef == null) return;
    try {
      final snapshot = await _pollutionMarkersRef!.get();
      if (snapshot.exists && mounted) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        _buildMarkersFromData(data);
      }
    } catch (e) {
      _showSnackBar('Failed to load community markers', Colors.orange);
    }
  }

  void _setupRealtimeListener() {
    if (!_firebaseConnected || _pollutionMarkersRef == null) return;
    _firebaseSubscription?.cancel();
    _firebaseSubscription = _pollutionMarkersRef!.onValue.listen((DatabaseEvent event) {
      print('Firebase data changed, rebuilding markers...');
      if (!mounted) return;
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        print('Current marker count in Firebase: ${data.length}');
        _buildMarkersFromData(data);
      } else {
        _safeSetState(() {
          _markers.removeWhere((marker) => _isPollutionMarker(marker));
          _markerDataCache.clear();
        });
      }
    }, onError: (error) {
      if (mounted) {
        _showSnackBar('Real-time sync error', Colors.red);
      }
    });
  }

  Future<void> _createMarkerIcons() async {
    // Create base marker icons for each pollution type
    for (var entry in _pollutionTypes.entries) {
      final type = entry.key;
      final config = entry.value;
      _markerIconCache[type] = BitmapDescriptor.defaultMarkerWithHue(config['hue']);
    }
  }

  Future<BitmapDescriptor> _createMarkerIcon(String pollutionType, {int? count}) async {
    final config = _pollutionTypes[pollutionType] ?? _pollutionTypes['Other']!;
    
    // Create a custom marker
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final size = Size(48, 48);
    
    // Draw the base marker
    final markerPaint = Paint()
      ..color = config['color']
      ..style = PaintingStyle.fill;
    
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    
    canvas.drawPath(path, markerPaint);
    
    // Draw the number badge if count is provided and greater than 1
    if (count != null && count > 1) {
      final badgePaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      
      // Increased badge size from 24 to 32
      final badgeSize = 32.0;
      final badgeX = size.width - badgeSize / 2;
      final badgeY = badgeSize / 2;
      
      canvas.drawCircle(
        Offset(badgeX, badgeY),
        badgeSize / 2,
        badgePaint,
      );
      
      // Draw the number with larger font size
      final textPainter = TextPainter(
        text: TextSpan(
          text: count.toString(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 20, // Increased from 14 to 20
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          badgeX - textPainter.width / 2,
          badgeY - textPainter.height / 2,
        ),
      );
    }
    
    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  void _buildMarkersFromData(Map<dynamic, dynamic> data) {
    _safeSetState(() {
      _markers.removeWhere((marker) => _isPollutionMarker(marker));
      _markerDataCache.clear();
      _clusteredMarkers.clear();
      
      // First, collect all markers and preserve Firebase keys
      data.forEach((key, value) {
        final markerData = Map<String, dynamic>.from(value);
        // IMPORTANT: Store the Firebase key with the marker data
        markerData['firebaseKey'] = key.toString();
        _markerDataCache[key.toString()] = markerData;
        
        final latitude = (markerData['latitude'] as num?)?.toDouble() ?? 0.0;
        final longitude = (markerData['longitude'] as num?)?.toDouble() ?? 0.0;
        
        // Find or create a cluster for this marker
        String clusterKey = _findOrCreateCluster(latitude, longitude);
        if (!_clusteredMarkers.containsKey(clusterKey)) {
          _clusteredMarkers[clusterKey] = [];
        }
        // Store both the marker data AND the Firebase key
        final markerWithKey = Map<String, dynamic>.from(markerData);
        markerWithKey['originalFirebaseKey'] = key.toString();
        _clusteredMarkers[clusterKey]!.add(markerWithKey);
      });

      // Now create the actual markers (either clustered or individual)
      _clusteredMarkers.forEach((clusterKey, markers) async {
        final pollutionType = _getMostCommonPollutionType(markers);
        final pollutionConfig = _pollutionTypes[pollutionType] ?? _pollutionTypes['Other']!;
        
        if (markers.length > 1) {
          // Create a cluster marker
          final clusterCenter = _calculateClusterCenter(markers);
          final clusterIcon = await _createMarkerIcon(pollutionType, count: markers.length);
          
          // Create cluster marker data
          final clusterMarkerData = {
            'isCluster': true,
            'clusterCount': markers.length,
            'clusterMarkers': markers,
            'pollutionType': pollutionType,
            'latitude': clusterCenter['latitude'] ?? 0.0,
            'longitude': clusterCenter['longitude'] ?? 0.0,
          };
          
          _markerDataCache[clusterKey] = clusterMarkerData;
          
          _markers.add(
            Marker(
              markerId: MarkerId(clusterKey),
              position: LatLng(
                clusterCenter['latitude'] ?? 0.0,
                clusterCenter['longitude'] ?? 0.0,
              ),
              icon: clusterIcon,
              infoWindow: InfoWindow(
                title: '${markers.length} Pollution Reports',
                snippet: 'Tap to view all reports in this area',
              ),
              onTap: () => _showClusterDetailsDialog(clusterKey, markers),
            ),
          );
        } else {
          // Create individual marker
          final markerData = markers[0];
          final isMyMarker = markerData['addedBy'] == _currentUserId;
          final addedByName = markerData['addedByName'] ?? 'Unknown User';
          final individualIcon = await _createMarkerIcon(pollutionType);
          final firebaseKey = markerData['originalFirebaseKey'] ?? markerData['firebaseKey'];
          
          // Add isCluster flag to individual marker data
          markerData['isCluster'] = false;
          _markerDataCache[firebaseKey] = markerData;
          
          _markers.add(
            Marker(
              markerId: MarkerId(firebaseKey),
              position: LatLng(
                (markerData['latitude'] as num?)?.toDouble() ?? 0.0,
                (markerData['longitude'] as num?)?.toDouble() ?? 0.0,
              ),
              icon: individualIcon,
              infoWindow: InfoWindow(
                title: '$pollutionType - ${markerData['severity'] ?? 'Unknown'}',
                snippet: isMyMarker 
                  ? 'Reported by you • Tap to view details' 
                  : 'Reported by $addedByName • Tap to view details',
              ),
              onTap: () => _onMarkerTapped(firebaseKey, markerData),
            ),
          );
        }
      });
    });
  }

  String _findOrCreateCluster(double latitude, double longitude) {
    for (String clusterKey in _clusteredMarkers.keys) {
      final clusterCenter = _calculateClusterCenter(_clusteredMarkers[clusterKey]!);
      final distance = _calculateDistance(
        latitude,
        longitude,
        clusterCenter['latitude'] ?? 0.0,
        clusterCenter['longitude'] ?? 0.0,
      );
      
      // Convert to miles if needed
      final distanceInMiles = _useMiles ? distance * 0.621371 : distance;
      
      if (distanceInMiles <= _clusterRadius) {
        return clusterKey;
      }
    }
    
    // If no nearby cluster found, create a new one
    return 'cluster_${DateTime.now().millisecondsSinceEpoch}_${_clusteredMarkers.length}';
  }

  Map<String, double> _calculateClusterCenter(List<Map<String, dynamic>> markers) {
    double totalLat = 0;
    double totalLng = 0;
    
    for (var marker in markers) {
      totalLat += (marker['latitude'] as num?)?.toDouble() ?? 0.0;
      totalLng += (marker['longitude'] as num?)?.toDouble() ?? 0.0;
    }
    
    return {
      'latitude': totalLat / markers.length,
      'longitude': totalLng / markers.length,
    };
  }

  String _getMostCommonPollutionType(List<Map<String, dynamic>> markers) {
    Map<String, int> typeCount = {};
    String mostCommon = 'Other';
    int maxCount = 0;
    
    for (var marker in markers) {
      final type = marker['pollutionType'] ?? 'Other';
      typeCount[type] = (typeCount[type] ?? 0) + 1;
      
      if (typeCount[type]! > maxCount) {
        maxCount = typeCount[type]!;
        mostCommon = type;
      }
    }
    
    return mostCommon;
  }

  Future<void> _showClusterDetailsDialog(String clusterKey, List<Map<String, dynamic>> markers) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[700]!.withOpacity(0.1),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.group_work, color: Colors.red[700], size: 24),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${markers.length} Pollution Reports',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'In this area',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: markers.length,
                    itemBuilder: (context, index) {
                      final markerData = markers[index];
                      final isMyMarker = markerData['addedBy'] == _currentUserId;
                      final pollutionType = markerData['pollutionType'] ?? 'Other';
                      final pollutionConfig = _pollutionTypes[pollutionType] ?? _pollutionTypes['Other']!;
                      
                      // Get the Firebase key for this marker
                      final firebaseKey = markerData['originalFirebaseKey'] ?? markerData['firebaseKey'];
                      
                      return Card(
                        margin: EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            _onMarkerTapped(firebaseKey, markerData);
                          },
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      pollutionConfig['icon'],
                                      color: pollutionConfig['color'],
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            pollutionType,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            'Severity: ${markerData['severity'] ?? 'Unknown'}',
                                            style: TextStyle(
                                              color: _getSeverityColor(markerData['severity'] ?? 'Low'),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isMyMarker)
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        onPressed: () async {
                                          final shouldDelete = await _showDeleteConfirmationDialog(
                                            pollutionType,
                                            markerData['addedByName'] ?? 'Unknown User',
                                            true
                                          );
                                          if (shouldDelete == true) {
                                            // Close the dialog first
                                            Navigator.pop(context);
                                            
                                            // Delete the marker using the Firebase key
                                            await _deleteMarkerFromCluster(firebaseKey, pollutionType);
                                          }
                                        },
                                        tooltip: 'Delete',
                                      ),
                                  ],
                                ),
                                if (markerData['description'] != null && markerData['description'].isNotEmpty) ...[
                                  SizedBox(height: 8),
                                  Text(
                                    markerData['description'],
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 16,
                                      color: Colors.grey[600],
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      markerData['addedByName'] ?? 'Unknown User',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                    Spacer(),
                                    if (markerData['images'] != null &&
                                        (markerData['images'] as List).isNotEmpty)
                                      Text(
                                        '${(markerData['images'] as List).length} photos',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addPollutionMarker() async {
    if (_currentLocation == null) {
      _showSnackBar('Location not available. Please wait for GPS.', Colors.red);
      return;
    }
    final pollutionData = await _showPollutionInputDialog();
    if (pollutionData == null) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing report...'),
            Text(
              'Converting images...',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );

    try {
      final markerId = 'pollution_${DateTime.now().millisecondsSinceEpoch}';
      final pollutionConfig = _pollutionTypes[pollutionData['pollutionType']] ?? _pollutionTypes['Other']!;

      // Image processing
      List<String> base64Images = [];
      for (int i = 0; i < pollutionData['images'].length; i++) {
        final imageFile = pollutionData['images'][i] as File;
        final base64String = await _convertImageToBase64(imageFile);
        if (base64String != null) {
          base64Images.add(base64String);
        }
      }

      final markerData = {
        'pollutionType': pollutionData['pollutionType'],
        'severity': pollutionData['severity'],
        'description': pollutionData['description'],
        'latitude': _currentLocation!.latitude!,
        'longitude': _currentLocation!.longitude!,
        'timestamp': ServerValue.timestamp,
        'addedBy': _currentUserId,
        'addedByName': _currentUserName,
        'images': base64Images,
        'imageCount': base64Images.length,
      };

      // Cache the marker data
      _markerDataCache[markerId] = markerData;

      // Add marker locally first
      _safeSetState(() {
        _markers.add(
          Marker(
            markerId: MarkerId(markerId),
            position: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
            infoWindow: InfoWindow(
              title: '${pollutionData['pollutionType']} - ${pollutionData['severity']}',
              snippet: 'Reported by you • Tap to view details',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(pollutionConfig['hue']),
            onTap: () => _onMarkerTapped(markerId, markerData),
          ),
        );
      });

      // Save to Firebase if connected
      if (_firebaseConnected && _pollutionMarkersRef != null) {
        await _pollutionMarkersRef!.child(markerId).set(markerData);
        Navigator.of(context).pop();
        _showSnackBar('Pollution report "${pollutionData['pollutionType']}" shared with community!', Colors.green);
      } else {
        Navigator.of(context).pop();
        _showSnackBar('Report added locally (offline mode)', Colors.orange);
      }
    } catch (e) {
      Navigator.of(context).pop();
      _showSnackBar('Failed to save report: $e', Colors.red);
    }
  }

  Future<String?> _convertImageToBase64(File imageFile) async {
    try {
      if (!await imageFile.exists()) return null;
      final bytes = await imageFile.readAsBytes();
      Uint8List processedBytes = bytes;
      final base64String = base64Encode(processedBytes);
      return base64String;
    } catch (e) {
      return null;
    }
  }

 Future<Map<String, dynamic>?> _showPollutionInputDialog() async {
  String selectedPollutionType = _pollutionTypes.keys.first;
  String selectedSeverity = 'Low';
  String description = '';
  List<File> selectedImages = [];

  // Reset AI analysis state
  _aiAnalysisComplete = false;
  
  // Create controllers for the text fields
  final TextEditingController descriptionController = TextEditingController();

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final pollutionConfig = _pollutionTypes[selectedPollutionType]!;

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.report_problem, color: Colors.red),
                SizedBox(width: 8),
                Text('Report Pollution'),
              ],
            ),
            content: Container(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Report pollution at your current location:'),
                    SizedBox(height: 16),
                    Text(
                      'Type of Pollution *',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[400]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedPollutionType,
                          isExpanded: true,
                          onChanged: (String? newValue) {
                            setDialogState(() {
                              selectedPollutionType = newValue!;
                            });
                          },
                          items: _pollutionTypes.keys.map<DropdownMenuItem<String>>((String type) {
                            final config = _pollutionTypes[type]!;
                            return DropdownMenuItem<String>(
                              value: type,
                              child: Row(
                                children: [
                                  Icon(config['icon'], color: config['color'], size: 20),
                                  SizedBox(width: 8),
                                  Text(type),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Severity Level *',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[400]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedSeverity,
                          isExpanded: true,
                          onChanged: (String? newValue) {
                            setDialogState(() {
                              selectedSeverity = newValue!;
                            });
                          },
                          items: ['Low', 'Medium', 'High', 'Critical'].map<DropdownMenuItem<String>>((String severity) {
                            Color severityColor = Colors.green;
                            if (severity == 'Medium') severityColor = Colors.orange;
                            else if (severity == 'High') severityColor = Colors.red;
                            else if (severity == 'Critical') severityColor = Colors.red[900]!;
                            return DropdownMenuItem<String>(
                              value: severity,
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: severityColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(severity),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      onChanged: (value) => description = value,
                      decoration: InputDecoration(
                        labelText: 'Description *',
                        hintText: 'Describe the pollution issue...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                      ),
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    SizedBox(height: 16),
                    // AI Analysis Button - Conditional rendering based on analysis state
                    if (!_aiAnalysisComplete) ...[
                      SizedBox(
                        width: double.infinity,
                        child: _isAnalyzing
                            ? Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red[700]!),
                                    ),
                                  ),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: selectedImages.isEmpty
                                    ? null
                                    : () async {
                                        if (selectedImages.isEmpty) return;
                                        
                                        setDialogState(() {
                                          _isAnalyzing = true;
                                        });
                                        
                                        try {
                                          print('Starting AI pollution analysis...');
                                          final analysis = await _geminiService.analyzePollutionImage(selectedImages[0]);
                                          print('Analysis complete: $analysis');
                                          
                                          if (analysis['pollutionType'] == 'Error') {
                                            throw Exception(analysis['description']);
                                          }

                                          if (analysis['pollutionType'] == 'NO_POLLUTION_DETECTED') {
                                            showDialog(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: Row(
                                                  children: [
                                                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                                    SizedBox(width: 8),
                                                    Text('No Pollution Detected'),
                                                  ],
                                                ),
                                                content: Text('The AI could not detect any pollution in the image. Please try again with a clearer image showing environmental issues.'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.of(context).pop(),
                                                    child: Text('OK'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            // Reset the analysis state but don't mark as complete
                                            setDialogState(() {
                                              _isAnalyzing = false;
                                            });
                                            return;
                                          }
                                          
                                          // Update the form with AI analysis
                                          setDialogState(() {
                                            selectedPollutionType = analysis['pollutionType'] ?? 'Other';
                                            selectedSeverity = analysis['severity'] ?? 'Low';
                                            descriptionController.text = analysis['description'] ?? '';
                                            description = descriptionController.text;
                                            _isAnalyzing = false;
                                            _aiAnalysisComplete = true;
                                          });
                                          
                                          // Show success message
                                          showDialog(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: Row(
                                                children: [
                                                  Icon(Icons.check_circle, color: Colors.red[700]),
                                                  SizedBox(width: 8),
                                                  Text('Analysis Complete'),
                                                ],
                                              ),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'The AI has analyzed the pollution in your image and filled in the form. Please review and edit the content to ensure it accurately represents the pollution issue.',
                                                    style: TextStyle(fontSize: 16),
                                                  ),
                                                  SizedBox(height: 16),
                                                  Text(
                                                    'Important:',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                  SizedBox(height: 8),
                                                  Text('• Verify the pollution type is correct'),
                                                  Text('• Check that the severity level is accurate'),
                                                  Text('• Make sure the description is precise'),
                                                ],
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(context).pop(),
                                                  child: Text('I Will Review'),
                                                ),
                                              ],
                                            ),
                                          );
                                          
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('AI analysis complete!'),
                                              backgroundColor: Colors.red[700],
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        } catch (e) {
                                          print('Error during AI analysis: $e');
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Failed to analyze image: $e'),
                                              backgroundColor: Colors.red,
                                              duration: Duration(seconds: 3),
                                            ),
                                          );
                                          // Reset analysis state on error
                                          setDialogState(() {
                                            _isAnalyzing = false;
                                          });
                                        }
                                      },
                                icon: Icon(Icons.auto_awesome),
                                label: Text('Let AI Analyze Pollution'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red[700],
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey[300],
                                  disabledForegroundColor: Colors.grey[600],
                                ),
                              ),
                      ),
                      SizedBox(height: 16),
                    ],
                    Text(
                      'Photos * (At least 1 required)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    if (selectedImages.isNotEmpty) ...[
                      Container(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: selectedImages.length,
                          itemBuilder: (context, index) {
                            return Container(
                              margin: EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      selectedImages[index],
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedImages.removeAt(index);
                                        });
                                      },
                                      child: Container(
                                        padding: EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final image = await _imagePicker.pickImage(
                                source: ImageSource.camera,
                                maxWidth: 1024,
                                maxHeight: 1024,
                                imageQuality: 80,
                              );
                              if (image != null) {
                                setDialogState(() {
                                  selectedImages.add(File(image.path));
                                });
                              }
                            },
                            icon: Icon(Icons.camera_alt),
                            label: Text('Camera'),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final image = await _imagePicker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1024,
                                maxHeight: 1024,
                                imageQuality: 80,
                              );
                              if (image != null) {
                                setDialogState(() {
                                  selectedImages.add(File(image.path));
                                });
                              }
                            },
                            icon: Icon(Icons.photo_library),
                            label: Text('Gallery'),
                          ),
                        ),
                      ],
                    ),
                    if (selectedImages.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Please add at least one photo (camera or gallery)',
                          style: TextStyle(
                            color: Colors.red[600],
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: description.trim().isNotEmpty && selectedImages.isNotEmpty
                    ? () {
                        Navigator.of(context).pop({
                          'pollutionType': selectedPollutionType,
                          'severity': selectedSeverity,
                          'description': description.trim(),
                          'images': selectedImages,
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text('Report'),
              ),
            ],
          );
        },
      );
    },
  );
}

  Future<void> _onMarkerTapped(String markerId, Map<String, dynamic> markerData) async {
    await _showMarkerDetailsDialog(markerId, markerData);
  }

  Future<void> _showMarkerDetailsDialog(String markerId, Map<String, dynamic> markerData) async {
    final isMyMarker = markerData['addedBy'] == _currentUserId;
    final addedByName = markerData['addedByName'] ?? 'Unknown User';
    final addedById = markerData['addedBy'] ?? '';
    final pollutionType = markerData['pollutionType'] ?? 'Other';
    final pollutionConfig = _pollutionTypes[pollutionType] ?? _pollutionTypes['Other']!;
    final base64Images = List<String>.from(markerData['images'] ?? []);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: pollutionConfig['color'].withOpacity(0.1),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(pollutionConfig['icon'], color: pollutionConfig['color'], size: 24),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$pollutionType - ${markerData['severity'] ?? 'Unknown'}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Reported by ${isMyMarker ? "you" : addedByName}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Severity: ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getSeverityColor(markerData['severity'] ?? 'Low'),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                markerData['severity'] ?? 'Low',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        if (markerData['description'] != null && markerData['description'].isNotEmpty) ...[
                          Text(
                            'Description',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              markerData['description'],
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                          SizedBox(height: 16),
                        ],
                        if (base64Images.isNotEmpty) ...[
                          Text(
                            'Photos',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 8),
                          Container(
                            height: 150,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: base64Images.length,
                              itemBuilder: (context, index) {
                                return Container(
                                  margin: EdgeInsets.only(right: 8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: _buildBase64Image(base64Images[index]),
                                  ),
                                );
                              },
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.image_not_supported, color: Colors.grey[400]),
                                SizedBox(width: 8),
                                Text(
                                  'No photos available',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (!isMyMarker && addedById.isNotEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: FriendButton(
                                userId: addedById,
                                userName: addedByName,
                                isMyMarker: isMyMarker,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: MessageButton(
                                recipientId: addedById,
                                recipientName: addedByName,
                                foodMarkerId: markerId,
                                foodName: '$pollutionType Report',
                                isMyMarker: isMyMarker,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('Close'),
                            ),
                          ),
                          if (isMyMarker) ...[
                            SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  final shouldDelete = await _showDeleteConfirmationDialog(
                                    '$pollutionType Report',
                                    addedByName,
                                    isMyMarker
                                  );
                                  if (shouldDelete == true) {
                                    await _deleteMarker(markerId, '$pollutionType Report');
                                  }
                                },
                                icon: Icon(Icons.delete, size: 18),
                                label: Text('Delete'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBase64Image(String base64String) {
    try {
      final bytes = base64Decode(base64String);
      return Image.memory(
        bytes,
        width: 150,
        height: 150,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 150,
            height: 150,
            color: Colors.grey[200],
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, color: Colors.grey[400]),
                Text(
                  'Image Error',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      return Container(
        width: 150,
        height: 150,
        color: Colors.grey[200],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, color: Colors.grey[400]),
            Text(
              'Invalid Image',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      );
    }
  }

  // UI helpers & nav
  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'Low': return Colors.green;
      case 'Medium': return Colors.orange;
      case 'High': return Colors.red;
      case 'Critical': return Colors.red[900]!;
      default: return Colors.grey;
    }
  }

  Future<bool?> _showDeleteConfirmationDialog(String reportName, String addedByName, bool isMyMarker) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Report'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to delete this pollution report?'),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.report_problem, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            reportName,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.grey[600], size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Reported by: ${isMyMarker ? "You" : addedByName}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Text(
                'This action cannot be undone and will remove the report for all users.',
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete, size: 16),
                  SizedBox(width: 4),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteMarkerFromCluster(String firebaseKey, String reportName) async {
    print('Attempting to delete marker with Firebase key: $firebaseKey');
    
    if (_firebaseConnected && _pollutionMarkersRef != null) {
      try {
        // Delete from Firebase
        await _pollutionMarkersRef!.child(firebaseKey).remove();
        print('Successfully deleted from Firebase: $firebaseKey');
        
        // Remove from local cache immediately
        _markerDataCache.remove(firebaseKey);
        
        // Remove from markers set immediately
        _safeSetState(() {
          _markers.removeWhere((marker) => marker.markerId.value == firebaseKey);
        });
        
        _showSnackBar('Report "$reportName" deleted successfully', Colors.green);
        
        // The real-time listener will automatically rebuild the clusters
        // But we can also force a refresh to be sure
        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted) {
            _loadPollutionMarkers();
          }
        });
        
      } catch (e) {
        print('Failed to delete marker: $e');
        _showSnackBar('Failed to delete marker: $e', Colors.red);
      }
    } else {
      // Local deletion only
      _safeSetState(() {
        _markers.removeWhere((marker) => marker.markerId.value == firebaseKey);
        _markerDataCache.remove(firebaseKey);
      });
      _showSnackBar('Report "$reportName" deleted locally', Colors.orange);
    }
  }

  Future<void> _deleteMarker(String markerId, String reportName) async {
    await _deleteMarkerFromCluster(markerId, reportName);
  }

  Future<void> _centerOnCurrentLocation() async {
    if (_currentLocation != null && _mapController != null) {
      await _animateToLocation(_currentLocation!);
    }
  }

  Future<void> _refreshData() async {
    _safeSetState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    await _setupLocation();
    if (_firebaseConnected) {
      await _loadPollutionMarkers();
    }
    _safeSetState(() {
      _isLoading = false;
    });
  }

  Future<void> _signOut() async {
    final shouldSignOut = await _showSignOutDialog();
    if (shouldSignOut == true) {
      try {
        await _authService.signOut();
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      } catch (e) {
        _showSnackBar('Failed to sign out: $e', Colors.red);
      }
    }
  }

  Future<bool?> _showSignOutDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.logout, color: Colors.red),
              SizedBox(width: 8),
              Text('Sign Out'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to sign out?'),
              SizedBox(height: 8),
              Text(
                'You will need to sign in again to access the app.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('Sign Out'),
            ),
          ],
        );
      },
    );
  }

  void _setError(String message) {
    _safeSetState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  bool _isPollutionMarker(Marker marker) => true;
  int _getPollutionMarkerCount() => _markers.where((marker) => _isPollutionMarker(marker)).length;

  // Profile, Info, NavBar, etc...
  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.red[700],
                child: Text(
                  _currentUserName.isNotEmpty ? _currentUserName[0].toUpperCase() : '?',
                  style: TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(height: 12),
              Text(
                _currentUserName,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_authService.currentUserEmail != null) ...[
                SizedBox(height: 4),
                Text(
                  _authService.currentUserEmail!,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _signOut,
                  icon: Icon(Icons.logout, color: Colors.white),
                  label: Text('Sign Out', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAppInfoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info, color: Colors.red[700]),
              SizedBox(width: 8),
              Text('How to Use'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoListItem('🟠', 'Orange markers = Pollution you reported'),
              _buildInfoListItem('🔴', 'Colored markers = Community pollution reports'),
              _buildInfoListItem('🔵', 'Blue dot = Your live location (Google Maps)'),
              _buildInfoListItem('⚠️', 'Tap "Report Pollution" to mark pollution'),
              _buildInfoListItem('👁️', 'Tap any marker to view pollution details'),
              _buildInfoListItem('🌈', 'Markers are color-coded by pollution type'),
              _buildInfoListItem('🔥', 'Severity levels: Low, Medium, High, Critical'),
              _buildInfoListItem('👥', 'Message and friend other reporters'),
              _buildInfoListItem('🗑️', 'Delete any pollution report (yours or others)'),
              _buildInfoListItem('📍', 'Tap location button to center on you'),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person,
                      size: 16,
                      color: Colors.red[700],
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Signed in as: $_currentUserName',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Got it!'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoListItem(String icon, String text) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 3),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Text(
                icon, 
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              text, 
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _updateRadiusForUnitChange(bool newUseMiles) {
    if (newUseMiles != _useMiles) {
      if (newUseMiles) {
        // Converting from km to miles
        _radius = (_radius * 0.621371).clamp(_minRadius, _maxRadiusMiles);
      } else {
        // Converting from miles to km
        _radius = (_radius / 0.621371).clamp(_minRadius, _maxRadiusKm);
      }
      _radiusController.text = _radius.toStringAsFixed(1);
    }
  }

  void _showListView() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Filter and sort markers
            final filteredMarkers = _markers.where((marker) {
              final markerData = _getMarkerData(marker.markerId.value);
              if (markerData == null) return false;
              
              // Calculate distance
              final distanceKm = _calculateDistance(
                _currentLocation?.latitude ?? 0,
                _currentLocation?.longitude ?? 0,
                markerData['latitude'] ?? 0,
                markerData['longitude'] ?? 0,
              );
              final distance = _useMiles ? distanceKm * 0.621371 : distanceKm;
              
              // Check if within radius
              if (distance > _radius) return false;
              
              // Apply search filter
              if (_searchQuery.isEmpty) return true;
              
              final pollutionType = (markerData['pollutionType'] ?? '').toLowerCase();
              final description = (markerData['description'] ?? '').toLowerCase();
              final addedBy = (markerData['addedByName'] ?? '').toLowerCase();
              final severity = (markerData['severity'] ?? '').toLowerCase();
              final query = _searchQuery.toLowerCase();
              
              return pollutionType.contains(query) || 
                     description.contains(query) || 
                     addedBy.contains(query) ||
                     severity.contains(query);
            }).toList();

            // Sort markers
            filteredMarkers.sort((a, b) {
              final aData = _getMarkerData(a.markerId.value);
              final bData = _getMarkerData(b.markerId.value);
              if (aData == null || bData == null) return 0;

              switch (_sortBy) {
                case 'distance':
                  final aDistance = _calculateDistance(
                    _currentLocation?.latitude ?? 0,
                    _currentLocation?.longitude ?? 0,
                    aData['latitude'] ?? 0,
                    aData['longitude'] ?? 0,
                  );
                  final bDistance = _calculateDistance(
                    _currentLocation?.latitude ?? 0,
                    _currentLocation?.longitude ?? 0,
                    bData['latitude'] ?? 0,
                    bData['longitude'] ?? 0,
                  );
                  return aDistance.compareTo(bDistance);
                
                case 'recent':
                  final aTimestamp = aData['timestamp'] ?? 0;
                  final bTimestamp = bData['timestamp'] ?? 0;
                  return bTimestamp.compareTo(aTimestamp);
                
                case 'name':
                  final aName = (aData['pollutionType'] ?? '').toLowerCase();
                  final bName = (bData['pollutionType'] ?? '').toLowerCase();
                  return aName.compareTo(bName);
                
                default:
                  return 0;
              }
            });

            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Pollution Reports',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[700],
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  'km',
                                  style: TextStyle(
                                    color: !_useMiles ? Colors.red[700] : Colors.grey,
                                    fontWeight: !_useMiles ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                Switch(
                                  value: _useMiles,
                                  onChanged: (value) {
                                    setState(() {
                                      _updateRadiusForUnitChange(value);
                                      _useMiles = value;
                                    });
                                  },
                                  activeColor: Colors.red[700],
                                ),
                                Text(
                                  'mi',
                                  style: TextStyle(
                                    color: _useMiles ? Colors.red[700] : Colors.grey,
                                    fontWeight: _useMiles ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Radius: ${_radius.toStringAsFixed(1)} ${_useMiles ? 'mi' : 'km'}',
                                        style: TextStyle(
                                          color: Colors.red[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Container(
                                        width: 80,
                                        child: TextField(
                                          controller: _radiusController,
                                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                            border: OutlineInputBorder(),
                                            suffixText: _useMiles ? 'mi' : 'km',
                                          ),
                                          onChanged: (value) {
                                            final newRadius = double.tryParse(value);
                                            if (newRadius != null && newRadius > 0) {
                                              setState(() {
                                                _radius = newRadius.clamp(
                                                  _minRadius,
                                                  _useMiles ? _maxRadiusMiles : _maxRadiusKm
                                                );
                                                _radiusController.text = _radius.toStringAsFixed(1);
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Slider(
                                    value: _radius,
                                    min: _minRadius,
                                    max: _useMiles ? _maxRadiusMiles : _maxRadiusKm,
                                    divisions: 100,
                                    activeColor: Colors.red[700],
                                    inactiveColor: Colors.red[700]!.withOpacity(0.2),
                                    onChanged: (value) {
                                      setState(() {
                                        _radius = value;
                                        _radiusController.text = value.toStringAsFixed(1);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _sortBy,
                                decoration: InputDecoration(
                                  labelText: 'Sort by',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'distance',
                                    child: Text('Distance'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'recent',
                                    child: Text('Most Recent'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'name',
                                    child: Text('Type'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _sortBy = value;
                                    });
                                  }
                                },
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                decoration: InputDecoration(
                                  labelText: 'Search',
                                  prefixIcon: Icon(Icons.search),
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filteredMarkers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No reports found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (_searchQuery.isNotEmpty || _radius < (_useMiles ? 50.0 : 80.0))
                                Text(
                                  'Try adjusting your search or radius',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.all(16),
                          itemCount: filteredMarkers.length,
                          itemBuilder: (context, index) {
                            final marker = filteredMarkers[index];
                            final markerData = _getMarkerData(marker.markerId.value);
                            if (markerData == null) return SizedBox.shrink();

                            final distanceKm = _calculateDistance(
                              _currentLocation?.latitude ?? 0,
                              _currentLocation?.longitude ?? 0,
                              markerData['latitude'] ?? 0,
                              markerData['longitude'] ?? 0,
                            );
                            final distance = _useMiles ? distanceKm * 0.621371 : distanceKm;
                            final unit = _useMiles ? 'mi' : 'km';
                            final isMyMarker = markerData['addedBy'] == _currentUserId;
                            final pollutionType = markerData['pollutionType'] ?? 'Other';
                            final pollutionConfig = _pollutionTypes[pollutionType] ?? _pollutionTypes['Other']!;

                            return Card(
                              margin: EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                onTap: () {
                                  Navigator.pop(context);
                                  // Check if this is a cluster marker
                                  if (markerData['isCluster'] == true) {
                                    _showClusterDetailsDialog(marker.markerId.value, markerData['clusterMarkers'] ?? []);
                                  } else {
                                    _onMarkerTapped(marker.markerId.value, markerData);
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            pollutionConfig['icon'],
                                            color: pollutionConfig['color'],
                                            size: 20,
                                          ),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  markerData['isCluster'] == true 
                                                      ? '${markerData['clusterCount'] ?? 0} Pollution Reports'
                                                      : pollutionType,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                if (markerData['isCluster'] != true)
                                                  Text(
                                                    'Severity: ${markerData['severity'] ?? 'Unknown'}',
                                                    style: TextStyle(
                                                      color: _getSeverityColor(markerData['severity'] ?? 'Low'),
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red[700]!.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '${distance.toStringAsFixed(1)} $unit',
                                              style: TextStyle(
                                                color: Colors.red[700],
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (markerData['isCluster'] != true && 
                                          markerData['description'] != null && 
                                          markerData['description'].isNotEmpty) ...[
                                        SizedBox(height: 8),
                                        Text(
                                          markerData['description'],
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                      SizedBox(height: 8),
                                      Row(
                                        children: [
                                          if (markerData['isCluster'] != true) ...[
                                            Icon(
                                              Icons.person,
                                              size: 16,
                                              color: Colors.grey[600],
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              markerData['addedByName'] ?? 'Unknown User',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                          Spacer(),
                                          if (markerData['isCluster'] == true)
                                            Text(
                                              'Tap to view all reports',
                                              style: TextStyle(
                                                color: Colors.red[700],
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            )
                                          else if (isMyMarker)
                                            IconButton(
                                              icon: Icon(
                                                Icons.delete_outline,
                                                color: Colors.red,
                                                size: 20,
                                              ),
                                              onPressed: () async {
                                                final shouldDelete = await _showDeleteConfirmationDialog(
                                                  pollutionType,
                                                  markerData['addedByName'] ?? 'Unknown User',
                                                  true
                                                );
                                                if (shouldDelete == true) {
                                                  await _deleteMarker(marker.markerId.value, pollutionType);
                                                  Navigator.pop(context);
                                                }
                                              },
                                              tooltip: 'Delete',
                                            ),
                                          if (markerData['isCluster'] != true &&
                                              markerData['images'] != null &&
                                              (markerData['images'] as List).isNotEmpty)
                                            Text(
                                              '${(markerData['images'] as List).length} photos',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Map<String, dynamic>? _getMarkerData(String markerId) {
    // First try to get from cache
    if (_markerDataCache.containsKey(markerId)) {
      return _markerDataCache[markerId];
    }

    // If not in cache, try to get from marker info (basic data)
    try {
      final marker = _markers.firstWhere(
        (marker) => marker.markerId.value == markerId,
      );
      
      // Parse basic data from marker info
      final titleParts = marker.infoWindow.title?.split(' - ') ?? [];
      final pollutionType = titleParts.isNotEmpty ? titleParts[0] : 'Other';
      final severity = titleParts.length > 1 ? titleParts[1] : 'Unknown';
      
      final snippetParts = marker.infoWindow.snippet?.split('•') ?? [];
      final addedByPart = snippetParts.isNotEmpty ? snippetParts[0].trim() : '';
      final addedByName = addedByPart.replaceAll('Reported by ', '').trim();

      final markerData = {
        'pollutionType': pollutionType,
        'severity': severity,
        'description': '', // Will be empty without Firebase data
        'latitude': marker.position.latitude,
        'longitude': marker.position.longitude,
        'addedByName': addedByName,
        'images': [], // Will be empty without Firebase data
        'addedBy': '', // Will be empty without Firebase data
        'timestamp': 0, // Will be 0 without Firebase data
      };

      // Try to get full data from Firebase and update cache
      if (_firebaseConnected && _pollutionMarkersRef != null) {
        _pollutionMarkersRef!.child(markerId).get().then((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.value as Map<dynamic, dynamic>;
            final fullMarkerData = Map<String, dynamic>.from(data);
            _markerDataCache[markerId] = fullMarkerData;
          }
        });
      }

      return markerData;
    } catch (e) {
      return null;
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * math.pi / 180;
  }

  // Bottom navigation bar with three tabs
  Widget _buildBottomNavigation() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => FoodLocatorScreen(),
                  ),
                );
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.map,
                      color: Color(0xFF00A74C),
                      size: 24,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Food Map',
                      style: TextStyle(
                        color: Color(0xFF00A74C),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.grey[300],
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => EcoChallengesScreen(),
                  ),
                );
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.eco,
                      color: Colors.green[600],
                      size: 24,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Eco Challenges',
                      style: TextStyle(
                        color: Colors.green[600],
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.grey[300],
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                _showSnackBar('You are already on the Pollution Tracker screen', Colors.red[700]!);
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red[700]!.withOpacity(0.1),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(20),
                  ),
                  border: Border.all(
                    color: Colors.red[700]!.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.report_problem,
                      color: Colors.red[700],
                      size: 24,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Pollution',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
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

  // The main build method
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: Row(
          children: [
            Icon(Icons.report_problem, color: Colors.red[700]),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Pollution Tracker',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.list, color: Colors.red[700]),
            onPressed: _showListView,
            tooltip: 'List View',
          ),
          StreamBuilder<int>(
            stream: _friendsService.getPendingRequestsCount(),
            builder: (context, snapshot) {
              final pendingCount = snapshot.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.people, color: Colors.red[700]),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => FriendsScreen(),
                        ),
                      );
                    },
                    tooltip: 'Friends',
                  ),
                  if (pendingCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          pendingCount > 99 ? '99+' : pendingCount.toString(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          StreamBuilder<int>(
            stream: _messagingService.getUnreadCount(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.chat_bubble_outline, color: Colors.red[700]),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ConversationsScreen(),
                        ),
                      );
                    },
                    tooltip: 'Messages',
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _showProfileMenu(context),
              child: CircleAvatar(
                backgroundColor: Colors.red[700],
                child: Text(
                  _currentUserName.isNotEmpty ? _currentUserName[0].toUpperCase() : '?',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading 
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.red[700]),
                SizedBox(height: 16),
                Text('Getting your location...'),
                SizedBox(height: 8),
                Text(
                  'Please allow location access',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        : _errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red),
                    SizedBox(height: 16),
                    Text(
                      'Oops! Something went wrong',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      style: TextStyle(fontSize: 16, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _refreshData,
                      icon: Icon(Icons.refresh),
                      label: Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                  },
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      _currentLocation?.latitude ?? 37.7749,
                      _currentLocation?.longitude ?? -122.4194,
                    ),
                    zoom: 16.0,
                  ),
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  compassEnabled: true,
                  mapType: MapType.normal,
                  zoomControlsEnabled: false,
                ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton.extended(
                    onPressed: _addPollutionMarker,
                    icon: Icon(Icons.report_problem),
                    label: Text('Report Pollution', style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                    heroTag: "add_pollution",
                  ),
                ),
              ],
            ),
      bottomNavigationBar: ModernBottomNav(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }
}