import 'package:flutter/material.dart';
import '../services/messaging_service.dart';
import '../screens/chat_screen.dart';

/// A button widget that initiates messaging with another user
/// Opens a dialog to compose and send a message about a food listing
class MessageButton extends StatelessWidget {
  /// The unique identifier of the message recipient
  final String recipientId;
  
  /// The display name of the message recipient
  final String recipientName;
  
  /// The unique identifier of the food marker being discussed
  final String foodMarkerId;
  
  /// The name of the food item being discussed
  final String foodName;
  
  /// Whether the button is being displayed on the current user's marker
  final bool isMyMarker;

  const MessageButton({
    super.key,
    required this.recipientId,
    required this.recipientName,
    required this.foodMarkerId,
    required this.foodName,
    required this.isMyMarker,
  });

  @override
  Widget build(BuildContext context) {
    // Don't show message button for own markers
    if (isMyMarker) {
      return const SizedBox.shrink();
    }

    return OutlinedButton.icon(
      onPressed: () => _showMessageDialog(context),
      icon: const Icon(Icons.message, size: 18),
      label: const Text('Message', style: TextStyle(fontSize: 14)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.blue,
        side: const BorderSide(color: Colors.blue),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  /// Shows the message composition dialog
  void _showMessageDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext dialogContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
          ),
          child: MessageBottomSheet(
            recipientId: recipientId,
            recipientName: recipientName,
            foodMarkerId: foodMarkerId,
            foodName: foodName,
          ),
        );
      },
    );
  }
}

/// A dialog widget for composing and sending messages
/// Includes food item context and message composition interface
class MessageBottomSheet extends StatefulWidget {
  /// The unique identifier of the message recipient
  final String recipientId;
  
  /// The display name of the message recipient
  final String recipientName;
  
  /// The unique identifier of the food marker being discussed
  final String foodMarkerId;
  
  /// The name of the food item being discussed
  final String foodName;

  const MessageBottomSheet({
    super.key,
    required this.recipientId,
    required this.recipientName,
    required this.foodMarkerId,
    required this.foodName,
  });

  @override
  State<MessageBottomSheet> createState() => _MessageBottomSheetState();
}

class _MessageBottomSheetState extends State<MessageBottomSheet> {
  final TextEditingController _messageController = TextEditingController();
  final MessagingService _messagingService = MessagingService();
  bool _isLoading = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.message, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Message ${widget.recipientName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.restaurant, color: Colors.orange[700], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'About: ${widget.foodName}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                              Text(
                                'Messaging ${widget.recipientName}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Your message:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Hi! I\'m interested in your ${widget.foodName}...',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.chat_bubble_outline),
                    ),
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    autofocus: false,
                  ),
                  const SizedBox(height: 80), // Space for floating button
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: FloatingActionButton.extended(
                onPressed: _isLoading ? null : _sendMessage,
                label: Text(_isLoading ? 'Sending...' : 'Send Message'),
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sends the composed message and navigates to the chat screen
  /// Shows loading state and feedback via snackbar
  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a message'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _messagingService.sendMessage(
        recipientId: widget.recipientId,
        recipientName: widget.recipientName,
        foodMarkerId: widget.foodMarkerId,
        foodName: widget.foodName,
        message: message,
      );

      // Close dialog and navigate to chat
      Navigator.of(context).pop();
      
      // Get conversation ID and navigate to chat
      final conversationId = _getConversationId(
        _messagingService.currentUserId,
        widget.recipientId,
      );
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversationId,
            otherUserId: widget.recipientId,
            otherUserName: widget.recipientName,
            foodName: widget.foodName,
            foodMarkerId: widget.foodMarkerId,
          ),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message sent to ${widget.recipientName}!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Generates a consistent conversation ID for two users
  /// Ensures same ID regardless of who initiates the conversation
  String _getConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }
}