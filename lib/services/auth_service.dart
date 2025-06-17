import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Service class that handles all authentication-related operations
/// Manages user authentication state, sign-in, registration, and profile management
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  /// Returns the currently authenticated user
  User? get currentUser => _auth.currentUser;

  /// Returns the unique identifier of the current user
  String? get currentUserId => _auth.currentUser?.uid;

  /// Returns the email address of the current user
  String? get currentUserEmail => _auth.currentUser?.email;

  /// Returns the display name of the current user
  /// Falls back to email username if display name is not set
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

  /// Stream of authentication state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Authenticates a user with email and password
  /// Clears any existing session before attempting to sign in
  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    try {
      // Clear existing session
      if (_auth.currentUser != null) {
        await _auth.signOut();
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      await credential.user?.reload();
      await _updateUserProfile(credential.user);
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Login failed: ${e.toString()}';
    }
  }

  /// Creates a new user account with email and password
  /// Sets up initial user profile in the database
  Future<UserCredential?> registerWithEmailAndPassword(
    String email, 
    String password, 
    String displayName
  ) async {
    try {
      // Clear existing session
      if (_auth.currentUser != null) {
        await _auth.signOut();
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      await credential.user?.updateDisplayName(displayName);
      await credential.user?.reload();
      await _saveUserProfile(credential.user!, displayName);
      
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Registration failed: ${e.toString()}';
    }
  }

  /// Signs in a user anonymously
  /// Creates a temporary user profile for unauthenticated users
  Future<UserCredential?> signInAnonymously() async {
    try {
      final credential = await _auth.signInAnonymously();
      await _updateUserProfile(credential.user);
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Signs out the current user and clears the session
  Future<void> signOut() async {
    try {
      // Clear any cached user data first
      await _database.child('users').child(_auth.currentUser?.uid ?? '').get().then((snapshot) {
        if (snapshot.exists) {
          snapshot.ref.remove();
        }
      });
      
      // Sign out from Firebase Auth
      await _auth.signOut();
      
      // Add a delay to ensure all cleanup is complete
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print('Error signing out: $e');
      // Force sign out even if there's an error
      await _auth.signOut();
    }
  }

  /// Sends a password reset email to the specified email address
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Saves a new user profile to the database
  /// Creates initial user data structure with timestamps
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
    }
  }

  /// Updates an existing user's profile in the database
  /// Creates a new profile if one doesn't exist
  Future<void> _updateUserProfile(User? user) async {
    if (user == null) return;
    
    try {
      final userRef = _database.child('users').child(user.uid);
      final snapshot = await userRef.get();
      
      if (snapshot.exists) {
        await userRef.update({
          'lastLoginAt': ServerValue.timestamp,
        });
      } else {
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
    }
  }

  /// Handles Firebase authentication exceptions
  /// Returns user-friendly error messages for common auth errors
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

  /// Retrieves a user's profile data from the database
  /// Returns null if the profile doesn't exist or there's an error
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

  /// Checks if a user is currently logged in
  bool get isLoggedIn => _auth.currentUser != null;

  /// Checks if the current user is anonymous
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  /// Forces a refresh of the current user's data
  Future<void> refreshCurrentUser() async {
    try {
      await _auth.currentUser?.reload();
    } catch (e) {
      print('Error refreshing user: $e');
    }
  }

  /// Completely clears the authentication state
  /// Useful for logging out and cleaning up
  Future<void> clearAuthState() async {
    try {
      // Clear any existing user data
      if (_auth.currentUser != null) {
        await _database.child('users').child(_auth.currentUser!.uid).get().then((snapshot) {
          if (snapshot.exists) {
            snapshot.ref.remove();
          }
        });
      }
      
      // Sign out
      await signOut();
      
      // Add a longer delay to ensure complete cleanup
      await Future.delayed(const Duration(milliseconds: 1000));
    } catch (e) {
      print('Error clearing auth state: $e');
      // Force sign out even if there's an error
      await _auth.signOut();
    }
  }
}