import 'package:get/get.dart';
import '../../core/utils/slug.dart';
import '../models/store_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'store_repository.dart';

abstract class AuthRepository {
  Stream<UserModel?> get userChanges;
  UserModel? get cachedUser;

  Future<UserModel> signIn({required String email, required String password});

  /// [storeId] is the store (see StoreModel) the buyer is registering as
  /// a customer of — every buyer belongs to exactly one store.
  Future<UserModel> signUpBuyer({
    required String name,
    required String email,
    required String password,
    required String storeId,
  });
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
  FirebaseAuthRepository({StoreRepository? storeRepository})
      : _storeRepository = storeRepository ?? Get.find<StoreRepository>();

  final AuthService _auth = Get.find<AuthService>();
  final FirestoreService _fs = Get.find<FirestoreService>();
  final StoreRepository _storeRepository;

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
  Future<UserModel> signIn(
      {required String email, required String password}) async {
    final cred = await _auth.signIn(email: email, password: password);
    final doc = await _fs.users.doc(cred.user!.uid).get();
    _cached = UserModel.fromMap(doc.data()!);
    return _cached!;
  }

  @override
  Future<UserModel> signUpBuyer({
    required String name,
    required String email,
    required String password,
    required String storeId,
  }) async {
    final cred = await _auth.signUp(email: email, password: password);
    final user = UserModel(
      uid: cred.user!.uid,
      name: name,
      email: email,
      role: UserRole.buyer,
      storeId: storeId,
      createdAt: DateTime.now(),
    );
    // Global identity doc (role bootstrap, same as every other role) plus
    // a mirror under the store's own tenant tree, so Firestore rules can
    // authorize store-scoped reads without ever touching `users`.
    await _fs.users.doc(user.uid).set(user.toMap());
    await _fs.storeCustomers(storeId).doc(user.uid).set(user.toMap());
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
    await _createStoreForSeller(sellerId: user.uid, storeName: storeName);
    _cached = user;
    return user;
  }

  /// Every seller needs a [StoreModel] to have anything to sell against —
  /// without this, a freshly-registered seller has no store at all
  /// (see WORKLOG.md, 2026-09-11). One store per seller for now; a
  /// store-switcher for multi-store sellers is future work.
  Future<void> _createStoreForSeller(
      {required String sellerId, required String storeName}) async {
    final base = slugify(storeName);
    var slug = base;
    var suffix = 2;
    while (await _storeRepository.storeBySlug(slug) != null) {
      slug = '$base-$suffix';
      suffix++;
    }
    await _storeRepository.createStore(StoreModel(
      id: 'store-$sellerId',
      slug: slug,
      sellerId: sellerId,
      name: storeName,
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordReset(email);

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> updateUser(UserModel user) async {
    await _fs.users.doc(user.uid).update(user.toMap());
    _cached = user;
  }
}
