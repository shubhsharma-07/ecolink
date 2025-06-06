import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  // Get current user email
  String? get currentUserEmail => _auth.currentUser?.email;

  // Get current user display name - FIXED VERSION
  String get currentUserDisplayName {
    try {
      final user = _auth.currentUser;
      if (user?.displayName != null && user!.displayName!.isNotEmpty) {
        return user.displayName!;
      }
      final email = user?.email;
      if (email != null && email.isNotEmpty) {
        return email.split('@')[0];
      }
      return 'User';
    } catch (e) {
      print('Error getting display name: $e');
      return 'User';
    }
  }

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with email and password - IMPROVED VERSION
  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    try {
      // Sign out first to clear any cached data
      if (_auth.currentUser != null) {
        await _auth.signOut();
        // Add a small delay to ensure cleanup
        await Future.delayed(Duration(milliseconds: 500));
      }
      
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Reload user to get fresh data
      await credential.user?.reload();
      
      await _updateUserProfile(credential.user);
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Login failed: ${e.toString()}';
    }
  }

  // Register with email and password - IMPROVED VERSION
  Future<UserCredential?> registerWithEmailAndPassword(
    String email, 
    String password, 
    String displayName
  ) async {
    try {
      // Sign out first to clear any cached data
      if (_auth.currentUser != null) {
        await _auth.signOut();
        await Future.delayed(Duration(milliseconds: 500));
      }
      
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Update display name
      await credential.user?.updateDisplayName(displayName);
      await credential.user?.reload();
      
      // Save user profile to database
      await _saveUserProfile(credential.user!, displayName);
      
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Registration failed: ${e.toString()}';
    }
  }

  // Sign in anonymously
  Future<UserCredential?> signInAnonymously() async {
    try {
      final credential = await _auth.signInAnonymously();
      await _updateUserProfile(credential.user);
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Sign out - IMPROVED VERSION
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      // Add delay to ensure complete cleanup
      await Future.delayed(Duration(milliseconds: 300));
    } catch (e) {
      print('Error signing out: $e');
      // Force sign out even if there's an error
      await _auth.signOut();
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Save user profile to database - IMPROVED VERSION
  Future<void> _saveUserProfile(User user, String displayName) async {
    try {
      await _database.child('users').child(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': displayName,
        'createdAt': ServerValue.timestamp,
        'lastLoginAt': ServerValue.timestamp,
      });
    } catch (e) {
      print('Error saving user profile: $e');
      // Don't throw error - this shouldn't prevent login
    }
  }

  // Update user profile on login - IMPROVED VERSION
  Future<void> _updateUserProfile(User? user) async {
    if (user == null) return;
    
    try {
      // Check if user exists in database first
      final userRef = _database.child('users').child(user.uid);
      final snapshot = await userRef.get();
      
      if (snapshot.exists) {
        // Update existing user
        await userRef.update({
          'lastLoginAt': ServerValue.timestamp,
        });
      } else {
        // Create new user profile if it doesn't exist
        await userRef.set({
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName': user.displayName ?? user.email?.split('@')[0] ?? 'User',
          'createdAt': ServerValue.timestamp,
          'lastLoginAt': ServerValue.timestamp,
        });
      }
    } catch (e) {
      print('Error updating user profile: $e');
      // Don't throw error - this shouldn't prevent login
    }
  }

  // Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'invalid-email':
        return 'Email address is not valid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'too-many-requests':
        return 'Too many requests. Try again later.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled.';
      case 'invalid-credential':
        return 'The provided credentials are invalid.';
      case 'user-mismatch':
        return 'The provided credentials do not match the current user.';
      case 'requires-recent-login':
        return 'This operation requires recent authentication. Please log in again.';
      default:
        return 'Authentication failed: ${e.message}';
    }
  }

  // Get user profile from database - IMPROVED VERSION
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final snapshot = await _database.child('users').child(userId).get();
      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value;
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      print('Error getting user profile: $e');
    }
    return null;
  }

  // Check if user is logged in
  bool get isLoggedIn => _auth.currentUser != null;

  // Check if user is anonymous
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  // Force refresh current user - NEW METHOD
  Future<void> refreshCurrentUser() async {
    try {
      await _auth.currentUser?.reload();
    } catch (e) {
      print('Error refreshing user: $e');
    }
  }

  // Clear auth state - NEW METHOD
  Future<void> clearAuthState() async {
    try {
      await signOut();
      await Future.delayed(Duration(milliseconds: 500));
    } catch (e) {
      print('Error clearing auth state: $e');
    }
  }
}