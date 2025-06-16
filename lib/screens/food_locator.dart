import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../services/friends_service.dart';
import '../screens/conversations_screen.dart';
import '../screens/friends_screen.dart';
import '../widgets/message_button.dart';
import '../widgets/friend_button.dart';
import '../screens/eco_challenges_screen.dart';
import '../screens/pollution_tracker_screen.dart';
import '../services/gemini_service.dart';
import '../widgets/modern_bottom_nav.dart';
import '../widgets/review_widget.dart';
import '../services/review_service.dart';
import '../widgets/tab_page_transition.dart';






class FoodLocatorScreen extends StatefulWidget {
  const FoodLocatorScreen({super.key});

  @override
  _FoodLocatorScreenState createState() => _FoodLocatorScreenState();
}

class _FoodLocatorScreenState extends State<FoodLocatorScreen> {
  GoogleMapController? _mapController;
  final Location _location = Location();
  LocationData? _currentLocation;
  final Set<Marker> _markers = {};
  bool _isLoading = true;
  String _errorMessage = '';
  DatabaseReference? _database;
  DatabaseReference? _foodMarkersRef;
  bool _firebaseConnected = false;
  final ImagePicker _imagePicker = ImagePicker();
  final AuthService _authService = AuthService();
  final MessagingService _messagingService = MessagingService();
  final FriendsService _friendsService = FriendsService();
  final GeminiService _geminiService = GeminiService();
  final ReviewService _reviewService = ReviewService();
  bool _aiAnalysisComplete = false;
  bool _useMiles = true;
  String _searchQuery = '';
  String _sortBy = 'distance';
  double _radius = 10.0; // Default radius in miles
  final TextEditingController _radiusController = TextEditingController();
  bool _isAnalyzing = false;
  final int _currentIndex = 0;
  bool _isCenteredOnUser = true;

  // Constants for radius limits
  static const double _maxRadiusMiles = 100.0;
  static const double _maxRadiusKm = 160.0;
  static const double _minRadius = 0.1;

  String get _currentUserId => _authService.currentUserId ?? 'unknown';
  String get _currentUserName => _authService.currentUserDisplayName;
  bool get _isAnonymous => false;
  final Map<String, Map<String, dynamic>> _markerDataCache = {};
  @override
  void initState() {
    super.initState();
    _initializeApp();
    _radiusController.text = _radius.toString();
  }

  @override
void dispose() {
  _radiusController.dispose();
  _markerDataCache.clear();
  super.dispose();
}

  Future<void> _initializeApp() async {
    await _initializeFirebase();
    await _setupLocation();
    if (_firebaseConnected) {
      await _validateAndCleanupMarkers();
      await _loadFoodMarkers();
      _setupRealtimeListener();
    }
  }

  Future<void> _initializeFirebase() async {
    try {
      print('Initializing Firebase...');
      _database = FirebaseDatabase.instance.ref();
      print('Database reference created');
      _foodMarkersRef = _database!.child('foodMarkers');
      print('Food markers reference created');
      _firebaseConnected = true;
      print('Firebase connected successfully');
    } catch (e, stackTrace) {
      print('Firebase connection failed: $e');
      print('Stack trace: $stackTrace');
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
      setState(() {
        _currentLocation = locationData;
        _isLoading = false;
      });
      _location.onLocationChanged.listen((LocationData newLocation) {
        setState(() {
          _currentLocation = newLocation;
        });
      });
    } catch (e) {
      _setError('Failed to get location: $e');
    }
  }

