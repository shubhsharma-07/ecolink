import 'package:firebase_database/firebase_database.dart';
import 'auth_service.dart';

class MessagingService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final AuthService _authService = AuthService();

  // Get current user info
  String get currentUserId => _authService.currentUserId ?? 'unknown';
  String get currentUserName => _authService.currentUserDisplayName;

  // Send a message about a food listing
  Future<void> sendMessage({
    required String recipientId,
    required String recipientName,
    required String foodMarkerId,
    required String foodName,
    required String message,
  }) async {
    try {
      final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
      final timestamp = ServerValue.timestamp;

      final messageData = {
        'id': messageId,
        'senderId': currentUserId,
        'senderName': currentUserName,
        'recipientId': recipientId,
        'recipientName': recipientName,
        'foodMarkerId': foodMarkerId,
        'foodName': foodName,
        'message': message,
        'timestamp': timestamp,
        'read': false,
      };

      // Create conversation ID (consistent regardless of who sends first)
      final conversationId = _getConversationId(currentUserId, recipientId);

      // Save message to conversation
      await _database
          .child('conversations')
          .child(conversationId)
          .child('messages')
          .child(messageId)
          .set(messageData);

      // Update conversation metadata
      await _database
          .child('conversations')
          .child(conversationId)
          .child('metadata')
          .set({
        'participants': {
          currentUserId: currentUserName,
          recipientId: recipientName,
        },
        'lastMessage': message,
        'lastTimestamp': timestamp,
        'lastSenderId': currentUserId,
        'foodMarkerId': foodMarkerId,
        'foodName': foodName,
      });

      // Update user's conversation list
      await _database
          .child('userConversations')
          .child(currentUserId)
          .child(conversationId)
          .set({
        'conversationId': conversationId,
        'otherUserId': recipientId,
        'otherUserName': recipientName,
        'foodMarkerId': foodMarkerId,
        'foodName': foodName,
        'lastMessage': message,
        'lastTimestamp': timestamp,
        'unreadCount': 0, // No unread for sender
      });

      // Update recipient's conversation list
      await _database
          .child('userConversations')
          .child(recipientId)
          .child(conversationId)
          .set({
        'conversationId': conversationId,
        'otherUserId': currentUserId,
        'otherUserName': currentUserName,
        'foodMarkerId': foodMarkerId,
        'foodName': foodName,
        'lastMessage': message,
        'lastTimestamp': timestamp,
        'unreadCount': ServerValue.increment(1),
      });
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  // Get conversation ID (always same order)
  String _getConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  // Get user's conversations
  Stream<List<Map<String, dynamic>>> getUserConversations() {
    return _database
        .child('userConversations')
        .child(currentUserId)
        .orderByChild('lastTimestamp')
        .onValue
        .map((event) {
      if (!event.snapshot.exists) return <Map<String, dynamic>>[];

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final conversations = <Map<String, dynamic>>[];

      data.forEach((key, value) {
        final conversation = Map<String, dynamic>.from(value);
        conversation['id'] = key;
        conversations.add(conversation);
      });

      // Sort by timestamp (newest first)
      conversations.sort((a, b) {
        final aTime = a['lastTimestamp'] ?? 0;
        final bTime = b['lastTimestamp'] ?? 0;
        return bTime.compareTo(aTime);
      });

      return conversations;
    });
  }

  // Get messages for a conversation
  Stream<List<Map<String, dynamic>>> getConversationMessages(String conversationId) {
    return _database
        .child('conversations')
        .child(conversationId)
        .child('messages')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
      if (!event.snapshot.exists) return <Map<String, dynamic>>[];

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final messages = <Map<String, dynamic>>[];

      data.forEach((key, value) {
        final message = Map<String, dynamic>.from(value);
        messages.add(message);
      });

      // Sort by timestamp (oldest first for chat display)
      messages.sort((a, b) {
        final aTime = a['timestamp'] ?? 0;
        final bTime = b['timestamp'] ?? 0;
        return aTime.compareTo(bTime);
      });

      return messages;
    });
  }

  // Mark conversation as read
  Future<void> markConversationAsRead(String conversationId) async {
    try {
      // Reset unread count for current user
      await _database
          .child('userConversations')
          .child(currentUserId)
          .child(conversationId)
          .child('unreadCount')
          .set(0);

      // Mark messages as read
      final messagesRef = _database
          .child('conversations')
          .child(conversationId)
          .child('messages');

      final snapshot = await messagesRef.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;

        data.forEach((messageId, messageData) async {
          final message = Map<String, dynamic>.from(messageData);
          if (message['recipientId'] == currentUserId && !message['read']) {
            await messagesRef.child(messageId).child('read').set(true);
          }
        });
      }
    } catch (e) {
      print('Error marking conversation as read: $e');
    }
  }

  // Get total unread count for user
  Stream<int> getUnreadCount() {
    return _database
        .child('userConversations')
        .child(currentUserId)
        .onValue
        .map((event) {
      if (!event.snapshot.exists) return 0;

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      int totalUnread = 0;

      data.forEach((key, value) {
        final conversation = Map<String, dynamic>.from(value);
        final unreadCount = conversation['unreadCount'] ?? 0;
        totalUnread += unreadCount as int;
      });

      return totalUnread;
    });
  }

  // DEV ONLY: Delete conversation for both users and all messages, with debug prints
  Future<void> deleteConversationForEveryone(String conversationId, String otherUserId) async {
    bool anyError = false;

    // Try to delete from your userConversations node
    try {
      await _database
          .child('userConversations')
          .child(currentUserId)
          .child(conversationId)
          .remove();
      print('Deleted from my userConversations');
    } catch (e) {
      print('FAILED deleting from my userConversations: $e');
      anyError = true;
    }

    // Try to delete from other user's userConversations node
    try {
      await _database
          .child('userConversations')
          .child(otherUserId)
          .child(conversationId)
          .remove();
      print('Deleted from other userConversations');
    } catch (e) {
      print('FAILED deleting from other userConversations: $e');
      anyError = true;
    }

    // Try to delete the entire conversation and messages
    try {
      await _database
          .child('conversations')
          .child(conversationId)
          .remove();
      print('Deleted from conversations');
    } catch (e) {
      print('FAILED deleting from conversations: $e');
      anyError = true;
    }

    if (anyError) {
      throw Exception('Some parts could not be deleted, check console for details');
    }
  }

  // Legacy: Delete conversation only for self, delete from conversations if both users removed it
  Future<void> deleteConversation(String conversationId, String otherUserId) async {
    try {
      // Remove from user's conversation list
      await _database
          .child('userConversations')
          .child(currentUserId)
          .child(conversationId)
          .remove();

      // Check if other user still has the conversation
      final otherUserConversation = await _database
          .child('userConversations')
          .child(otherUserId)
          .child(conversationId)
          .get();

      // If other user also doesn't have it, delete the entire conversation
      if (!otherUserConversation.exists) {
        await _database
            .child('conversations')
            .child(conversationId)
            .remove();
      }
    } catch (e) {
      throw Exception('Failed to delete conversation: $e');
    }
  }
}
