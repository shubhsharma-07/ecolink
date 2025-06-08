import 'package:firebase_database/firebase_database.dart';
import 'auth_service.dart';

/// Service class that handles all messaging-related operations
/// Manages conversations, messages, and real-time updates for the chat system
class MessagingService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final AuthService _authService = AuthService();

  /// Returns the current user's unique identifier
  String get currentUserId => _authService.currentUserId ?? 'unknown';
  
  /// Returns the current user's display name
  String get currentUserName => _authService.currentUserDisplayName;

  /// Sends a new message in a conversation about a food listing
  /// Creates or updates conversation metadata and updates both users' conversation lists
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

      // Generate consistent conversation ID for both users
      final conversationId = _getConversationId(currentUserId, recipientId);

      // Store message in conversation
      await _database
          .child('conversations')
          .child(conversationId)
          .child('messages')
          .child(messageId)
          .set(messageData);

      // Update conversation metadata with latest message info
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

      // Update sender's conversation list
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
        'unreadCount': 0,
      });

      // Update recipient's conversation list with unread count
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

  /// Generates a consistent conversation ID for two users
  /// Ensures same ID regardless of who initiates the conversation
  String _getConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  /// Returns a stream of the current user's conversations
  /// Conversations are sorted by most recent message
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

      // Sort conversations by timestamp (newest first)
      conversations.sort((a, b) {
        final aTime = a['lastTimestamp'] ?? 0;
        final bTime = b['lastTimestamp'] ?? 0;
        return bTime.compareTo(aTime);
      });

      return conversations;
    });
  }

  /// Returns a stream of messages for a specific conversation
  /// Messages are sorted chronologically (oldest first)
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

      // Sort messages by timestamp (oldest first for chat display)
      messages.sort((a, b) {
        final aTime = a['timestamp'] ?? 0;
        final bTime = b['timestamp'] ?? 0;
        return aTime.compareTo(bTime);
      });

      return messages;
    });
  }

  /// Marks all messages in a conversation as read for the current user
  /// Resets unread count and updates message read status
  Future<void> markConversationAsRead(String conversationId) async {
    try {
      // Reset unread count for current user
      await _database
          .child('userConversations')
          .child(currentUserId)
          .child(conversationId)
          .child('unreadCount')
          .set(0);

      // Mark all unread messages as read
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

  /// Returns a stream of the total unread message count for the current user
  /// Aggregates unread counts from all conversations
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

  /// Development utility: Deletes a conversation and all its messages
  /// Removes conversation data for both participants
  Future<void> deleteConversationForEveryone(String conversationId, String otherUserId) async {
    bool anyError = false;

    // Delete from current user's conversation list
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

    // Delete from other user's conversation list
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