  Future<void> _loadFoodMarkers() async {
    if (!_firebaseConnected || _foodMarkersRef == null) {
      print('Cannot load food markers: Firebase not connected or reference is null');
      return;
    }
    try {
      print('Attempting to load food markers...');
      final snapshot = await _foodMarkersRef!.get();
      print('Snapshot exists: ${snapshot.exists}');
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        print('Loaded ${data.length} food markers');
        print('First marker data: ${data.isNotEmpty ? data.values.first : 'No markers'}');
        _buildMarkersFromData(data);
      } else {
        print('No food markers found in database');
      }
    } catch (e, stackTrace) {
      print('Error loading food markers: $e');
      print('Stack trace: $stackTrace');
      _showSnackBar('Failed to load community markers', Colors.orange);
    }
  }

  void _setupRealtimeListener() {
    if (!_firebaseConnected || _foodMarkersRef == null) return;
    _foodMarkersRef!.onValue.listen((DatabaseEvent event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        _buildMarkersFromData(data);
      } else {
        setState(() {
          _markers.removeWhere((marker) => _isFoodMarker(marker));
        });
      }
    }, onError: (error) {
      _showSnackBar('Real-time sync error', Colors.red);
    });
  }

  void _buildMarkersFromData(Map<dynamic, dynamic> data) {
  setState(() {
    _markers.removeWhere((marker) => _isFoodMarker(marker));
    _approximateCircles.clear();
    _markerDataCache.clear(); // Clear the cache
    
    data.forEach((key, value) {
      try {
        final markerData = Map<String, dynamic>.from(value);
        final isMyMarker = markerData['addedBy'] == _currentUserId;
        final addedByName = markerData['addedByName'] ?? 'Unknown User';
        
        // Store the complete marker data in cache
        _markerDataCache[key] = markerData;
        
        // Safely get location data with null checks
        final locationData = markerData['location'];
        if (locationData == null) {
          print('Warning: Location data is null for marker $key');
          return; // Skip this marker
        }
        
        final latitude = locationData['latitude'];
        final longitude = locationData['longitude'];
        
        if (latitude == null || longitude == null) {
          print('Warning: Latitude or longitude is null for marker $key');
          return; // Skip this marker
        }
        
        // Get the original location
        final originalLatLng = LatLng(
          latitude.toDouble(),
          longitude.toDouble(),
        );
        
        // For other users' markers, use approximate location
        final displayLatLng = isMyMarker 
          ? originalLatLng 
          : _generateApproximateLocation(originalLatLng, 0.5); // 500m radius
        
        // Add marker
        _markers.add(
          Marker(
            markerId: MarkerId(key),
            position: displayLatLng,
            infoWindow: InfoWindow(
              title: markerData['name'] ?? 'Unknown Food',
              snippet: isMyMarker 
                ? 'Added by you • Tap to view details' 
                : 'Added by $addedByName • Approximate location • Tap to view details',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isMyMarker ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueRed
            ),
            onTap: () => _onMarkerTapped(key, markerData),
          ),
        );
        
        // Add circle for approximate locations of other users' markers
        if (!isMyMarker) {
          _approximateCircles.add(
            Circle(
              circleId: CircleId('approximate_$key'),
              center: displayLatLng,
              radius: 500, // 500 meters
              fillColor: Colors.red.withOpacity(0.1),
              strokeColor: Colors.red.withOpacity(0.3),
              strokeWidth: 1,
            ),
          );
        }
      } catch (e, stackTrace) {
        print('Error processing marker $key: $e');
        print('Stack trace: $stackTrace');
      }
    });
  });
}

  Future<void> _addFoodMarker() async {
    if (_currentLocation == null) {
      _showSnackBar('Location not available. Please wait for GPS.', Colors.red);
      return;
    }
    final foodData = await _showFoodInputDialog();
    if (foodData == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Processing food marker...'),
            Text(
              'Converting images...',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
    try {
      final markerId = 'food_${DateTime.now().millisecondsSinceEpoch}';
      List<String> base64Images = [];
      for (int i = 0; i < foodData['images'].length; i++) {
        final imageFile = foodData['images'][i] as File;
        final base64String = await _convertImageToBase64(imageFile);
        if (base64String != null) {
          base64Images.add(base64String);
        }
      }
      final markerData = {
        'name': foodData['name'],
        'description': foodData['description'],
        'location': {
          'latitude': _currentLocation!.latitude!,
          'longitude': _currentLocation!.longitude!,
        },
        'timestamp': ServerValue.timestamp,
        'addedBy': _currentUserId,
        'addedByName': _currentUserName,
        'images': base64Images,
        'imageCount': base64Images.length,
      };
      // In your _addFoodMarker method, after creating markerData and before setState, add:

// ... existing code for creating markerData ...

// Add to cache
_markerDataCache[markerId] = markerData;

setState(() {
  _markers.add(
    Marker(
      markerId: MarkerId(markerId),
      position: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
      infoWindow: InfoWindow(
        title: foodData['name'],
        snippet: 'Added by you • Tap to view details',
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      onTap: () => _onMarkerTapped(markerId, markerData),
    ),
  );
});

// ... rest of the method ...
      if (_firebaseConnected && _foodMarkersRef != null) {
        await _foodMarkersRef!.child(markerId).set(markerData);
        Navigator.of(context).pop();
        _showSnackBar('Food marker "${foodData['name']}" shared with community!', const Color(0xFF00A74C));
      } else {
        Navigator.of(context).pop();
        _showSnackBar('Marker added locally (offline mode)', Colors.orange);
      }
    } catch (e) {
      Navigator.of(context).pop();
      _showSnackBar('Failed to save marker: $e', Colors.red);
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

 Future<Map<String, dynamic>?> _showFoodInputDialog() async {
  String foodName = '';
  String description = '';
  List<File> selectedImages = [];
  
  // Reset AI analysis state
  _aiAnalysisComplete = false;
  
  // Create controllers for the text fields
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
            ),
            child: Container(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.92,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fixed header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.restaurant, color: Color(0xFF00A74C)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Add Food Location',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                          softWrap: true,
                          overflow: TextOverflow.visible,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Tell us about the food at your location:'),
                  const SizedBox(height: 16),
                  
                  // Scrollable content
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: nameController,
                              onChanged: (value) => foodName = value,
                              decoration: const InputDecoration(
                                labelText: 'Food Name *',
                                hintText: 'e.g., Pizza, Burger, Tacos',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.fastfood),
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: descriptionController,
                              onChanged: (value) => description = value,
                              decoration: const InputDecoration(
                                labelText: 'Description *',
                                hintText: 'Describe the food, price, availability...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.description),
                              ),
                              maxLines: 3,
                              textCapitalization: TextCapitalization.sentences,
                            ),
                            const SizedBox(height: 16),
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
                                        child: const Center(
                                          child: SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A74C)),
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
                                                  print('Starting AI analysis...');
                                                  final analysis = await _geminiService.analyzeFoodImage(selectedImages[0]);
                                                  print('Analysis complete: $analysis');
                                                  
                                                  if (analysis['name'] == 'Error') {
                                                    throw Exception(analysis['description']);
                                                  }

                                                  if (analysis['name'] == 'NO_FOOD_DETECTED') {
                                                    showDialog(
                                                      context: context,
                                                      builder: (context) => AlertDialog(
                                                        title: const Row(
                                                          children: [
                                                            Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                                            SizedBox(width: 8),
                                                            Text('No Food Detected'),
                                                          ],
                                                        ),
                                                        content: const Text('The AI could not detect any food items in the image. Please try again with a clearer image of food items.'),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.of(context).pop(),
                                                            child: const Text('OK'),
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
                                                  
                                                  nameController.text = analysis['name'] ?? '';
                                                  descriptionController.text = '${analysis['description']}\n\nCharacteristics: ${analysis['characteristics']}';
                                                  
                                                  foodName = nameController.text;
                                                  description = descriptionController.text;
                                                  
                                                  // Mark analysis as complete
                                                  setDialogState(() {
                                                    _isAnalyzing = false;
                                                    _aiAnalysisComplete = true;
                                                  });
                                                  
                                                  // Show warning message about verifying content
                                                  showDialog(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      title: const Row(
                                                        children: [
                                                          Icon(Icons.check_circle, color: Color(0xFF00A74C)),
                                                          SizedBox(width: 8),
                                                          Text('Analysis Complete'),
                                                        ],
                                                      ),
                                                      content: const Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            'The AI has generated a description and title for your food item. Please carefully review and edit the content to ensure it accurately represents your food item.',
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
                                                          Text('• Verify the food name is correct'),
                                                          Text('• Check that the description is accurate'),
                                                          Text('• Make sure all details are precise'),
                                                        ],
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.of(context).pop(),
                                                          child: const Text('I Will Review'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('AI analysis complete!'),
                                                      backgroundColor: Color(0xFF00A74C),
                                                      duration: Duration(seconds: 2),
                                                    ),
                                                  );
                                                } catch (e) {
                                                  print('Error during AI analysis: $e');
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('Failed to analyze image: $e'),
                                                      backgroundColor: Colors.red,
                                                      duration: const Duration(seconds: 3),
                                                    ),
                                                  );
                                                  // Reset analysis state on error
                                                  setDialogState(() {
                                                    _isAnalyzing = false;
                                                  });
                                                }
                                              },
                                        icon: const Icon(Icons.auto_awesome),
                                        label: const Text('Let AI Write Description & Title'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF00A74C),
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor: Colors.grey[300],
                                          disabledForegroundColor: Colors.grey[600],
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            const Text(
                              'Photos * (At least 1 required)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            if (selectedImages.isNotEmpty) ...[
                              SizedBox(
                                height: 100,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: selectedImages.length,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      margin: const EdgeInsets.only(right: 8),
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
                                                padding: const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: Colors.red,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Icon(
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
                              const SizedBox(height: 8),
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
                                    icon: const Icon(Icons.camera_alt),
                                    label: const Text('Camera'),
                                  ),
                                ),
                                const SizedBox(width: 8),
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
                                    icon: const Icon(Icons.photo_library),
                                    label: const Text('Gallery'),
                                  ),
                                ),
                              ],
                            ),
                            if (selectedImages.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Please add at least one photo (camera or gallery)',
                                  style: TextStyle(
                                    color: Colors.red[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            // Add some extra padding at the bottom for better scrolling
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Fixed footer with action buttons
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: nameController.text.trim().isNotEmpty &&
                                 descriptionController.text.trim().isNotEmpty &&
                                 selectedImages.isNotEmpty
                            ? () {
                                Navigator.of(context).pop({
                                  'name': nameController.text.trim(),
                                  'description': descriptionController.text.trim(),
                                  'images': selectedImages,
                                });
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00A74C),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Add Marker'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

  Future<void> _onMarkerTapped(String markerId, Map<String, dynamic> markerData) async {
    print('DEBUG: _onMarkerTapped called with markerId: $markerId');
    print('DEBUG: markerData: $markerData');
    await _showMarkerDetailsDialog(markerId, markerData);
  }

  Future<void> _showMarkerDetailsDialog(String markerId, Map<String, dynamic> markerData) async {
    print('DEBUG: _showMarkerDetailsDialog called with markerId: $markerId');
    print('DEBUG: Full markerData in dialog: $markerData');
    final isMyMarker = markerData['addedBy'] == _currentUserId;
    final addedByName = markerData['addedByName'] ?? 'Unknown User';
    final addedById = markerData['addedBy'] ?? '';
    final base64Images = List<String>.from(markerData['images'] ?? []);
    print('DEBUG: base64Images length: ${base64Images.length}');
    print('DEBUG: Description: ${markerData['description']}');
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          child: Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * 0.92,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE6F8EE),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.restaurant, color: Color(0xFF00A74C), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              markerData['name'] ?? 'Unknown Food',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Added by ${isMyMarker ? "you" : addedByName}',
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
                        icon: const Icon(Icons.close, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMyMarker) ...[
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange[200]!),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on, color: Colors.orange[700], size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'This location is approximate for privacy',
                                      style: TextStyle(
                                        color: Colors.orange[900],
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (markerData['description'] != null && markerData['description'].isNotEmpty) ...[
                            const Text(
                              'Description',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(markerData['description']),
                            const SizedBox(height: 16),
                          ],
                          if (base64Images.isNotEmpty) ...[
                            const Text(
                              'Photos',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 150,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: base64Images.length,
                                itemBuilder: (context, index) {
                                  return Container(
                                    margin: const EdgeInsets.only(right: 8),
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
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.image_not_supported, color: Colors.grey[400]),
                                  const SizedBox(width: 8),
                                  Text(
                                    'No photos available',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                          const Text(
                            'User Reviews',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ReviewWidget(
                            targetUserId: addedById,
                            targetUserName: addedByName,
                            showReviewButton: !isMyMarker,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(32),
                      bottomRight: Radius.circular(32),
                    ),
                  ),
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: MessageButton(
                                recipientId: addedById,
                                recipientName: addedByName,
                                foodMarkerId: markerId,
                                foodName: markerData['name'] ?? 'Unknown Food',
                                isMyMarker: isMyMarker,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                textStyle: const TextStyle(fontSize: 14),
                              ),
                              child: const Text('Close'),
                            ),
                          ),
                          if (isMyMarker) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  final shouldDelete = await _showDeleteConfirmationDialog(
                                    markerData['name'] ?? 'Unknown Food',
                                    addedByName,
                                    isMyMarker
                                  );
                                  if (shouldDelete == true) {
                                    await _deleteMarker(markerId, markerData['name'] ?? 'Unknown Food');
                                  }
                                },
                                icon: const Icon(Icons.delete, size: 18),
                                label: const Text('Delete', style: TextStyle(fontSize: 14)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
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

  Future<bool?> _showDeleteConfirmationDialog(String markerName, String addedByName, bool isMyMarker) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Marker'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to delete this food marker?'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
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
                        const Icon(Icons.restaurant, color: Color(0xFF00A74C), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            markerName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.grey[600], size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Added by: ${isMyMarker ? "You" : addedByName}',
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
              const SizedBox(height: 12),
              Text(
                'This action cannot be undone and will remove the marker for all users.',
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
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Row(
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

  Future<void> _deleteMarker(String markerId, String markerName) async {
  setState(() {
    _markers.removeWhere((marker) => marker.markerId.value == markerId);
    _markerDataCache.remove(markerId); // Remove from cache
  });
  if (_firebaseConnected && _foodMarkersRef != null) {
    try {
      await _foodMarkersRef!.child(markerId).remove();
      _showSnackBar('Marker "$markerName" deleted successfully', const Color(0xFF00A74C));
    } catch (e) {
      _showSnackBar('Failed to delete from server: $e', Colors.red);
    }
  } else {
    _showSnackBar('Marker "$markerName" deleted locally', Colors.orange);
  }
}

  Future<void> _centerOnCurrentLocation() async {
    if (_currentLocation != null && _mapController != null) {
      await _animateToLocation(_currentLocation!);
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
      setState(() {
        _isCenteredOnUser = true;
      });
    }
  }

  void _onCameraMove(CameraPosition position) {
    if (_currentLocation != null) {
      final distance = _calculateDistance(
        position.target.latitude,
        position.target.longitude,
        _currentLocation!.latitude!,
        _currentLocation!.longitude!,
      );
      // If we're more than 100 meters away from user location, show the button
      setState(() {
        _isCenteredOnUser = distance < 0.1; // 0.1 km = 100 meters
      });
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    await _setupLocation();
    if (_firebaseConnected) {
      await _loadFoodMarkers();
    }
    setState(() {
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
          title: const Row(
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
              const Text('Are you sure you want to sign out?'),
              const SizedBox(height: 8),
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
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );
  }

  // ========== Modern Profile Sheet ==========
  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: const Color(0xFF00A74C),
                child: Text(
                  _currentUserName.isNotEmpty ? _currentUserName[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _currentUserName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_authService.currentUserEmail != null) ...[
                const SizedBox(height: 4),
                Text(
                  _authService.currentUserEmail!,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text('Sign Out', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _setError(String message) {
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool _isFoodMarker(Marker marker) {
    return true;
  }

  int _getFoodMarkerCount() {
    return _markers.where((marker) => _isFoodMarker(marker)).length;
  }

  // App Info Dialog (still accessible, call from menu or button if you want)
  void _showAppInfoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info, color: Colors.blue),
              SizedBox(width: 8),
              Text('How to Use'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoListItem('🟠', 'Orange markers = Food spots you added'),
              _buildInfoListItem('🔴', 'Red markers = Community food spots'),
              _buildInfoListItem('🔵', 'Blue dot = Your live location (Google Maps)'),
              _buildInfoListItem('➕', 'Tap "Add Food" to mark food locations'),
              _buildInfoListItem('👁️', 'Tap any food marker to view details'),
              _buildInfoListItem('🌱', 'Complete eco challenges to help the environment'),
              _buildInfoListItem('👥', 'Add friends and send friend requests'),
              _buildInfoListItem('💬', 'Message users about their food listings'),
              _buildInfoListItem('🗑️', 'Delete any food marker (yours or others)'),
              _buildInfoListItem('📍', 'Tap location button to center on you'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person,
                      size: 16,
                      color: Colors.blue[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Signed in as: $_currentUserName',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
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
              child: const Text('Got it!'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoListItem(String icon, String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(8),
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
              boxShadow: const [
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
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Filter and sort markers
            // In _showListView(), replace the filteredMarkers logic with this:
final filteredMarkers = _markers.where((marker) {
  final markerId = marker.markerId.value;
  final markerData = _markerDataCache[markerId];
  if (markerData == null) return false;
  
  // Calculate distance
  final distanceKm = _calculateDistance(
    _currentLocation?.latitude ?? 0,
    _currentLocation?.longitude ?? 0,
    markerData['location']['latitude'] ?? 0,
    markerData['location']['longitude'] ?? 0,
  );
  final distance = _useMiles ? distanceKm * 0.621371 : distanceKm;
  
  // Check if within radius
  if (distance > _radius) return false;
  
  // Apply search filter
  if (_searchQuery.isEmpty) return true;
  
  final name = (markerData['name'] ?? '').toLowerCase();
  final description = (markerData['description'] ?? '').toLowerCase();
  final addedBy = (markerData['addedByName'] ?? '').toLowerCase();
  final query = _searchQuery.toLowerCase();
  
  return name.contains(query) || 
         description.contains(query) || 
         addedBy.contains(query);
}).toList();

// Sort markers
filteredMarkers.sort((a, b) {
  final aData = _markerDataCache[a.markerId.value];
  final bData = _markerDataCache[b.markerId.value];
  if (aData == null || bData == null) return 0;

  switch (_sortBy) {
    case 'distance':
      final aDistance = _calculateDistance(
        _currentLocation?.latitude ?? 0,
        _currentLocation?.longitude ?? 0,
        aData['location']['latitude'] ?? 0,
        aData['location']['longitude'] ?? 0,
      );
      final bDistance = _calculateDistance(
        _currentLocation?.latitude ?? 0,
        _currentLocation?.longitude ?? 0,
        bData['location']['latitude'] ?? 0,
        bData['location']['longitude'] ?? 0,
      );
      return aDistance.compareTo(bDistance);
    
    case 'recent':
      final aTimestamp = aData['timestamp'] ?? 0;
      final bTimestamp = bData['timestamp'] ?? 0;
      return bTimestamp.compareTo(aTimestamp);
    
    case 'name':
      final aName = (aData['name'] ?? '').toLowerCase();
      final bName = (bData['name'] ?? '').toLowerCase();
      return aName.compareTo(bName);
    
    case 'rating':
      // For rating sorting, we'll use a placeholder value
      // The actual sorting will be handled by the FutureBuilder
      return 0;
    
    default:
      return 0;
  }
});

            // If sorting by rating, we need to fetch the ratings first
            if (_sortBy == 'rating') {
              // Create a list of futures for rating lookups
              final ratingFutures = filteredMarkers.map((marker) async {
                final markerData = _getMarkerData(marker.markerId.value);
                if (markerData == null) return 0.0;
                return await _reviewService.getUserTrustScore(markerData['addedBy'] ?? '');
              }).toList();

              // Wait for all rating lookups to complete
              Future.wait(ratingFutures).then((ratings) {
                // Sort the markers based on the fetched ratings
                for (int i = 0; i < filteredMarkers.length; i++) {
                  for (int j = i + 1; j < filteredMarkers.length; j++) {
                    if (ratings[j] > ratings[i]) {
                      // Swap markers
                      final temp = filteredMarkers[i];
                      filteredMarkers[i] = filteredMarkers[j];
                      filteredMarkers[j] = temp;
                      // Swap ratings
                      final tempRating = ratings[i];
                      ratings[i] = ratings[j];
                      ratings[j] = tempRating;
                    }
                  }
                }
                // Trigger a rebuild with the sorted list
                setState(() {});
              });
            }

            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Food Locations',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _useMiles = true;
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      'mi',
                                      style: TextStyle(
                                        color: _useMiles ? const Color(0xFF00A74C) : Colors.grey[600],
                                        fontWeight: _useMiles ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '|',
                                    style: TextStyle(color: Colors.grey[400]),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _useMiles = false;
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      'km',
                                      style: TextStyle(
                                        color: !_useMiles ? const Color(0xFF00A74C) : Colors.grey[600],
                                        fontWeight: !_useMiles ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
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
                                        style: const TextStyle(
                                          color: Color(0xFF00A74C),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: TextField(
                                          controller: _radiusController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                            border: const OutlineInputBorder(),
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
                                  const SizedBox(height: 8),
                                  Slider(
                                    value: _radius,
                                    min: _minRadius,
                                    max: _useMiles ? _maxRadiusMiles : _maxRadiusKm,
                                    divisions: 100,
                                    activeColor: const Color(0xFF00A74C),
                                    inactiveColor: const Color(0xFF00A74C).withOpacity(0.2),
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
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _sortBy,
                                decoration: InputDecoration(
                                  labelText: 'Sort by',
                                  border: const OutlineInputBorder(
                                    borderRadius: BorderRadius.zero,
                                    borderSide: BorderSide(color: Colors.grey),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                  isDense: false,
                                ),
                                isExpanded: true,
                                icon: Icon(Icons.arrow_drop_down, color: const Color(0xFF00A74C)),
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                                dropdownColor: Theme.of(context).colorScheme.surface,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'distance',
                                    child: Text('Distance', style: TextStyle(color: Colors.white)),
                                  ),
                                  DropdownMenuItem(
                                    value: 'recent',
                                    child: Text('Most Recent', style: TextStyle(color: Colors.white)),
                                  ),
                                  DropdownMenuItem(
                                    value: 'name',
                                    child: Text('Name', style: TextStyle(color: Colors.white)),
                                  ),
                                  DropdownMenuItem(
                                    value: 'rating',
                                    child: Text('Rating', style: TextStyle(color: Colors.white)),
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
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Search',
                                  prefixIcon: Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.zero,
                                    borderSide: BorderSide(color: Colors.grey),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
                              const SizedBox(height: 16),
                              Text(
                                'No listings found',
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
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredMarkers.length,
                          // In your _showListView() method, replace the ListView.builder itemBuilder with this:
itemBuilder: (context, index) {
  final marker = filteredMarkers[index];
  final markerId = marker.markerId.value;
  
  return FutureBuilder<Map<String, dynamic>?>(
    future: _getFullMarkerData(markerId),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Card(
          margin: EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A74C)),
                ),
                SizedBox(width: 16),
                Text('Loading marker data...'),
              ],
            ),
          ),
        );
      }

      final markerData = snapshot.data;
      if (markerData == null) {
        return const SizedBox.shrink();
      }

      final distanceKm = _calculateDistance(
        _currentLocation?.latitude ?? 0,
        _currentLocation?.longitude ?? 0,
        markerData['location']['latitude'] ?? 0,
        markerData['location']['longitude'] ?? 0,
      );
      final distance = _useMiles ? distanceKm * 0.621371 : distanceKm;
      final unit = _useMiles ? 'mi' : 'km';
      final isMyMarker = markerData['addedBy'] == _currentUserId;

      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            print('DEBUG: ListView onTap passing markerData: ${markerData}');
            _onMarkerTapped(markerId, markerData);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.restaurant,
                      color: Color(0xFF00A74C),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        markerData['name'] ?? 'Unknown Food',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A74C).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${distance.toStringAsFixed(1)} $unit',
                        style: const TextStyle(
                          color: Color(0xFF00A74C),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (markerData['description'] != null && markerData['description'].isNotEmpty) ...[
                  const SizedBox(height: 8),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.person,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      markerData['addedByName'] ?? 'Unknown User',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    if (markerData['addedBy'] != null)
                      FutureBuilder<double>(
                        future: _reviewService.getUserTrustScore(markerData['addedBy']),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            );
                          }
                          final rating = snapshot.data ?? 0.0;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${rating.toStringAsFixed(1)}',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 20,
                              ),
                            ],
                          );
                        },
                      ),
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
  // Simply return the cached data if available
  return _markerDataCache[markerId];
}

  Future<Map<String, dynamic>?> _getFullMarkerData(String markerId) async {
  // First check the cache
  if (_markerDataCache.containsKey(markerId)) {
    return _markerDataCache[markerId];
  }
  
  // If not in cache, fetch from Firebase
  if (!_firebaseConnected || _foodMarkersRef == null) {
    print('DEBUG: Cannot get full marker data - Firebase not connected or reference is null');
    return null;
  }
  
  try {
    print('DEBUG: Fetching full marker data for markerId: $markerId');
    final snapshot = await _foodMarkersRef!.child(markerId).get();
    print('DEBUG: Snapshot exists: ${snapshot.exists}');
    
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      print('DEBUG: Full data from Firebase: $data');
      
      // Store in cache for future use
      _markerDataCache[markerId] = data;
      
      return data;
    }
    return null;
  } catch (e) {
    print('DEBUG: Error getting full marker data: $e');
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

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    
    switch (index) {
      case 0:
        // Already on Food Map
        break;
      case 1:
        Navigator.of(context).pushReplacement(
          TabPageTransition(
            page: const EcoChallengesScreen(),
            fromIndex: _currentIndex,
            toIndex: index,
          ),
        );
        break;
      case 2:
        Navigator.of(context).pushReplacement(
          TabPageTransition(
            page: const PollutionTrackerScreen(),
            fromIndex: _currentIndex,
            toIndex: index,
          ),
        );
        break;
    }
  }

  LatLng _generateApproximateLocation(LatLng originalLocation, double radiusKm) {
    // Convert radius from km to degrees (approximate)
    final radiusInDegrees = radiusKm / 111.0;
    
    // Generate random angle
    final angle = math.Random().nextDouble() * 2 * math.pi;
    
    // Generate random distance within radius
    final distance = math.Random().nextDouble() * radiusInDegrees;
    
    // Calculate new coordinates
    final lat = originalLocation.latitude + (distance * math.cos(angle));
    final lng = originalLocation.longitude + (distance * math.sin(angle));
    
    return LatLng(lat, lng);
  }

  final Set<Circle> _approximateCircles = {};

  Future<void> _validateAndCleanupMarkers() async {
    if (!_firebaseConnected || _foodMarkersRef == null) return;
    
    try {
      final snapshot = await _foodMarkersRef!.get();
      if (!snapshot.exists) return;
      
      final data = snapshot.value as Map<dynamic, dynamic>;
      final invalidMarkers = <String>[];
      
      data.forEach((key, value) {
        try {
          final markerData = Map<String, dynamic>.from(value);
          final locationData = markerData['location'];
          
          if (locationData == null || 
              locationData['latitude'] == null || 
              locationData['longitude'] == null) {
            print('Found invalid marker: $key');
            print('Marker data: $markerData');
            invalidMarkers.add(key.toString());
          }
        } catch (e) {
          print('Error validating marker $key: $e');
          invalidMarkers.add(key.toString());
        }
      });
      
      // Remove invalid markers
      for (final markerId in invalidMarkers) {
        print('Removing invalid marker: $markerId');
        await _foodMarkersRef!.child(markerId).remove();
      }
      
      if (invalidMarkers.isNotEmpty) {
        print('Removed ${invalidMarkers.length} invalid markers');
      }
    } catch (e) {
      print('Error validating markers: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 2,
        title: Icon(Icons.restaurant_menu, color: const Color(0xFF00A74C)),
        actions: [
          IconButton(
            icon: Icon(Icons.list, color: const Color(0xFF00A74C)),
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
                    icon: const Icon(Icons.people, color: Color(0xFF00A74C)),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const FriendsScreen(),
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
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          pendingCount > 99 ? '99+' : pendingCount.toString(),
                          style: const TextStyle(
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
                    icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00A74C)),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ConversationsScreen(),
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
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: const TextStyle(
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
                backgroundColor: const Color(0xFF00A74C),
                child: Text(
                  _currentUserName.isNotEmpty ? _currentUserName[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFF00A74C)),
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
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Oops! Something went wrong',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      style: const TextStyle(fontSize: 16, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _refreshData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A74C),
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
                  circles: _approximateCircles,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  compassEnabled: true,
                  mapType: MapType.normal,
                  zoomControlsEnabled: false,
                  onCameraMove: _onCameraMove,
                ),
                if (!_isCenteredOnUser)
                  Positioned(
                    left: 20,
                    bottom: 20,
                    child: FloatingActionButton(
                      onPressed: () {
                        if (_currentLocation != null) {
                          _animateToLocation(_currentLocation!);
                        }
                      },
                      backgroundColor: Colors.white,
                      child: Icon(Icons.my_location, color: Colors.green[600]),
                      heroTag: "center_location",
                    ),
                  ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton.extended(
                    onPressed: _addFoodMarker,
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('Add Food', style: TextStyle(color: Colors.white)),
                    backgroundColor: const Color(0xFF00A74C),
                    foregroundColor: Colors.white,
                    heroTag: "add_food",
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
