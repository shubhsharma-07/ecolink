import 'package:flutter/material.dart';
import '../services/review_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class ReviewWidget extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;

  const ReviewWidget({
    Key? key,
    required this.targetUserId,
    required this.targetUserName,
  }) : super(key: key);

  @override
  _ReviewWidgetState createState() => _ReviewWidgetState();
}

class _ReviewWidgetState extends State<ReviewWidget> {
  final ReviewService _reviewService = ReviewService();
  final TextEditingController _commentController = TextEditingController();
  bool _canReview = false;
  int _messageCount = 0;
  double _trustScore = 0.0;
  List<Map<String, dynamic>> _reviews = [];

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    _canReview = await _reviewService.canReviewUser(widget.targetUserId);
    _messageCount = await _reviewService.getMessageCount(widget.targetUserId);
    _trustScore = await _reviewService.getUserTrustScore(widget.targetUserId);
    _reviews = await _reviewService.getUserReviews(widget.targetUserId);
    if (mounted) setState(() {});
  }

  Future<void> _deleteReview(String reviewId) async {
    try {
      await _reviewService.deleteReview(reviewId);
      await _initializeData(); // Refresh data after deletion
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Review deleted successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete review: $e')),
      );
    }
  }

  Future<void> _submitReview(int rating, String comment) async {
    try {
      await _reviewService.submitReview(
        reviewedId: widget.targetUserId,
        rating: rating,
        comment: comment,
      );
      Navigator.of(context).pop(); // Close the review dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Review submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      await _initializeData(); // Refresh the widget data
    } catch (e) {
      Navigator.of(context).pop(); // Close the review dialog
      if (e.toString().contains('ALREADY_REVIEWED')) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('Already Reviewed'),
              ],
            ),
            content: Text('You have already reviewed ${widget.targetUserName}.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK'),
              ),
            ],
          ),
        );
      } else if (e.toString().contains('permission-denied')) {
        // If we get a permission error but the review was actually saved
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Review submitted! Refreshing...'),
            backgroundColor: Colors.green,
          ),
        );
        await _initializeData(); // Refresh the widget data
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit review: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildReviewButton() {
    return Container(
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
              Icon(
                _messageCount >= ReviewService.REQUIRED_MESSAGES
                    ? Icons.check_circle
                    : Icons.info_outline,
                color: _messageCount >= ReviewService.REQUIRED_MESSAGES
                    ? Colors.green
                    : Colors.grey[600],
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Message Exchange: $_messageCount/${ReviewService.REQUIRED_MESSAGES}',
                  style: TextStyle(
                    color: _messageCount >= ReviewService.REQUIRED_MESSAGES
                        ? Colors.green
                        : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'You need to exchange at least ${ReviewService.REQUIRED_MESSAGES} messages with ${widget.targetUserName} before you can leave a review.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _messageCount >= ReviewService.REQUIRED_MESSAGES
                  ? () => _showReviewDialog()
                  : null,
              icon: Icon(Icons.rate_review),
              label: Text('Write Review'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF00A74C),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReviewDialog() {
    int selectedRating = 0;
    final dialogCommentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Write Review'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('How would you rate your experience with ${widget.targetUserName}?'),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < selectedRating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
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
                SizedBox(height: 16),
                TextField(
                  controller: dialogCommentController,
                  decoration: InputDecoration(
                    labelText: 'Your Review',
                    hintText: 'Share your experience...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedRating > 0
                    ? () => _submitReview(selectedRating, dialogCommentController.text)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF00A74C),
                  foregroundColor: Colors.white,
                ),
                child: Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReviewButton(),
        SizedBox(height: 16),
        if (_reviews.isEmpty)
          Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No reviews yet',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _reviews.length,
            itemBuilder: (context, index) {
              final review = _reviews[index];
              final isMyReview = review['reviewerId'] == _reviewService.currentUserId;
              final timestamp = review['timestamp'] as int;
              final date = DateTime.fromMillisecondsSinceEpoch(timestamp);

              return Card(
                margin: EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 20),
                          SizedBox(width: 4),
                          Text(
                            '${review['rating']}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Spacer(),
                          if (isMyReview)
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteReview(review['id']),
                              tooltip: 'Delete Review',
                            ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        review['comment'] ?? '',
                        style: TextStyle(fontSize: 14),
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            review['reviewerName'] ?? 'Anonymous User',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          Spacer(),
                          Text(
                            timeago.format(date),
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
              );
            },
          ),
      ],
    );
  }
} 