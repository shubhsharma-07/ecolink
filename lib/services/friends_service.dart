import 'package:firebase_database/firebase_database.dart';
import 'auth_service.dart';

/// Represents the possible states of a friendship between two users
enum FriendshipStatus {
  none,      // No friendship or request exists
  pending,   // Current user has sent a friend request
  requested, // Other user has sent a friend request
  friends,   // Users are friends
}

/// Service class that handles all friend-related operations
/// Manages friend requests, friendships, and friend lists
class FriendsService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final AuthService _authService = AuthService();

  /// Returns the current user's unique identifier
  String get currentUserId => _authService.currentUserId ?? 'unknown';
  
  /// Returns the current user's display name
  String get currentUserName => _authService.currentUserDisplayName;

  /// Generates a consistent request ID for two users
  /// Ensures same ID regardless of who sends the request
  String _generateRequestId(String user1Id, String user2Id) {
    final sortedIds = [user1Id, user2Id]..sort();
    return 'req_${sortedIds[0]}_${sortedIds[1]}';
  }

  /// Sends a friend request to another user
  /// Creates request records for both users and updates their request lists
  Future<void> sendFriendRequest({
    required String recipientId,
    required String recipientName,
  }) async {
    try {
      if (recipientId == currentUserId) {
        throw Exception('Cannot send friend request to yourself');
      }

      // Verify no existing friendship or request
      final existingStatus = await getFriendshipStatus(recipientId);
      if (existingStatus != FriendshipStatus.none) {
        throw Exception('Friend request already exists or you are already friends');
      }

      final requestId = _generateRequestId(currentUserId, recipientId);
      const timestamp = ServerValue.timestamp;

      // Create friend request data structure
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

      // Store request in friend requests collection
      await _database
          .child('friendRequests')
          .child(requestId)
          .set(requestData);

      // Update sender's outgoing requests list
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

      // Update recipient's incoming requests list
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

  /// Accepts a pending friend request
  /// Updates friendship status and adds users to each other's friend lists
  Future<void> acceptFriendRequest(String requestId, String senderId, String senderName) async {
    try {
      const timestamp = ServerValue.timestamp;

      print('Accepting friend request: $requestId from $senderId');

      // Update request status to accepted
      await _database
          .child('friendRequests')
          .child(requestId)
          .child('status')
          .set('accepted');

      // Add friendship records for both users
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

      // Remove request records
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

  /// Declines a pending friend request
  /// Updates request status and removes request records
  Future<void> declineFriendRequest(String requestId, String senderId) async {
    try {
      print('Declining friend request: $requestId from $senderId');

      // Update request status to declined
      await _database
          .child('friendRequests')
          .child(requestId)
          .child('status')
          .set('declined');

      // Remove request records for both users
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

  /// Cancels an outgoing friend request
  /// Updates request status and removes request records
  Future<void> cancelFriendRequest(String recipientId) async {
    try {
      print('Cancelling friend request to: $recipientId');

      // Retrieve request details
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

        // Update request status to cancelled
        await _database
            .child('friendRequests')
            .child(requestId)
            .child('status')
            .set('cancelled');

        // Remove request records for both users
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

  /// Removes a friendship between two users
  /// Deletes friendship records for both users
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

  /// Gets the current friendship status with another user
  /// Checks for existing friendship, outgoing request, or incoming request
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

  /// Returns a stream of the user's friends list
  /// Friends are sorted alphabetically by name
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

  /// Returns a stream of incoming friend requests
  /// Requests are sorted by timestamp (newest first)
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

  /// Returns a stream of outgoing friend requests
  /// Requests are sorted by timestamp (newest first)
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

  /// Returns a stream of the total number of pending friend requests
  Stream<int> getPendingRequestsCount() {
    return getIncomingFriendRequests().map((requests) => requests.length);
  }

  /// Searches for users in both food and pollution markers
  /// Filters out existing friends and pending requests
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