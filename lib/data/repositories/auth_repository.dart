import 'package:get/get.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

abstract class AuthRepository {
  Stream<UserModel?> get userChanges;
  UserModel? get cachedUser;

  Future<UserModel> signIn({required String email, required String password});
  Future<UserModel> signUpBuyer({required String name, required String email, required String password});
  Future<UserModel> signUpSeller({
    required String name,
    required String email,
    required String password,
    required String storeName,
    required String phone,
  });
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
  Future<void> updateUser(UserModel user);
}

/// Firebase-backed implementation. Composes [AuthService] (identity)
/// with [FirestoreService] (the `users` document holding role, store
/// name, subscription state, etc).
class FirebaseAuthRepository extends GetxService implements AuthRepository {
  final AuthService _auth = Get.find<AuthService>();
  final FirestoreService _fs = Get.find<FirestoreService>();

  UserModel? _cached;

  @override
  UserModel? get cachedUser => _cached;

  @override
  Stream<UserModel?> get userChanges async* {
    await for (final fbUser in _auth.authStateChanges) {
      if (fbUser == null) {
        _cached = null;
        yield null;
        continue;
      }
      final doc = await _fs.users.doc(fbUser.uid).get();
      if (doc.exists) {
        _cached = UserModel.fromMap(doc.data()!);
        yield _cached;
      } else {
        yield null;
      }
    }
  }

  @override
  Future<UserModel> signIn({required String email, required String password}) async {
    final cred = await _auth.signIn(email: email, password: password);
    final doc = await _fs.users.doc(cred.user!.uid).get();
    _cached = UserModel.fromMap(doc.data()!);
    return _cached!;
  }

  @override
  Future<UserModel> signUpBuyer({required String name, required String email, required String password}) async {
    final cred = await _auth.signUp(email: email, password: password);
    final user = UserModel(
      uid: cred.user!.uid,
      name: name,
      email: email,
      role: UserRole.buyer,
      createdAt: DateTime.now(),
    );
    await _fs.users.doc(user.uid).set(user.toMap());
    _cached = user;
    return user;
  }

  @override
  Future<UserModel> signUpSeller({
    required String name,
    required String email,
    required String password,
    required String storeName,
    required String phone,
  }) async {
    final cred = await _auth.signUp(email: email, password: password);
    final user = UserModel(
      uid: cred.user!.uid,
      name: name,
      email: email,
      phone: phone,
      role: UserRole.seller,
      storeName: storeName,
      sellerStatus: SellerStatus.pendingApproval,
      createdAt: DateTime.now(),
    );
    await _fs.users.doc(user.uid).set(user.toMap());
    _cached = user;
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) => _auth.sendPasswordReset(email);

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> updateUser(UserModel user) async {
    await _fs.users.doc(user.uid).update(user.toMap());
    _cached = user;
  }
}
