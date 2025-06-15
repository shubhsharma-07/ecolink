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

      // Update trust score - handle any errors here without throwing
      try {
        await _updateTrustScore(reviewedId);
      } catch (e) {
        print('Warning: Failed to update trust score: $e');
        // Don't throw the error, as the review was successfully saved
      }
    } catch (e) {
      print('Error submitting review: $e');
      rethrow;
    }
  }

  // Update trust score for a user
  Future<void> _updateTrustScore(String userId) async {
    try {
      // Get all reviews for the user
      final reviewsSnapshot = await _database
          .child('userReviews')
          .orderByChild('reviewedId')
          .equalTo(userId)
          .get();

      if (!reviewsSnapshot.exists) {
        // If no reviews exist, set to 0 with timestamp
        await _database.child('userTrustScores').child(userId).set({
          'score': 0.0,
          'lastUpdated': ServerValue.timestamp
        });
        return;
      }

      final reviews = reviewsSnapshot.value as Map<dynamic, dynamic>;
      double totalRating = 0;
      int reviewCount = 0;

      reviews.forEach((key, value) {
        if (value['rating'] != null) {
          totalRating += (value['rating'] as num).toDouble();
          reviewCount++;
        }
      });

      final averageRating = reviewCount > 0 ? totalRating / reviewCount : 0.0;
      
      // First update the user's own trust score
      await _database.child('userTrustScores').child(userId).set({
        'score': averageRating,
        'lastUpdated': ServerValue.timestamp
      });

      // Then update the reviewer's trust score if they don't have one
      final reviewerScoreSnapshot = await _database
          .child('userTrustScores')
          .child(currentUserId)
          .get();

      if (!reviewerScoreSnapshot.exists) {
        await _database.child('userTrustScores').child(currentUserId).set({
          'score': 0.0,
          'lastUpdated': ServerValue.timestamp
        });
      }
    } catch (e) {
      print('Error updating trust score: $e');
      // Don't throw the error, just log it
      // The review was already saved successfully
    }
  }

  // Get user's trust score
  Future<double> getUserTrustScore(String userId) async {
    try {
      final trustScoreSnapshot = await _database
          .child('userTrustScores')
          .child(userId)
          .get();

      if (!trustScoreSnapshot.exists) return 0.0;

      final trustScoreData = trustScoreSnapshot.value as Map<dynamic, dynamic>;
      return (trustScoreData['score'] as num).toDouble();
    } catch (e) {
      print('Error getting trust score: $e');
      return 0.0;
    }
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

      final reviewedId = reviewData['reviewedId'];
      await _database.child('userReviews').child(reviewId).remove();
      await _updateTrustScore(reviewedId);
    } catch (e) {
      print('Error deleting review: $e');
      rethrow;
    }
  }
} 