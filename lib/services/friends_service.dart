import 'package:firebase_database/firebase_database.dart';
import 'auth_service.dart';

enum FriendshipStatus {
  none,
  pending, // I sent a request
  requested, // They sent me a request
  friends,
}

class FriendsService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final AuthService _authService = AuthService();

  // Get current user info
  String get currentUserId => _authService.currentUserId ?? 'unknown';
  String get currentUserName => _authService.currentUserDisplayName;

  // Generate consistent request ID for two users
  String _generateRequestId(String user1Id, String user2Id) {
    // Always put the smaller user ID first for consistency
    final sortedIds = [user1Id, user2Id]..sort();
    return 'req_${sortedIds[0]}_${sortedIds[1]}';
  }

  // Send a friend request
  Future<void> sendFriendRequest({
    required String recipientId,
    required String recipientName,
  }) async {
    try {
      if (recipientId == currentUserId) {
        throw Exception('Cannot send friend request to yourself');
      }

      // Check if already friends or request exists
      final existingStatus = await getFriendshipStatus(recipientId);
      if (existingStatus != FriendshipStatus.none) {
        throw Exception('Friend request already exists or you are already friends');
      }

      final requestId = _generateRequestId(currentUserId, recipientId);
      final timestamp = ServerValue.timestamp;

      // Create friend request data
      final requestData = {
        'id': requestId,
        'senderId': currentUserId,
        'senderName': currentUserName,
        'recipientId': recipientId,
        'recipientName': recipientName,
        'status': 'pending',
        'timestamp': timestamp,
      };

      print('Sending friend request: $requestData');

      // Save to friend requests
      await _database
          .child('friendRequests')
          .child(requestId)
          .set(requestData);

      // Update sender's outgoing requests
      await _database
          .child('userFriendRequests')
          .child(currentUserId)
          .child('outgoing')
          .child(recipientId)
          .set({
        'requestId': requestId,
        'userId': recipientId,
        'userName': recipientName,
        'timestamp': timestamp,
        'status': 'pending',
      });

      // Update recipient's incoming requests
      await _database
          .child('userFriendRequests')
          .child(recipientId)
          .child('incoming')
          .child(currentUserId)
          .set({
        'requestId': requestId,
        'userId': currentUserId,
        'userName': currentUserName,
        'timestamp': timestamp,
        'status': 'pending',
      });

      print('Friend request sent successfully');

    } catch (e) {
      print('Error sending friend request: $e');
      throw Exception('Failed to send friend request: $e');
    }
  }

  // Accept a friend request
  Future<void> acceptFriendRequest(String requestId, String senderId, String senderName) async {
    try {
      final timestamp = ServerValue.timestamp;

      print('Accepting friend request: $requestId from $senderId');

      // Update request status
      await _database
          .child('friendRequests')
          .child(requestId)
          .child('status')
          .set('accepted');

      // Add to friends lists
      await _database
          .child('userFriends')
          .child(currentUserId)
          .child(senderId)
          .set({
        'userId': senderId,
        'userName': senderName,
        'timestamp': timestamp,
        'status': 'friends',
      });

      await _database
          .child('userFriends')
          .child(senderId)
          .child(currentUserId)
          .set({
        'userId': currentUserId,
        'userName': currentUserName,
        'timestamp': timestamp,
        'status': 'friends',
      });

      // Remove from friend requests
      await _database
          .child('userFriendRequests')
          .child(currentUserId)
          .child('incoming')
          .child(senderId)
          .remove();

      await _database
          .child('userFriendRequests')
          .child(senderId)
          .child('outgoing')
          .child(currentUserId)
          .remove();

      print('Friend request accepted successfully');

    } catch (e) {
      print('Error accepting friend request: $e');
      throw Exception('Failed to accept friend request: $e');
    }
  }

  // Decline a friend request
  Future<void> declineFriendRequest(String requestId, String senderId) async {
    try {
      print('Declining friend request: $requestId from $senderId');

      // Update request status
      await _database
          .child('friendRequests')
          .child(requestId)
          .child('status')
          .set('declined');

      // Remove from friend requests
      await _database
          .child('userFriendRequests')
          .child(currentUserId)
          .child('incoming')
          .child(senderId)
          .remove();

      await _database
          .child('userFriendRequests')
          .child(senderId)
          .child('outgoing')
          .child(currentUserId)
          .remove();

      print('Friend request declined successfully');

    } catch (e) {
      print('Error declining friend request: $e');
      throw Exception('Failed to decline friend request: $e');
    }
  }

  // Cancel outgoing friend request
  Future<void> cancelFriendRequest(String recipientId) async {
    try {
      print('Cancelling friend request to: $recipientId');

      // Find the request ID
      final outgoingSnapshot = await _database
          .child('userFriendRequests')
          .child(currentUserId)
          .child('outgoing')
          .child(recipientId)
          .get();

      if (outgoingSnapshot.exists) {
        final data = outgoingSnapshot.value as Map<dynamic, dynamic>;
        final requestId = data['requestId'];

        print('Found request to cancel: $requestId');

        // Update request status
        await _database
            .child('friendRequests')
            .child(requestId)
            .child('status')
            .set('cancelled');

        // Remove from friend requests
        await _database
            .child('userFriendRequests')
            .child(currentUserId)
            .child('outgoing')
            .child(recipientId)
            .remove();

        await _database
            .child('userFriendRequests')
            .child(recipientId)
            .child('incoming')
            .child(currentUserId)
            .remove();

        print('Friend request cancelled successfully');
      } else {
        print('No outgoing request found to $recipientId');
      }

    } catch (e) {
      print('Error cancelling friend request: $e');
      throw Exception('Failed to cancel friend request: $e');
    }
  }

  // Remove friend
  Future<void> removeFriend(String friendId) async {
    try {
      print('Removing friend: $friendId');

      // Remove from both users' friends lists
      await _database
          .child('userFriends')
          .child(currentUserId)
          .child(friendId)
          .remove();

      await _database
          .child('userFriends')
          .child(friendId)
          .child(currentUserId)
          .remove();

      print('Friend removed successfully');

    } catch (e) {
      print('Error removing friend: $e');
      throw Exception('Failed to remove friend: $e');
    }
  }

  // Get friendship status with another user
  Future<FriendshipStatus> getFriendshipStatus(String userId) async {
    try {
      if (userId == currentUserId) return FriendshipStatus.none;

      print('Getting friendship status with: $userId');

      // Check if already friends
      final friendSnapshot = await _database
          .child('userFriends')
          .child(currentUserId)
          .child(userId)
          .get();

      if (friendSnapshot.exists) {
        print('Already friends with $userId');
        return FriendshipStatus.friends;
      }

      // Check for outgoing request
      final outgoingSnapshot = await _database
          .child('userFriendRequests')
          .child(currentUserId)
          .child('outgoing')
          .child(userId)
          .get();

      if (outgoingSnapshot.exists) {
        print('Found outgoing request to $userId');
        return FriendshipStatus.pending;
      }

      // Check for incoming request
      final incomingSnapshot = await _database
          .child('userFriendRequests')
          .child(currentUserId)
          .child('incoming')
          .child(userId)
          .get();

      if (incomingSnapshot.exists) {
        print('Found incoming request from $userId');
        return FriendshipStatus.requested;
      }

      print('No relationship with $userId');
      return FriendshipStatus.none;

    } catch (e) {
      print('Error getting friendship status: $e');
      return FriendshipStatus.none;
    }
  }

  // Get user's friends list
  Stream<List<Map<String, dynamic>>> getFriends() {
    return _database
        .child('userFriends')
        .child(currentUserId)
        .onValue
        .map((event) {
      if (!event.snapshot.exists) return <Map<String, dynamic>>[];

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final friends = <Map<String, dynamic>>[];

      data.forEach((key, value) {
        final friend = Map<String, dynamic>.from(value);
        friend['id'] = key;
        friends.add(friend);
      });

      // Sort by name
      friends.sort((a, b) => (a['userName'] ?? '').compareTo(b['userName'] ?? ''));

      return friends;
    });
  }

  // Get incoming friend requests
  Stream<List<Map<String, dynamic>>> getIncomingFriendRequests() {
    return _database
        .child('userFriendRequests')
        .child(currentUserId)
        .child('incoming')
        .onValue
        .map((event) {
      if (!event.snapshot.exists) return <Map<String, dynamic>>[];

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final requests = <Map<String, dynamic>>[];

      data.forEach((key, value) {
        final request = Map<String, dynamic>.from(value);
        request['senderId'] = key;
        requests.add(request);
      });

      // Sort by timestamp (newest first)
      requests.sort((a, b) {
        final aTime = a['timestamp'] ?? 0;
        final bTime = b['timestamp'] ?? 0;
        return bTime.compareTo(aTime);
      });

      return requests;
    });
  }

  // Get outgoing friend requests
  Stream<List<Map<String, dynamic>>> getOutgoingFriendRequests() {
    return _database
        .child('userFriendRequests')
        .child(currentUserId)
        .child('outgoing')
        .onValue
        .map((event) {
      if (!event.snapshot.exists) return <Map<String, dynamic>>[];

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final requests = <Map<String, dynamic>>[];

      data.forEach((key, value) {
        final request = Map<String, dynamic>.from(value);
        request['recipientId'] = key;
        requests.add(request);
      });

      // Sort by timestamp (newest first)
      requests.sort((a, b) {
        final aTime = a['timestamp'] ?? 0;
        final bTime = b['timestamp'] ?? 0;
        return bTime.compareTo(aTime);
      });

      return requests;
    });
  }

  // Get total pending friend requests count
  Stream<int> getPendingRequestsCount() {
    return getIncomingFriendRequests().map((requests) => requests.length);
  }

  // IMPROVED: Search for users from BOTH food markers AND pollution markers
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      if (query.trim().isEmpty) return [];

      print('Searching for users with query: $query');

      final users = <String, Map<String, dynamic>>{};

      // Get current friends and requests to filter out
      final friendsSnapshot = await _database
          .child('userFriends')
          .child(currentUserId)
          .get();
      
      final outgoingSnapshot = await _database
          .child('userFriendRequests')
          .child(currentUserId)
          .child('outgoing')
          .get();

      final friends = <String>{};
      final pendingRequests = <String>{};

      if (friendsSnapshot.exists) {
        final friendsData = friendsSnapshot.value as Map<dynamic, dynamic>;
        friends.addAll(friendsData.keys.cast<String>());
      }

      if (outgoingSnapshot.exists) {
        final requestsData = outgoingSnapshot.value as Map<dynamic, dynamic>;
        pendingRequests.addAll(requestsData.keys.cast<String>());
      }

      print('Current friends: $friends');
      print('Pending requests: $pendingRequests');

      // Search in FOOD markers
      try {
        final foodMarkersSnapshot = await _database.child('foodMarkers').get();
        if (foodMarkersSnapshot.exists) {
          final foodData = foodMarkersSnapshot.value as Map<dynamic, dynamic>;
          
          foodData.forEach((key, value) {
            final marker = Map<String, dynamic>.from(value);
            final userId = marker['addedBy'];
            final userName = marker['addedByName'];

            if (userId != null && 
                userName != null && 
                userId != currentUserId &&
                !friends.contains(userId) &&
                !pendingRequests.contains(userId) &&
                userName.toLowerCase().contains(query.toLowerCase())) {
              
              users[userId] = {
                'userId': userId,
                'userName': userName,
                'source': 'food_markers',
              };
              print('Found user from food markers: $userName ($userId)');
            }
          });
        }
      } catch (e) {
        print('Error searching food markers: $e');
      }

      // Search in POLLUTION markers
      try {
        final pollutionMarkersSnapshot = await _database.child('pollutionMarkers').get();
        if (pollutionMarkersSnapshot.exists) {
          final pollutionData = pollutionMarkersSnapshot.value as Map<dynamic, dynamic>;
          
          pollutionData.forEach((key, value) {
            final marker = Map<String, dynamic>.from(value);
            final userId = marker['addedBy'];
            final userName = marker['addedByName'];

            if (userId != null && 
                userName != null && 
                userId != currentUserId &&
                !friends.contains(userId) &&
                !pendingRequests.contains(userId) &&
                userName.toLowerCase().contains(query.toLowerCase())) {
              
              users[userId] = {
                'userId': userId,
                'userName': userName,
                'source': 'pollution_markers',
              };
              print('Found user from pollution markers: $userName ($userId)');
            }
          });
        }
      } catch (e) {
        print('Error searching pollution markers: $e');
      }

      // Search in USERS collection directly
      try {
        final usersSnapshot = await _database.child('users').get();
        if (usersSnapshot.exists) {
          final usersData = usersSnapshot.value as Map<dynamic, dynamic>;
          
          usersData.forEach((userId, userData) {
            final user = Map<String, dynamic>.from(userData);
            final userName = user['displayName'];

            if (userName != null && 
                userId != currentUserId &&
                !friends.contains(userId) &&
                !pendingRequests.contains(userId) &&
                userName.toLowerCase().contains(query.toLowerCase())) {
              
              users[userId] = {
                'userId': userId,
                'userName': userName,
                'source': 'users_collection',
              };
              print('Found user from users collection: $userName ($userId)');
            }
          });
        }
      } catch (e) {
        print('Error searching users collection: $e');
      }

      final results = users.values.toList()
        ..sort((a, b) => (a['userName'] ?? '').compareTo(b['userName'] ?? ''));

      print('Search results: ${results.length} users found');
      return results;

    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  // Check if user is friend
  Future<bool> isFriend(String userId) async {
    final status = await getFriendshipStatus(userId);
    return status == FriendshipStatus.friends;
  }
}