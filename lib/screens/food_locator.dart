import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../services/friends_service.dart';
import '../screens/conversations_screen.dart';
import '../screens/friends_screen.dart';
import '../widgets/message_button.dart';
import '../widgets/friend_button.dart';
import '../screens/eco_challenges_screen.dart';
import '../screens/pollution_tracker_screen.dart';

class FoodLocatorScreen extends StatefulWidget {
  @override
  _FoodLocatorScreenState createState() => _FoodLocatorScreenState();
}

class _FoodLocatorScreenState extends State<FoodLocatorScreen> {
  GoogleMapController? _mapController;
  Location _location = Location();
  LocationData? _currentLocation;
  Set<Marker> _markers = {};
  bool _isLoading = true;
  String _errorMessage = '';
  DatabaseReference? _database;
  DatabaseReference? _foodMarkersRef;
  bool _firebaseConnected = false;
  final ImagePicker _imagePicker = ImagePicker();
  final AuthService _authService = AuthService();
  final MessagingService _messagingService = MessagingService();
  final FriendsService _friendsService = FriendsService();

  String get _currentUserId => _authService.currentUserId ?? 'unknown';
  String get _currentUserName => _authService.currentUserDisplayName;
  bool get _isAnonymous => false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await _initializeFirebase();
    await _setupLocation();
    if (_firebaseConnected) {
      await _loadFoodMarkers();
      _setupRealtimeListener();
    }
  }

  Future<void> _initializeFirebase() async {
    try {
      _database = FirebaseDatabase.instance.ref();
      _foodMarkersRef = _database!.child('foodMarkers');
      _firebaseConnected = true;
      print('Firebase connected successfully');
    } catch (e) {
      print('Firebase connection failed: $e');
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
        _animateToLocation(newLocation);
      });
    } catch (e) {
      _setError('Failed to get location: $e');
    }
  }

  Future<void> _loadFoodMarkers() async {
    if (!_firebaseConnected || _foodMarkersRef == null) return;
    try {
      final snapshot = await _foodMarkersRef!.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        _buildMarkersFromData(data);
      }
    } catch (e) {
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
      data.forEach((key, value) {
        final markerData = Map<String, dynamic>.from(value);
        final isMyMarker = markerData['addedBy'] == _currentUserId;
        final addedByName = markerData['addedByName'] ?? 'Unknown User';
        _markers.add(
          Marker(
            markerId: MarkerId(key),
            position: LatLng(
              markerData['latitude'].toDouble(),
              markerData['longitude'].toDouble(),
            ),
            infoWindow: InfoWindow(
              title: markerData['name'],
              snippet: isMyMarker 
                ? 'Added by you • Tap to view details' 
                : 'Added by $addedByName • Tap to view details',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isMyMarker ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueRed
            ),
            onTap: () => _onMarkerTapped(key, markerData),
          ),
        );
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
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing food marker...'),
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
        'latitude': _currentLocation!.latitude!,
        'longitude': _currentLocation!.longitude!,
        'timestamp': ServerValue.timestamp,
        'addedBy': _currentUserId,
        'addedByName': _currentUserName,
        'images': base64Images,
        'imageCount': base64Images.length,
      };
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
      if (_firebaseConnected && _foodMarkersRef != null) {
        await _foodMarkersRef!.child(markerId).set(markerData);
        Navigator.of(context).pop();
        _showSnackBar('Food marker "${foodData['name']}" shared with community!', Color(0xFF00A74C));
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
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.restaurant, color: Color(0xFF00A74C)),
                  SizedBox(width: 8),
                  Text('Add Food Location'),
                ],
              ),
              content: Container(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tell us about the food at your location:'),
                      SizedBox(height: 16),
                      TextField(
                        onChanged: (value) => foodName = value,
                        decoration: InputDecoration(
                          labelText: 'Food Name *',
                          hintText: 'e.g., Pizza, Burger, Tacos',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.fastfood),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      SizedBox(height: 16),
                      TextField(
                        onChanged: (value) => description = value,
                        decoration: InputDecoration(
                          labelText: 'Description *',
                          hintText: 'Describe the food, price, availability...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      SizedBox(height: 16),
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
                                          setState(() {
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
                                  setState(() {
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
                                  setState(() {
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
                  onPressed: foodName.trim().isNotEmpty &&
                           description.trim().isNotEmpty &&
                           selectedImages.isNotEmpty
                      ? () {
                          Navigator.of(context).pop({
                            'name': foodName.trim(),
                            'description': description.trim(),
                            'images': selectedImages,
                          });
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF00A74C),
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Add Marker'),
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
                    color: Color(0xFFE6F8EE),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.restaurant, color: Color(0xFF00A74C), size: 24),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              markerData['name'] ?? 'Unknown Food',
                              style: TextStyle(
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
                        if (markerData['description'] != null && markerData['description'].isNotEmpty) ...[
                          Text(
                            'Description',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(markerData['description']),
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
                                foodName: markerData['name'] ?? 'Unknown Food',
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
                                    markerData['name'] ?? 'Unknown Food',
                                    addedByName,
                                    isMyMarker
                                  );
                                  if (shouldDelete == true) {
                                    await _deleteMarker(markerId, markerData['name'] ?? 'Unknown Food');
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

  Future<bool?> _showDeleteConfirmationDialog(String markerName, String addedByName, bool isMyMarker) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
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
              Text('Are you sure you want to delete this food marker?'),
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
                        Icon(Icons.restaurant, color: Color(0xFF00A74C), size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            markerName,
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
              SizedBox(height: 12),
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

  Future<void> _deleteMarker(String markerId, String markerName) async {
    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == markerId);
    });
    if (_firebaseConnected && _foodMarkersRef != null) {
      try {
        await _foodMarkersRef!.child(markerId).remove();
        _showSnackBar('Marker "$markerName" deleted successfully', Color(0xFF00A74C));
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
    if (_mapController != null) {
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

  // ========== Modern Profile Sheet ==========
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
                backgroundColor: Color(0xFF00A74C),
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
        duration: Duration(seconds: 3),
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
          title: Row(
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
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(8),
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
                    SizedBox(width: 8),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: Row(
          children: [
            Icon(Icons.restaurant_menu, color: Color(0xFF00A74C)),
            SizedBox(width: 8),
            Text(
              'Food Locator',
              style: TextStyle(
                color: Color(0xFF00A74C),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          StreamBuilder<int>(
            stream: _friendsService.getPendingRequestsCount(),
            builder: (context, snapshot) {
              final pendingCount = snapshot.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.people, color: Color(0xFF00A74C)),
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
                    icon: Icon(Icons.chat_bubble_outline, color: Color(0xFF00A74C)),
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
                backgroundColor: Color(0xFF00A74C),
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
                        backgroundColor: Color(0xFF00A74C),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.extended(
                        onPressed: _addFoodMarker,
                        icon: Icon(Icons.restaurant),
                        label: Text('Add Food', style: TextStyle(color: Colors.white)),
                        backgroundColor: Color(0xFF00A74C),
                        foregroundColor: Colors.white,
                        heroTag: "add_food",
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _buildBottomInfo(),
    );
  }

  Widget? _buildBottomInfo() {
    if (_currentLocation == null) return null;
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
                _showSnackBar('You are already on the Food Locator screen', Color(0xFF00A74C));
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Color(0xFF00A74C).withOpacity(0.07),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                  ),
                  border: Border.all(
                    color: Color(0xFF00A74C).withOpacity(0.3),
                    width: 2,
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
                        fontWeight: FontWeight.bold,
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
                Navigator.of(context).push(
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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => PollutionTrackerScreen(),
                  ),
                );
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(20),
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
                        fontWeight: FontWeight.w500,
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
}
