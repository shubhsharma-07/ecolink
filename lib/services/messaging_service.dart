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
  /// Works with current Firebase rules by only writing where permitted
  Future<void> sendMessage({
    required String recipientId,
    required String recipientName,
    required String foodMarkerId,
    required String foodName,
    required String message,
    List<String>? images,
  }) async {
    print('🔵 SEND MESSAGE DEBUG START');
    print('Current User ID: $currentUserId');
    print('Current User Name: $currentUserName');
    print('Recipient ID: $recipientId');
    print('Recipient Name: $recipientName');
    
    try {
      final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
      final timestampValue = DateTime.now().millisecondsSinceEpoch;
      final conversationId = _getConversationId(currentUserId, recipientId);
      
      print('Conversation ID: $conversationId');
      print('Message ID: $messageId');

      // Reference to the conversation
      final conversationRef = _database.child('conversations').child(conversationId);
      
      // Check if conversation exists
      print('🔍 Checking if conversation exists...');
      final conversationSnapshot = await conversationRef.get();
      
      if (!conversationSnapshot.exists) {
        print('📝 Creating new conversation...');
        final conversationData = {
          'participants': {
            currentUserId: true,
            recipientId: true,
          },
          'lastMessageTimestamp': timestampValue,
          'lastMessage': images != null && images.isNotEmpty ? '📷 Image' : message,
          'lastSenderId': currentUserId,
          'foodMarkerId': foodMarkerId,
          'foodName': foodName,
        };
        
        print('Conversation data to create: $conversationData');
        
        try {
          await conversationRef.set(conversationData);
          print('✅ Conversation created successfully');
        } catch (e) {
          print('❌ Error creating conversation: $e');
          throw e;
        }
      } else {
        print('📝 Updating existing conversation...');
        final updateData = {
          'lastMessageTimestamp': timestampValue,
          'lastMessage': images != null && images.isNotEmpty ? '📷 Image' : message,
          'lastSenderId': currentUserId,
          'foodMarkerId': foodMarkerId,
          'foodName': foodName,
        };
        
        print('Update data: $updateData');
        
        try {
          await conversationRef.update(updateData);
          print('✅ Conversation updated successfully');
        } catch (e) {
          print('❌ Error updating conversation: $e');
          throw e;
        }
      }

      // Add the message - include ALL fields at once to satisfy validation
      print('📨 Creating message...');
      final messageData = {
        // Required fields for validation
        'senderId': currentUserId,
        'text': message,
        'timestamp': timestampValue,
        // Additional fields (these won't break validation)
        'senderName': currentUserName,
        'recipientId': recipientId,
        'recipientName': recipientName,
        'foodMarkerId': foodMarkerId,
        'foodName': foodName,
        'read': false,
        'hasImages': images != null && images.isNotEmpty,
        'images': images ?? [],
      };

      print('Message data: $messageData');
      print('Message path: conversations/$conversationId/messages/$messageId');

      // Set all fields at once
      try {
        await conversationRef
            .child('messages')
            .child(messageId)
            .set(messageData);
        print('✅ Message created successfully');
      } catch (e) {
        print('❌ Error creating message: $e');
        print('Error type: ${e.runtimeType}');
        print('Error details: ${e.toString()}');
        throw e;
      }

      // Update sender's conversation list (we have permission for this)
      print('📋 Updating sender conversation list...');
      final senderConvData = {
        'otherUserId': recipientId,
        'lastMessageTimestamp': timestampValue,
        'conversationId': conversationId,
        'otherUserName': recipientName,
        'foodMarkerId': foodMarkerId,
        'foodName': foodName,
        'lastMessage': images != null && images.isNotEmpty ? '📷 Image' : message,
        'unreadCount': 0,
      };
      
      print('Sender conversation path: userConversations/$currentUserId/$conversationId');
      print('Sender conversation data: $senderConvData');
      
      try {
        await _database
            .child('userConversations')
            .child(currentUserId)
            .child(conversationId)
            .set(senderConvData);
        print('✅ Sender conversation list updated');
      } catch (e) {
        print('❌ Error updating sender conversation list: $e');
        throw e;
      }

      // Try to update recipient's conversation list
      print('📋 Attempting to update recipient conversation list...');
      final recipientConvData = {
        'otherUserId': currentUserId,
        'lastMessageTimestamp': timestampValue,
        'conversationId': conversationId,
        'otherUserName': currentUserName,
        'foodMarkerId': foodMarkerId,
        'foodName': foodName,
        'lastMessage': images != null && images.isNotEmpty ? '📷 Image' : message,
        'unreadCount': 1,
      };
      
      print('Recipient conversation path: userConversations/$recipientId/$conversationId');
      print('Recipient conversation data: $recipientConvData');
      
      try {
        await _database
            .child('userConversations')
            .child(recipientId)
            .child(conversationId)
            .set(recipientConvData);
        print('✅ Recipient conversation list updated');
      } catch (e) {
        print('⚠️ Could not update recipient conversation list: $e');
        print('This is expected if the recipient hasn\'t opened the chat yet');
      }
      
      print('🔵 SEND MESSAGE DEBUG END - SUCCESS');
    } catch (e) {
      print('🔴 SEND MESSAGE DEBUG END - FAILED');
      throw Exception('Failed to send message: $e');
    }
  }

  /// Generates a consistent conversation ID for two users
  String _getConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  /// Returns a stream of the current user's conversations
  Stream<List<Map<String, dynamic>>> getUserConversations() {
    return _database
        .child('userConversations')
        .child(currentUserId)
        .orderByChild('lastMessageTimestamp')
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
        final aTime = a['lastMessageTimestamp'] ?? 0;
        final bTime = b['lastMessageTimestamp'] ?? 0;
        return bTime.compareTo(aTime);
      });

      return conversations;
    });
  }

  /// Returns a stream of messages for a specific conversation
  Stream<List<Map<String, dynamic>>> getConversationMessages(String conversationId) {
    print('🔵 GET MESSAGES DEBUG');
    print('Current User ID: $currentUserId');
    print('Conversation ID: $conversationId');
    print('Messages path: conversations/$conversationId/messages');
    
    return _database
        .child('conversations')
        .child(conversationId)
        .child('messages')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
      if (!event.snapshot.exists) {
        print('No messages found in conversation');
        return <Map<String, dynamic>>[];
      }

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final messages = <Map<String, dynamic>>[];

      data.forEach((key, value) {
        final message = Map<String, dynamic>.from(value);
        
        // Ensure backward compatibility
        if (!message.containsKey('text') && message.containsKey('message')) {
          message['text'] = message['message'];
        }
        
        messages.add(message);
      });

      // Sort messages by timestamp (oldest first for chat display)
      messages.sort((a, b) {
        final aTime = a['timestamp'] ?? 0;
        final bTime = b['timestamp'] ?? 0;
        return aTime.compareTo(bTime);
      });

      print('Found ${messages.length} messages');
      return messages;
    });
  }

  /// Marks conversation as read - only updates what we have permission for
  Future<void> markConversationAsRead(String conversationId) async {
    print('🔵 MARK AS READ DEBUG START');
    print('Current User ID: $currentUserId');
    print('Conversation ID: $conversationId');
    
    try {
      // Only update the unread count in user's own conversation list
      print('📋 Updating unread count in user conversation list...');
      print('Path: userConversations/$currentUserId/$conversationId');
      try {
        await _database
            .child('userConversations')
            .child(currentUserId)
            .child(conversationId)
            .update({
          'unreadCount': 0,
        });
        print('✅ Unread count updated');
      } catch (e) {
        print('❌ Error updating unread count: $e');
        print('This might happen if the conversation entry doesn\'t exist yet');
      }

      // Get all messages to mark as read
      print('🔍 Getting messages to mark as read...');
      final messagesRef = _database
          .child('conversations')
          .child(conversationId)
          .child('messages');

      final snapshot = await messagesRef.get();
      if (!snapshot.exists) {
        print('No messages to mark as read');
        return;
      }
      
      final data = snapshot.value as Map<dynamic, dynamic>;
      final updates = <String, dynamic>{};
      int messagesToUpdate = 0;

      data.forEach((messageId, messageValue) {
        final messageData = Map<String, dynamic>.from(messageValue);
        
        // Only mark as read if we're the recipient and message is unread
        if (messageData['recipientId'] == currentUserId && 
            messageData['read'] != true) {
          updates['$messageId/read'] = true;
          messagesToUpdate++;
        }
      });

      print('Found $messagesToUpdate messages to mark as read');

      // Update all messages at once if there are any updates
      if (updates.isNotEmpty) {
        print('📝 Updating message read status...');
        print('Updates: $updates');
        try {
          await messagesRef.update(updates);
          print('✅ Messages marked as read');
        } catch (e) {
          print('❌ Error marking messages as read: $e');
          print('Error details: ${e.toString()}');
        }
      }
    } catch (e) {
      print('🔴 MARK AS READ DEBUG END - ERROR: $e');
    }
    
    print('🔵 MARK AS READ DEBUG END');
  }

  /// Returns a stream of the total unread message count
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

  /// Initialize conversation for recipient when they first open it
  Future<void> initializeUserConversation(String conversationId) async {
    print('🔵 INITIALIZE CONVERSATION DEBUG START');
    print('Current User ID: $currentUserId');
    print('Conversation ID: $conversationId');
    
    try {
      // Check if user already has this conversation
      final userConvRef = _database
          .child('userConversations')
          .child(currentUserId)
          .child(conversationId);
          
      print('🔍 Checking if user conversation exists...');
      final existingSnapshot = await userConvRef.get();
      if (existingSnapshot.exists) {
        print('User conversation already exists');
        return;
      }

      // Get conversation details
      print('🔍 Getting conversation details...');
      final conversationRef = _database.child('conversations').child(conversationId);
      final snapshot = await conversationRef.get();
      
      if (!snapshot.exists) {
        print('Conversation does not exist');
        return;
      }
      
      final conversationData = snapshot.value as Map<dynamic, dynamic>;
      final participants = conversationData['participants'] as Map<dynamic, dynamic>;
      
      print('Participants: $participants');
      
      // Check if current user is a participant
      if (!participants.containsKey(currentUserId)) {
        print('Current user is not a participant');
        return;
      }
      
      // Find the other user
      String? otherUserId;
      participants.forEach((userId, value) {
        if (userId != currentUserId) {
          otherUserId = userId as String;
        }
      });
      
      if (otherUserId == null) {
        print('Could not find other user');
        return;
      }
      
      print('Other User ID: $otherUserId');
      
      // Get other user's name
      print('🔍 Getting other user name...');
      final otherUserSnapshot = await _database
          .child('users')
          .child(otherUserId!)
          .child('displayName')
          .get();
      
      final otherUserName = otherUserSnapshot.value as String? ?? 'Unknown User';
      print('Other User Name: $otherUserName');
      
      // Count unread messages
      int unreadCount = 0;
      if (conversationData['messages'] != null) {
        final messages = conversationData['messages'] as Map<dynamic, dynamic>;
        messages.forEach((messageId, messageData) {
          final message = Map<String, dynamic>.from(messageData);
          if (message['recipientId'] == currentUserId && 
              message['read'] != true) {
            unreadCount++;
          }
        });
      }
      
      print('Unread count: $unreadCount');
      
      // Create user conversation entry
      final userConvData = {
        'otherUserId': otherUserId,
        'lastMessageTimestamp': conversationData['lastMessageTimestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        'conversationId': conversationId,
        'otherUserName': otherUserName,
        'foodMarkerId': conversationData['foodMarkerId'] ?? '',
        'foodName': conversationData['foodName'] ?? '',
        'lastMessage': conversationData['lastMessage'] ?? '',
        'unreadCount': unreadCount,
      };
      
      print('📝 Creating user conversation entry...');
      print('User conversation data: $userConvData');
      
      try {
        await userConvRef.set(userConvData);
        print('✅ User conversation created');
      } catch (e) {
        print('❌ Error creating user conversation: $e');
        throw e;
      }
    } catch (e) {
      print('🔴 INITIALIZE CONVERSATION DEBUG END - ERROR: $e');
    }
    
    print('🔵 INITIALIZE CONVERSATION DEBUG END');
  }

  /// Development utility: Deletes a conversation and all its messages
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

  // Legacy: Delete conversation only for self
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