import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReviewService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user ID
  String get currentUserId => _auth.currentUser?.uid ?? '';
  String get currentUserName => _auth.currentUser?.email?.split('@')[0] ?? 'Anonymous User';

  static const int REQUIRED_MESSAGES = 5;

  // Check if current user can review another user
  Future<bool> canReviewUser(String targetUserId) async {
    try {
      // Can't review yourself
      if (currentUserId == targetUserId) return false;

      // Check message count
      final messageCount = await getMessageCount(targetUserId);
      return messageCount >= REQUIRED_MESSAGES;
    } catch (e) {
      print('Error checking review permission: $e');
      return false;
    }
  }

  Future<int> getMessageCount(String targetUserId) async {
    try {
      // Get conversation ID
      final conversationId = _getConversationId(currentUserId, targetUserId);
      
      // Get messages from both users
      final messagesSnapshot = await _database
          .child('conversations')
          .child(conversationId)
          .child('messages')
          .get();

      if (!messagesSnapshot.exists) return 0;

      int currentUserMessages = 0;
      int targetUserMessages = 0;

      for (var message in messagesSnapshot.children) {
        final messageData = message.value as Map<dynamic, dynamic>;
        if (messageData['senderId'] == currentUserId) {
          currentUserMessages++;
        } else if (messageData['senderId'] == targetUserId) {
          targetUserMessages++;
        }
      }

      print('Message count - Current user: $currentUserMessages, Target user: $targetUserMessages');
      return currentUserMessages + targetUserMessages;
    } catch (e) {
      print('Error getting message count: $e');
      return 0;
    }
  }

  String _getConversationId(String user1Id, String user2Id) {
    final sortedIds = [user1Id, user2Id]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  // Submit a new review
  Future<void> submitReview({
    required String reviewedId,
    required int rating,
    required String comment,
  }) async {
    try {
      // Check if user has already reviewed this person
      final existingReviewsSnapshot = await _database
          .child('userReviews')
          .orderByChild('reviewerId')
          .equalTo(currentUserId)
          .get();

      if (existingReviewsSnapshot.exists) {
        final reviews = existingReviewsSnapshot.value as Map<dynamic, dynamic>;
        final hasExistingReview = reviews.values.any((review) => 
          review['reviewedId'] == reviewedId
        );

        if (hasExistingReview) {
          throw Exception('ALREADY_REVIEWED');
        }
      }

      // Create a new review ID
      final reviewId = 'review_${DateTime.now().millisecondsSinceEpoch}';
      
      // Create the review data
      final reviewData = {
        'reviewerId': currentUserId,
        'reviewedId': reviewedId,
        'rating': rating,
        'comment': comment,
        'timestamp': ServerValue.timestamp,
        'reviewerName': currentUserName,
      };

      // Save the review
      await _database.child('userReviews').child(reviewId).set(reviewData);
    } catch (e) {
      print('Error submitting review: $e');
      rethrow;
    }
  }

  // Get average rating from reviews
  Future<double> getAverageRating(String userId) async {
    try {
      final reviews = await getUserReviews(userId);
      if (reviews.isEmpty) return 0.0;

      double totalRating = 0;
      for (var review in reviews) {
        totalRating += (review['rating'] as num).toDouble();
      }
      return totalRating / reviews.length;
    } catch (e) {
      print('Error calculating average rating: $e');
      return 0.0;
    }
  }

  // Get user's trust score
  Future<double> getUserTrustScore(String userId) async {
    return getAverageRating(userId);
  }

  // Get all reviews for a user
  Future<List<Map<String, dynamic>>> getUserReviews(String userId) async {
    try {
      final snapshot = await _database
          .child('userReviews')
          .orderByChild('reviewedId')
          .equalTo(userId)
          .get();

      if (!snapshot.exists) return [];

      final reviews = <Map<String, dynamic>>[];
      for (var review in snapshot.children) {
        final reviewData = review.value as Map<dynamic, dynamic>;
        reviews.add({
          'id': review.key,
          'reviewerId': reviewData['reviewerId'],
          'reviewerName': reviewData['reviewerName'],
          'rating': reviewData['rating'],
          'comment': reviewData['comment'],
          'timestamp': reviewData['timestamp'],
        });
      }

      // Sort reviews by timestamp (newest first)
      reviews.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
      return reviews;
    } catch (e) {
      print('Error getting user reviews: $e');
      return [];
    }
  }

  // Delete a review
  Future<void> deleteReview(String reviewId) async {
    try {
      final reviewSnapshot = await _database.child('userReviews').child(reviewId).get();
      if (!reviewSnapshot.exists) {
        throw Exception('Review not found');
      }

      final reviewData = reviewSnapshot.value as Map<dynamic, dynamic>;
      if (reviewData['reviewerId'] != currentUserId) {
        throw Exception('You can only delete your own reviews');
      }

      await _database.child('userReviews').child(reviewId).remove();
    } catch (e) {
      print('Error deleting review: $e');
      rethrow;
    }
  }

  // Returns true if the current user has already reviewed the target user
  Future<bool> hasReviewed(String targetUserId) async {
    try {
      final existingReviewsSnapshot = await _database
          .child('userReviews')
          .orderByChild('reviewerId')
          .equalTo(currentUserId)
          .get();

      if (existingReviewsSnapshot.exists) {
        final reviews = existingReviewsSnapshot.value as Map<dynamic, dynamic>;
        final hasExistingReview = reviews.values.any((review) =>
          review['reviewedId'] == targetUserId
        );
        return hasExistingReview;
      }
      return false;
    } catch (e) {
      print('Error checking if already reviewed: $e');
      return false;
    }
  }
} 