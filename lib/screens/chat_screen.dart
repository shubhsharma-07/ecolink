import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import '../services/messaging_service.dart';
import '../services/review_service.dart';
import '../services/auth_service.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String foodName;
  final String foodMarkerId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    required this.foodName,
    required this.foodMarkerId,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessagingService _messagingService = MessagingService();
  final ReviewService _reviewService = ReviewService();
  final AuthService _authService = AuthService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final List<File> _selectedImages = [];
  bool _isSending = false;
  bool _hasShownReviewNotification = false;
  bool _canReview = false;
  bool _hasReviewed = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    print('🟦 CHAT SCREEN INITIALIZATION START');
    print('Conversation ID: ${widget.conversationId}');
    print('Other User ID: ${widget.otherUserId}');
    print('Other User Name: ${widget.otherUserName}');
    print('Food Name: ${widget.foodName}');
    print('Food Marker ID: ${widget.foodMarkerId}');
    
    try {
      // Initialize user conversation entry if needed (for recipients)
      print('📋 Initializing user conversation...');
      await _messagingService.initializeUserConversation(widget.conversationId);
      
      // Mark conversation as read
      print('👁️ Marking conversation as read...');
      await _messagingService.markConversationAsRead(widget.conversationId);
      
      // Check review eligibility
      print('⭐ Checking review eligibility...');
      await _checkReviewEligibility();
      await _checkIfReviewed();
      
      setState(() {
        _isInitialized = true;
      });
      print('🟦 CHAT SCREEN INITIALIZATION COMPLETE');
    } catch (e) {
      print('🔴 Error initializing chat: $e');
      // Continue anyway - don't block the chat
      setState(() {
        _isInitialized = true;
      });
    }
  }

  Future<String?> _convertImageToBase64(File imageFile) async {
    try {
      if (!await imageFile.exists()) return null;
      
      // Check file size (limit to 1MB for base64)
      final fileSize = await imageFile.length();
      if (fileSize > 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image is too large. Please select a smaller image.'),
            backgroundColor: Colors.orange,
          ),
        );
        return null;
      }
      
      final bytes = await imageFile.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      print('Error converting image: $e');
      return null;
    }
  }

  void _showImagePickerModal() {
    if (_selectedImages.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 3 images per message'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(context);
                  final image = await _imagePicker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 1024,
                    maxHeight: 1024,
                    imageQuality: 70,
                  );
                  if (image != null) {
                    setState(() {
                      _selectedImages.add(File(image.path));
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final image = await _imagePicker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1024,
                    maxHeight: 1024,
                    imageQuality: 70,
                  );
                  if (image != null) {
                    setState(() {
                      _selectedImages.add(File(image.path));
                    });
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReviewDialog() {
    int selectedRating = 0;
    final TextEditingController reviewController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.star, color: Color(0xFF00A74C)),
                SizedBox(width: 8),
                Text('Write Review'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'How would you rate ${widget.otherUserName}?',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < selectedRating ? Icons.star : Icons.star_border,
                        color: index < selectedRating ? Colors.amber : Colors.grey,
                        size: 32,
                      ),
                      onPressed: () {
                        setState(() {
                          selectedRating = index + 1;
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reviewController,
                  decoration: const InputDecoration(
                    labelText: 'Your Review',
                    hintText: 'Share your experience...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  maxLength: 500,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedRating == 0 || reviewController.text.trim().isEmpty
                    ? null
                    : () async {
                  try {
                    await _reviewService.submitReview(
                      reviewedId: widget.otherUserId,
                      rating: selectedRating,
                      comment: reviewController.text.trim(),
                    );
                    
                    if (mounted) {
                      Navigator.pop(context);
                      setState(() {
                        _hasReviewed = true;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Review submitted successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    print('Error submitting review: $e');
                    if (mounted) {
                      Navigator.pop(context);
                      if (e.toString().contains('ALREADY_REVIEWED')) {
                        setState(() {
                          _hasReviewed = true;
                        });
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.orange),
                                SizedBox(width: 8),
                                Text('Already Reviewed'),
                              ],
                            ),
                            content: Text('You have already reviewed ${widget.otherUserName}.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to submit review. Please try again.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A74C),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Submit Review'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReviewNotification() {
    if (_hasReviewed || !_canReview || !_hasShownReviewNotification) {
      return const SizedBox.shrink();
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.star, color: Colors.green.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You can now review each other!',
                      style: TextStyle(
                        color: Colors.green.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You\'ve exchanged enough messages to leave a review.',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showReviewDialog,
              icon: const Icon(Icons.rate_review),
              label: const Text('Write Review'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A74C),
                foregroundColor: Colors.white,
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            GestureDetector(
              onTap: () => _showProfileDetails(context),
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.otherUserName.isNotEmpty ? widget.otherUserName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUserName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.restaurant, size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'About: ${widget.foodName}',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagingService.getConversationMessages(widget.conversationId),
              builder: (context, snapshot) {
                if (!_isInitialized || snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00A74C)),
                  );
                }

                if (snapshot.hasError) {
                  print('🔴 StreamBuilder error: ${snapshot.error}');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text('Error loading messages'),
                        const SizedBox(height: 8),
                        Text(
                          'Error: ${snapshot.error}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isInitialized = false;
                            });
                            _initializeChat();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start the conversation about ${widget.foodName}!',
                          style: TextStyle(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                // Mark as read when messages are displayed
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  try {
                    await _messagingService.markConversationAsRead(widget.conversationId);
                  } catch (e) {
                    print('🔴 Error in addPostFrameCallback: $e');
                  }
                  
                  // Auto-scroll to bottom
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: messages.length + (_hasShownReviewNotification && !_hasReviewed ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_hasShownReviewNotification && !_hasReviewed && index == messages.length) {
                      return _buildReviewNotification();
                    }
                    final message = messages[index];
                    final isMe = message['senderId'] == _messagingService.currentUserId;
                    
                    return _buildMessageBubble(message, isMe);
                  },
                );
              },
            ),
          ),
          if (_selectedImages.isNotEmpty)
            Container(
              height: 100,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _selectedImages[index],
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 12,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedImages.removeAt(index);
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
                  );
                },
              ),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final timestamp = message['timestamp'];
    final hasImages = message['hasImages'] == true;
    final images = List<String>.from(message['images'] ?? []);
    // Handle both 'text' and 'message' fields for backward compatibility
    final messageText = message['text'] ?? message['message'] ?? '';
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF00A74C) : Colors.grey[200],
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
            bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImages && images.isNotEmpty) ...[
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _showFullScreenImage(images[index]),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            base64Decode(images[index]),
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 200,
                                height: 200,
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image, color: Colors.grey),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (messageText.isNotEmpty) const SizedBox(height: 8),
            ],
            if (messageText.isNotEmpty)
              Text(
                messageText,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatMessageTimestamp(timestamp),
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message['read'] == true ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message['read'] == true ? Colors.blue[200] : Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenImage(String base64Image) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image.memory(
                    base64Decode(base64Image),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? Colors.grey[900] : Colors.white;
    final borderColor = isDarkMode ? Colors.grey[700] : Colors.grey[300];
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final hintColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(color: borderColor!),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.add_photo_alternate,
                color: _selectedImages.length >= 3 ? Colors.grey : const Color(0xFF00A74C),
              ),
              onPressed: _showImagePickerModal,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: hintColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(color: Color(0xFF00A74C)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              mini: true,
              backgroundColor: _isSending || (_messageController.text.trim().isEmpty && _selectedImages.isEmpty)
                  ? Colors.grey
                  : const Color(0xFF00A74C),
              foregroundColor: Colors.white,
              onPressed: _isSending ? null : _sendMessage,
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMessageTimestamp(dynamic timestamp) {
    try {
      final DateTime dateTime;
      if (timestamp is int) {
        dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else {
        return '';
      }

      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }

  Future<void> _sendMessage() async {
    print('🟦 SEND MESSAGE BUTTON CLICKED');
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty && _selectedImages.isEmpty) {
      print('No message text or images - returning');
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      List<String> base64Images = [];
      if (_selectedImages.isNotEmpty) {
        for (var image in _selectedImages) {
          final base64Image = await _convertImageToBase64(image);
          if (base64Image != null) {
            base64Images.add(base64Image);
          }
        }
      }

      print('📤 Calling messaging service sendMessage...');
      await _messagingService.sendMessage(
        recipientId: widget.otherUserId,
        recipientName: widget.otherUserName,
        foodMarkerId: widget.foodMarkerId,
        foodName: widget.foodName,
        message: messageText,
        images: base64Images.isNotEmpty ? base64Images : null,
      );

      _messageController.clear();
      setState(() {
        _selectedImages.clear();
      });

      // Check if we can review after sending a message
      await _checkReviewEligibility();

      // Scroll to bottom after sending
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      print('🔴 Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: ${e.toString()}'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _sendMessage,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _showProfileDetails(BuildContext context) {
    // Implementation remains the same
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.4,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.otherUserName.isNotEmpty 
                              ? widget.otherUserName[0].toUpperCase() 
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.otherUserName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.restaurant, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                widget.foodName,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'User profile details will be shown here',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _checkReviewEligibility() async {
    try {
      final messageCount = await _reviewService.getMessageCount(widget.otherUserId);
      print('📊 Message count for review eligibility: $messageCount');
      if (messageCount >= ReviewService.REQUIRED_MESSAGES && !_hasShownReviewNotification) {
        setState(() {
          _canReview = true;
          _hasShownReviewNotification = true;
        });
      }
    } catch (e) {
      print('Error checking review eligibility: $e');
    }
  }

  Future<void> _checkIfReviewed() async {
    try {
      final reviewed = await _reviewService.hasReviewed(widget.otherUserId);
      print('📊 Has already reviewed: $reviewed');
      if (mounted) {
        setState(() {
          _hasReviewed = reviewed;
        });
      }
    } catch (e) {
      print('Error checking if reviewed: $e');
    }
  }
}