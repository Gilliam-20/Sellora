import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

/// Thin wrapper over FirebaseAuth. Kept deliberately dumb — it only
/// knows about authentication, never about Firestore user documents or
/// roles. AuthRepository composes this with FirestoreService to build
/// the full [UserModel].
class AuthService extends GetxService {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signUp(
      {required String email, required String password}) {
    return _auth.createUserWithEmailAndPassword(
        email: email, password: password);
  }

  Future<UserCredential> signIn(
      {required String email, required String password}) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() => _auth.signOut();
}
