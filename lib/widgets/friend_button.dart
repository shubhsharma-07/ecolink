import 'package:flutter/material.dart';
import '../services/friends_service.dart';

/// A dynamic button widget that handles friend request interactions
/// Displays different states based on friendship status and handles all friend-related actions
class FriendButton extends StatefulWidget {
  /// The unique identifier of the target user
  final String userId;
  
  /// The display name of the target user
  final String userName;
  
  /// Whether the button is being displayed on the current user's marker
  final bool isMyMarker;

  const FriendButton({
    Key? key,
    required this.userId,
    required this.userName,
    required this.isMyMarker,
  }) : super(key: key);

  @override
  _FriendButtonState createState() => _FriendButtonState();
}

class _FriendButtonState extends State<FriendButton> {
  final FriendsService _friendsService = FriendsService();
  FriendshipStatus _status = FriendshipStatus.none;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isMyMarker && widget.userId.isNotEmpty) {
      _loadFriendshipStatus();
    }
  }

  /// Loads the current friendship status with the target user
  /// Only loads if the button is not on the current user's marker
  Future<void> _loadFriendshipStatus() async {
    if (widget.userId.isEmpty || widget.isMyMarker) return;
    
    try {
      print('Loading friendship status for: ${widget.userId}');
      final status = await _friendsService.getFriendshipStatus(widget.userId);
      if (mounted) {
        setState(() {
          _status = status;
        });
        print('Friendship status loaded: $status');
      }
    } catch (e) {
      print('Error loading friendship status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show friend button for own markers
    if (widget.isMyMarker || widget.userId.isEmpty) {
      return SizedBox.shrink();
    }

    return _buildFriendButton();
  }

  /// Builds the appropriate button based on friendship status
  /// Includes loading state and different visual styles for each status
  Widget _buildFriendButton() {
    if (_isLoading) {
      return Container(
        width: 120,
        height: 36,
        child: OutlinedButton(
          onPressed: null,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    switch (_status) {
      case FriendshipStatus.none:
        return OutlinedButton.icon(
          onPressed: _sendFriendRequest,
          icon: Icon(Icons.person_add, size: 18),
          label: Text('Add Friend'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.blue,
            side: BorderSide(color: Colors.blue),
          ),
        );

      case FriendshipStatus.pending:
        return OutlinedButton.icon(
          onPressed: _cancelFriendRequest,
          icon: Icon(Icons.schedule, size: 18),
          label: Text('Pending'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
            side: BorderSide(color: Colors.orange),
          ),
        );

      case FriendshipStatus.requested:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _acceptFriendRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                child: Text('Accept', style: TextStyle(fontSize: 12)),
              ),
            ),
            SizedBox(width: 4),
            Expanded(
              child: OutlinedButton(
                onPressed: _declineFriendRequest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                child: Text('Decline', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        );

      case FriendshipStatus.friends:
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green[50],
            border: Border.all(color: Colors.green),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 16, color: Colors.green),
              SizedBox(width: 4),
              Text(
                'Friends',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
    }
  }

  /// Sends a friend request to the target user
  /// Updates UI state and shows feedback via snackbar
  Future<void> _sendFriendRequest() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('Sending friend request to: ${widget.userId} (${widget.userName})');
      
      await _friendsService.sendFriendRequest(
        recipientId: widget.userId,
        recipientName: widget.userName,
      );

      setState(() {
        _status = FriendshipStatus.pending;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Friend request sent to ${widget.userName}!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      print('Error sending friend request: $e');
      
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send friend request: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Cancels an outgoing friend request
  /// Shows confirmation dialog and updates UI state
  Future<void> _cancelFriendRequest() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Friend Request'),
        content: Text('Cancel your friend request to ${widget.userName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep Request'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[700],
              foregroundColor: Colors.white,
            ),
            child: Text('Cancel'),
          ),
        ],
      ),
    );

    if (shouldCancel == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        await _friendsService.cancelFriendRequest(widget.userId);

        setState(() {
          _status = FriendshipStatus.none;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Friend request to ${widget.userName} cancelled'),
            backgroundColor: Colors.grey[700],
          ),
        );

      } catch (e) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel friend request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _acceptFriendRequest() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get the actual request data from incoming requests
      final incomingRequests = await _friendsService.getIncomingFriendRequests().first;
      final requestData = incomingRequests.firstWhere(
        (request) => request['senderId'] == widget.userId,
        orElse: () => <String, dynamic>{},
      );

      if (requestData.isEmpty) {
        throw Exception('Friend request not found');
      }

      final requestId = requestData['requestId'];
      
      await _friendsService.acceptFriendRequest(
        requestId,
        widget.userId,
        widget.userName,
      );

      setState(() {
        _status = FriendshipStatus.friends;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You and ${widget.userName} are now friends!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      print('Error accepting friend request: $e');
      
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept friend request'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _declineFriendRequest() async {
    final shouldDecline = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Decline Friend Request'),
        content: Text('Decline the friend request from ${widget.userName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text('Decline'),
          ),
        ],
      ),
    );

    if (shouldDecline == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Get the actual request data from incoming requests
        final incomingRequests = await _friendsService.getIncomingFriendRequests().first;
        final requestData = incomingRequests.firstWhere(
          (request) => request['senderId'] == widget.userId,
          orElse: () => <String, dynamic>{},
        );

        if (requestData.isEmpty) {
          throw Exception('Friend request not found');
        }

        final requestId = requestData['requestId'];
        
        await _friendsService.declineFriendRequest(requestId, widget.userId);

        setState(() {
          _status = FriendshipStatus.none;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Friend request from ${widget.userName} declined'),
            backgroundColor: Colors.orange,
          ),
        );

      } catch (e) {
        print('Error declining friend request: $e');
        
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline friend request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}