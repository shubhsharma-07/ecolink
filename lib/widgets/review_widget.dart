import 'package:flutter/material.dart';
import '../services/review_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class ReviewWidget extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final bool showReviewButton;

  const ReviewWidget({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    this.showReviewButton = true,
  });

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
  bool _hasReviewed = false;
  String _sortOption = 'newest';

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
    _hasReviewed = await _reviewService.hasReviewed(widget.targetUserId);
    if (mounted) setState(() {});
  }

  Future<void> _deleteReview(String reviewId) async {
    try {
      await _reviewService.deleteReview(reviewId);
      await _initializeData(); // Refresh data after deletion
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review deleted successfully')),
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
        const SnackBar(
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
            title: const Row(
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
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else if (e.toString().contains('permission-denied')) {
        // If we get a permission error but the review was actually saved
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
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
      padding: const EdgeInsets.all(12),
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
              const SizedBox(width: 8),
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
          const SizedBox(height: 8),
          Text(
            'You need to exchange at least ${ReviewService.REQUIRED_MESSAGES} messages with ${widget.targetUserName} before you can leave a review.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _messageCount >= ReviewService.REQUIRED_MESSAGES
                  ? () => _showReviewDialog()
                  : null,
              icon: const Icon(Icons.rate_review),
              label: const Text('Write Review'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A74C),
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
        final screenWidth = MediaQuery.of(context).size.width;
        final isTablet = screenWidth > 600;
        
        return AlertDialog(
          title: const Text('Write Review'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('How would you rate your experience with ${widget.targetUserName}?'),
                const SizedBox(height: 16),
                // Star rating with FittedBox to prevent overflow
                Center(
                  child: SizedBox(
                    width: isTablet ? 280 : double.infinity, // Limit width on tablets
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  selectedRating = index + 1;
                                });
                              },
                              borderRadius: BorderRadius.circular(24),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  index < selectedRating ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                  size: 44, // This will scale down if needed
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: dialogCommentController,
                  decoration: const InputDecoration(
                    labelText: 'Your Review',
                    hintText: 'Share your experience...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedRating > 0
                  ? () => _submitReview(selectedRating, dialogCommentController.text)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A74C),
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    // Sort reviews based on selected option
    List<Map<String, dynamic>> sortedReviews = List.from(_reviews);
    switch (_sortOption) {
      case 'oldest':
        sortedReviews.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
        break;
      case 'highest':
        sortedReviews.sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));
        break;
      case 'lowest':
        sortedReviews.sort((a, b) => (a['rating'] ?? 0).compareTo(b['rating'] ?? 0));
        break;
      case 'newest':
      default:
        sortedReviews.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showReviewButton && !_hasReviewed) ...[
          _buildReviewButton(),
          const SizedBox(height: 16),
        ],
        if (_reviews.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Sort by:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _sortOption,
                items: const [
                  DropdownMenuItem(value: 'newest', child: Text('Newest')),
                  DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                  DropdownMenuItem(value: 'highest', child: Text('Highest Rated')),
                  DropdownMenuItem(value: 'lowest', child: Text('Lowest Rated')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _sortOption = value;
                    });
                  }
                },
              ),
            ],
          ),
          const Divider(),
        ],
        if (_reviews.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedReviews.length,
            itemBuilder: (context, index) {
              final review = sortedReviews[index];
              final isMyReview = review['reviewerId'] == _reviewService.currentUserId;
              final timestamp = review['timestamp'] as int;
              final date = DateTime.fromMillisecondsSinceEpoch(timestamp);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            '${review['rating']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          if (isMyReview)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteReview(review['id']),
                              tooltip: 'Delete Review',
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        review['comment'] ?? '',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            review['reviewerName'] ?? 'Anonymous User',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
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