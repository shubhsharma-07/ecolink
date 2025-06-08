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
    Key? key,
    required this.recipientId,
    required this.recipientName,
    required this.foodMarkerId,
    required this.foodName,
    required this.isMyMarker,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Don't show message button for own markers
    if (isMyMarker) {
      return SizedBox.shrink();
    }

    return OutlinedButton.icon(
      onPressed: () => _showMessageDialog(context),
      icon: Icon(Icons.message, size: 18),
      label: Text('Message'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.blue,
        side: BorderSide(color: Colors.blue),
      ),
    );
  }

  /// Shows the message composition dialog
  void _showMessageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return MessageDialog(
          recipientId: recipientId,
          recipientName: recipientName,
          foodMarkerId: foodMarkerId,
          foodName: foodName,
        );
      },
    );
  }
}

/// A dialog widget for composing and sending messages
/// Includes food item context and message composition interface
class MessageDialog extends StatefulWidget {
  /// The unique identifier of the message recipient
  final String recipientId;
  
  /// The display name of the message recipient
  final String recipientName;
  
  /// The unique identifier of the food marker being discussed
  final String foodMarkerId;
  
  /// The name of the food item being discussed
  final String foodName;

  const MessageDialog({
    Key? key,
    required this.recipientId,
    required this.recipientName,
    required this.foodMarkerId,
    required this.foodName,
  }) : super(key: key);

  @override
  _MessageDialogState createState() => _MessageDialogState();
}

class _MessageDialogState extends State<MessageDialog> {
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
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.message, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text('Message ${widget.recipientName}'),
          ),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.restaurant, color: Colors.orange[700], size: 20),
                  SizedBox(width: 8),
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
            SizedBox(height: 16),
            Text(
              'Your message:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Hi! I\'m interested in your ${widget.foodName}...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.chat_bubble_outline),
              ),
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _sendMessage,
          icon: _isLoading 
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(Icons.send, size: 16),
          label: Text(_isLoading ? 'Sending...' : 'Send Message'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  /// Sends the composed message and navigates to the chat screen
  /// Shows loading state and feedback via snackbar
  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
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