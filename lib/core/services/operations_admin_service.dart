import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/core_models.dart';
import 'operational_insights.dart';

/// Human-readable error (Arabic) thrown by direct user provisioning.
class UserProvisionException implements Exception {
  final String message;
  const UserProvisionException(this.message);
  @override
  String toString() => message;
}

class OperationsAdminService {
  final FirebaseFirestore firestore;

  OperationsAdminService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users => firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _operations => firestore.collection('operations');
  CollectionReference<Map<String, dynamic>> get _cycles => firestore.collection('work_cycles');
  CollectionReference<Map<String, dynamic>> get _dumpsites => firestore.collection('dumpsites');

  Stream<QuerySnapshot<Map<String, dynamic>>> activeCycles() =>
      _cycles.limit(50).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> dumpsites({bool includeInactive = false}) {
    final q = _dumpsites;
    return includeInactive ? q.limit(100).snapshots() : q.where('isActive', isEqualTo: true).limit(100).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> activeWorkforce() =>
      _users.where('isActive', isEqualTo: true).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> cycleUsers(String cycleId, {String? actorId}) {
    Query<Map<String, dynamic>> q = _users.where('cycleId', isEqualTo: cycleId);
    if (actorId != null && actorId.trim().isNotEmpty) {
      q = q.where('municipalityCoordinatorId', isEqualTo: actorId.trim());
    }
    return q.orderBy('name').snapshots();
  }

  Future<void> createWorkCycle({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required String createdBy,
  }) async {
    if (!endDate.isAfter(startDate)) {
      throw ArgumentError('Work cycle end date must be after the start date.');
    }
    final ref = _cycles.doc();
    await ref.set({
      'id': ref.id,
      'name': name.trim(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'status': 'active',
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archiveCycle(String cycleId, {required String archivedBy}) async {
    await _cycles.doc(cycleId).update({
      'status': 'archived',
      'archivedBy': archivedBy,
      'archivedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteWorkCycle(String cycleId) async {
    await _cycles.doc(cycleId).delete();
  }

  Future<void> addDumpsite({
    required String nameAr,
    required String nameEn,
    required double capacity,
    required double fillPercentage,
    String? code,
    String? location,
    double? latitude,
    double? longitude,
    required String actorId,
  }) async {
    final ar = nameAr.trim();
    final en = nameEn.trim();
    if (ar.isEmpty || en.isEmpty) throw ArgumentError('Dumpsite names are required.');
    if (capacity < 0) throw ArgumentError('Capacity cannot be negative.');
    if (fillPercentage < 0 || fillPercentage > 100) throw ArgumentError('Fill percentage must be between 0 and 100.');
    final ref = _dumpsites.doc();
    await ref.set({
      'id': ref.id,
      'name': ar,
      'nameAr': ar,
      'nameEn': en,
      'code': code?.trim() ?? '',
      'location': location?.trim() ?? '',
      if (latitude != null && longitude != null) 'locationGeo': GeoPoint(latitude, longitude),
      'capacity': capacity,
      'fillPercentage': fillPercentage,
      'isActive': true,
      'createdBy': actorId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final confirmed = await ref.get(const GetOptions(source: Source.server));
    if (!confirmed.exists || confirmed.data()?['createdBy'] != actorId) {
      throw StateError('لم يتم تأكيد حفظ المكب على الخادم. تحقق من القائمة قبل إعادة المحاولة.');
    }
  }

  Future<void> updateDumpsite({
    required String dumpsiteId,
    required String nameAr,
    required String nameEn,
    required double capacity,
    required double fillPercentage,
    String? code,
    String? location,
    double? latitude,
    double? longitude,
    required bool isActive,
    required String actorId,
  }) async {
    final ar = nameAr.trim();
    final en = nameEn.trim();
    if (ar.isEmpty || en.isEmpty) throw ArgumentError('Dumpsite names are required.');
    if (capacity < 0) throw ArgumentError('Capacity cannot be negative.');
    if (fillPercentage < 0 || fillPercentage > 100) throw ArgumentError('Fill percentage must be between 0 and 100.');
    await _dumpsites.doc(dumpsiteId).update({
      'name': ar,
      'nameAr': ar,
      'nameEn': en,
      'code': code?.trim() ?? '',
      'location': location?.trim() ?? '',
      if (latitude != null && longitude != null) 'locationGeo': GeoPoint(latitude, longitude),
      'capacity': capacity,
      'fillPercentage': fillPercentage,
      'isActive': isActive,
      'updatedBy': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setDumpsiteActive(String dumpsiteId, bool active, {required String actorId}) async {
    await _dumpsites.doc(dumpsiteId).update({
      'isActive': active,
      'updatedBy': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Creates a Group Supervisor / Worker account directly from the app
  /// (Firebase Auth + Firestore profile). No Cloud Functions required.
  Future<Map<String, dynamic>> provisionUser({
    required String name,
    required String username,
    required String role,
    required String cycleId,
    required String groupId,
    required String phone,
    String password = '',
    String email = '',
    String employeeId = '',
    String jobTitle = '',
    String notes = '',
  }) async {
    if (role != 'group_supervisor' && role != 'worker') {
      throw ArgumentError('Only Group Supervisor and Worker accounts can be provisioned here.');
    }
    return _createUserDirect(
      name: name, username: username, role: role, phone: phone, password: password,
      contactEmail: email, employeeId: employeeId, jobTitle: jobTitle, notes: notes,
      cycleId: cycleId, groupId: groupId,
    );
  }

  /// Creates a Level 2 / 3 / 4 account directly from the app.
  Future<Map<String, dynamic>> provisionManagementUser({
    required String name,
    required String username,
    required String role,
    required String phone,
    String scope = 'assigned_only',
    String password = '',
    String email = '',
    String employeeId = '',
    String jobTitle = '',
    String notes = '',
    String municipalityName = '',
  }) async {
    if (!const ['donor_manager', 'jsc_coordinator', 'municipality_coordinator'].contains(role)) {
      throw ArgumentError('Management provisioning supports Level 2, Level 3, and Level 4 only.');
    }
    return _createUserDirect(
      name: name, username: username, role: role, phone: phone, password: password,
      contactEmail: email, employeeId: employeeId, jobTitle: jobTitle, notes: notes,
      scope: scope,
      municipalityName: municipalityName,
    );
  }

  static const _workforceRoles = ['worker', 'group_supervisor'];
  static const _managementRoles = ['donor_manager', 'jsc_coordinator', 'municipality_coordinator'];

  Future<FirebaseApp> _provisioningApp() async {
    try {
      return Firebase.app('userProvisioning');
    } catch (_) {
      return Firebase.initializeApp(name: 'userProvisioning', options: Firebase.app().options);
    }
  }

  String _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _authErrorMessage(FirebaseAuthException e) => switch (e.code) {
        'email-already-in-use' => 'اسم المستخدم أو البريد مستخدم مسبقًا.',
        'weak-password' => 'كلمة المرور ضعيفة، استخدم 8 أحرف على الأقل.',
        'invalid-email' => 'اسم المستخدم غير صالح.',
        'network-request-failed' => 'لا يوجد اتصال بالإنترنت. إنشاء المستخدمين يتطلب اتصالًا.',
        'operation-not-allowed' => 'تسجيل الدخول بالبريد وكلمة المرور غير مفعّل في Firebase Authentication.',
        'too-many-requests' => 'محاولات كثيرة، انتظر قليلًا ثم أعد المحاولة.',
        _ => 'تعذر إنشاء الحساب: ${e.message ?? e.code}',
      };

  Future<Map<String, dynamic>> _createUserDirect({
    required String name,
    required String username,
    required String role,
    required String phone,
    required String password,
    required String contactEmail,
    required String employeeId,
    required String jobTitle,
    required String notes,
    String scope = 'assigned_only',
    String cycleId = '',
    String groupId = '',
    String municipalityName = '',
  }) async {
    final actorAuth = FirebaseAuth.instance.currentUser;
    if (actorAuth == null) {
      throw const UserProvisionException('يجب تسجيل الدخول أونلاين لإنشاء المستخدمين.');
    }

    // 1) Verify the actor from Firestore (server-side rules enforce it again).
    final DocumentSnapshot<Map<String, dynamic>> actorSnap;
    try {
      actorSnap = await _users.doc(actorAuth.uid).get(const GetOptions(source: Source.server));
    } on FirebaseException catch (_) {
      throw const UserProvisionException('تعذر التحقق من صلاحيتك. تأكد من الاتصال بالإنترنت.');
    }
    final actor = actorSnap.data() ?? const <String, dynamic>{};
    final actorRole = '${actor['role'] ?? ''}';
    if (actor['isActive'] == false) throw const UserProvisionException('حسابك غير نشط.');
    final isWorkforce = _workforceRoles.contains(role);
    if (isWorkforce && actorRole != 'municipality_coordinator') {
      throw const UserProvisionException('فقط منسق البلدية (L2) يضيف العاملين ومشرفي المجموعات.');
    }
    if (!isWorkforce && (!_managementRoles.contains(role) || actorRole != 'donor_manager')) {
      throw const UserProvisionException('فقط المدير الأعلى (L4) يضيف حسابات الإدارة.');
    }

    // 2) Validate input.
    final cleanName = name.trim();
    var login = username.trim().toLowerCase();
    if (cleanName.isEmpty || login.isEmpty) {
      throw const UserProvisionException('الاسم واسم المستخدم مطلوبان.');
    }
    if (!login.contains('@') && !RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch(login)) {
      throw const UserProvisionException('اسم المستخدم: حروف إنجليزية صغيرة وأرقام و . _ - فقط (3 إلى 30 حرفًا).');
    }
    final loginEmail = login.contains('@') ? login : '$login@solidwaste.local';
    login = login.replaceAll(RegExp(r'@solidwaste\.local$'), '');
    final pass = password.isEmpty ? _generatePassword() : password;
    if (pass.length < 8) throw const UserProvisionException('كلمة المرور يجب ألا تقل عن 8 أحرف.');

    final cleanCycle = cycleId.trim();
    final cleanGroup = groupId.trim();
    if (isWorkforce) {
      if (cleanCycle.isEmpty || cleanGroup.isEmpty) {
        throw const UserProvisionException('حسابات العاملين تحتاج دورة عمل ومجموعة.');
      }
      final cycle = await _cycles.doc(cleanCycle).get();
      if (!cycle.exists || cycle.data()?['status'] != 'active') {
        throw const UserProvisionException('دورة العمل المختارة غير نشطة.');
      }
    }

    // 3) Create the Auth account on a secondary app so the manager stays signed in.
    final app = await _provisioningApp();
    final secondaryAuth = FirebaseAuth.instanceFor(app: app);
    UserCredential cred;
    try {
      cred = await secondaryAuth.createUserWithEmailAndPassword(email: loginEmail, password: pass);
    } on FirebaseAuthException catch (e) {
      await app.delete().catchError((_) {});
      throw UserProvisionException(_authErrorMessage(e));
    }
    final newUser = cred.user!;

    // 4) Write profile + audit atomically (transaction = requires connection, never queued offline).
    try {
      final userRef = _users.doc(newUser.uid);
      final auditRef = firestore.collection('audit').doc();
      await firestore.runTransaction((tx) async {
        tx.set(userRef, {
          'id': newUser.uid,
          'username': login,
          'email': loginEmail,
          if (contactEmail.trim().isNotEmpty) 'contactEmail': contactEmail.trim().toLowerCase(),
          'name': cleanName,
          'role': role,
          'scope': scope,
          if (municipalityName.trim().isNotEmpty && role == 'municipality_coordinator') 'municipalityName': municipalityName.trim(),
          'phone': phone.trim(),
          'employeeId': employeeId.trim(),
          'jobTitle': jobTitle.trim(),
          'notes': notes.trim(),
          'groupId': isWorkforce ? cleanGroup : null,
          'municipalityCoordinatorId': isWorkforce ? actorAuth.uid : null,
          'cycleId': isWorkforce ? cleanCycle : null,
          'isActive': true,
          'status': 'active',
          'createdBy': actorAuth.uid,
          'createdByRole': actorRole,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(auditRef, {
          'actorId': actorAuth.uid,
          'operation': 'PROVISION_USER',
          'targetId': newUser.uid,
          'after': {'username': login, 'role': role, 'cycleId': isWorkforce ? cleanCycle : null, 'groupId': isWorkforce ? cleanGroup : null},
          'createdAt': DateTime.now().toIso8601String(),
          'timestamp': FieldValue.serverTimestamp(),
          'immutable': true,
        });
      });
    } on FirebaseException catch (e) {
      // Roll back the Auth account so no orphan login is left behind.
      await newUser.delete().catchError((_) {});
      await app.delete().catchError((_) {});
      if (e.code == 'permission-denied') {
        throw const UserProvisionException('رفضت قواعد Firestore العملية. انشر ملف firestore.rules المحدّث (firebase deploy --only firestore:rules).');
      }
      throw UserProvisionException('تعذر حفظ ملف المستخدم: ${e.message ?? e.code}');
    }

    await secondaryAuth.signOut().catchError((_) {});
    await app.delete().catchError((_) {});
    return {
      'uid': newUser.uid,
      'username': login,
      'email': loginEmail,
      'temporaryPassword': pass,
      'passwordWasProvided': password.isNotEmpty,
      'role': role,
    };
  }

  /// Live list of the accounts the actor manages (updates instantly after creation).
  Stream<QuerySnapshot<Map<String, dynamic>>> managedUsers({required String actorId, required String actorRole}) {
    if (actorRole == 'municipality_coordinator') {
      return _users.where('municipalityCoordinatorId', isEqualTo: actorId).snapshots();
    }
    return _users.snapshots();
  }

  /// Live counters computed straight from the users collection.
  Stream<Map<String, dynamic>> userStats({required String actorId, required String actorRole}) {
    return managedUsers(actorId: actorId, actorRole: actorRole).map((snap) {
      final roles = <String, int>{};
      var active = 0;
      for (final d in snap.docs) {
        final x = d.data();
        final r = '${x['role'] ?? ''}';
        roles[r] = (roles[r] ?? 0) + 1;
        if (x['isActive'] != false) active++;
      }
      return {'totalUsers': snap.docs.length, 'activeUsers': active, 'roles': roles};
    });
  }

  /// Delete directly on Firebase using a privileged callable function.
  /// GitHub is only used to publish code; it is not part of the runtime path.
  /// Never report success until the server confirms both account removals.
  Future<void> deleteManagedUser(String userId, {required String actorId}) async {
    final uid = userId.trim();
    final actor = actorId.trim();
    if (uid.isEmpty || actor.isEmpty || uid == actor) {
      throw StateError('لا يمكن حذف الحساب الحالي.');
    }
    try {
      final response = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('deleteManagedUser')
          .call(<String, dynamic>{'userId': uid});
      final data = response.data;
      if (data is! Map || data['ok'] != true || data['userId'] != uid) {
        throw StateError('لم يؤكد Firebase حذف الحساب نهائيًا.');
      }
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'تعذر حذف الحساب مباشرة من Firebase. تحقق من نشر وظيفة deleteManagedUser وصلاحيات الحساب.');
    }
  }

  /// Level 4 only: activate / deactivate any account (blocks its next login).
  Future<void> setUserActive(String userId, bool active, {required String actorId}) async {
    await _users.doc(userId).update({
      'isActive': active,
      'status': active ? 'active' : 'deactivated',
      if (!active) 'deactivatedBy': actorId,
      if (!active) 'deactivatedAt': FieldValue.serverTimestamp(),
      'updatedBy': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> aiCommandCenterState() =>
      firestore.collection('ai_state').doc('command_center').snapshots();

  Future<Map<String, dynamic>> liveOperationalSnapshot(AppUser user) async {
    final db = firestore;
    final opsSnap = await _operations.limit(1000).get();
    final dumpsSnap = await _dumpsites.limit(200).get();
    bool visible(Map<String, dynamic> record) => OperationalInsights.visibleToUser(
      record, role: user.role, userId: user.id,
      scope: user.scope, groupId: user.groupId,
    );
    var activeUsers = 0;
    var workers = 0;
    var supervisors = 0;
    final groupIds = <String>{};
    if (user.role == 'group_supervisor' || user.role == 'worker') {
      final self = await _users.doc(user.id).get();
      final x = self.data();
      if (x != null) {
        if (x['isActive'] != false) activeUsers = 1;
        if (x['isActive'] != false && x['role'] == 'worker') workers = 1;
        if (x['isActive'] != false && x['role'] == 'group_supervisor') supervisors = 1;
        final g = '${x['groupId'] ?? ''}'.trim();
        if (g.isNotEmpty) groupIds.add(g);
      }
    } else {
      Query<Map<String, dynamic>> usersQuery = _users.limit(500);
      if (user.role == 'municipality_coordinator') {
        usersQuery = _users.where('municipalityCoordinatorId', isEqualTo: user.id).limit(500);
      }
      final usersSnap = await usersQuery.get();
      for (final d in usersSnap.docs) {
        final x = d.data();
        if (x['isActive'] == false || !visible(x)) continue;
        activeUsers++;
        final role = '${x['role'] ?? ''}';
        if (role == 'worker') workers++;
        if (role == 'group_supervisor') supervisors++;
        final g = '${x['groupId'] ?? ''}'.trim();
        if (g.isNotEmpty) groupIds.add(g);
      }
    }
    var trips = 0;
    var emergencies = 0;
    var reports = 0;
    for (final d in opsSnap.docs) {
      final x = d.data();
      if (!visible(x)) continue;
      final e = '${x['_entity'] ?? ''}';
      if (e == 'trip') trips++;
      if (e == 'emergency' && OperationalInsights.isOpenAlert(x)) emergencies++;
      if (e == 'report') reports++;
    }
    var activeDumpsites = 0;
    var criticalDumpsites = 0;
    for (final d in dumpsSnap.docs) {
      final x = d.data();
      if (x['isActive'] != true || x['isDeleted'] == true) continue;
      activeDumpsites++;
      final fill = x['fillPercentage'];
      final value = fill is num ? fill.toDouble() : double.tryParse('$fill') ?? 0;
      if (value >= 85) criticalDumpsites++;
    }
    return {
      'activeUsers': activeUsers,
      'workers': workers,
      'supervisors': supervisors,
      'groups': groupIds.length,
      'trips': trips,
      'emergencies': emergencies,
      'reports': reports,
      'activeDumpsites': activeDumpsites,
      'criticalDumpsites': criticalDumpsites,
      'scopeLimited': user.role == 'jsc_coordinator' || user.role == 'municipality_coordinator',
      'countsMayBePartial': opsSnap.docs.length >= 1000 || dumpsSnap.docs.length >= 200,
      'checkedAt': DateTime.now(),
      'firebase': db.app.name,
    };
  }

  Future<void> freezeCycleUsers(String cycleId, {required String actorId}) async {
    if (FirebaseAuth.instance.currentUser?.uid != actorId) {
      throw StateError('انتهت الجلسة أو لا تملك صلاحية التجميد.');
    }
    final cycle = await _cycles.doc(cycleId)
        .get(const GetOptions(source: Source.server));
    final endValue = cycle.data()?['endDate'];
    final endDate = endValue is Timestamp ? endValue.toDate()
        : DateTime.tryParse('${endValue ?? ''}');
    if (!cycle.exists || endDate == null ||
        DateTime.now().isBefore(endDate)) {
      throw StateError('لا يمكن تجميد الدورة قبل انتهاء تاريخها المحدد.');
    }
    final query = _users
        .where('municipalityCoordinatorId', isEqualTo: actorId)
        .where('cycleId', isEqualTo: cycleId)
        .where('isActive', isEqualTo: true);
    final snap = await query.get(const GetOptions(source: Source.server));
    final targets = snap.docs.where((doc) => const ['worker', 'group_supervisor']
        .contains(doc.data()['role'])).toList();
    if (targets.isEmpty) {
      throw StateError('لا توجد حسابات نشطة لتجميدها في هذه الدورة.');
    }
    if (targets.length > 500) {
      throw StateError('عدد الحسابات يتجاوز حد العملية الواحدة؛ يلزم تنفيذ التجميد على دفعات.');
    }
    final batch = firestore.batch();
    for (final doc in targets) {
      batch.update(doc.reference, {
        'isActive': false,
        'status': 'frozen',
        'frozenAt': FieldValue.serverTimestamp(),
        'frozenBy': actorId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    final remaining = await query.get(const GetOptions(source: Source.server));
    if (remaining.docs.any((doc) => const ['worker', 'group_supervisor']
        .contains(doc.data()['role']))) {
      throw StateError('لم يؤكد الخادم تجميد جميع حسابات الدورة. راجع القائمة قبل إعادة المحاولة.');
    }
  }

  Future<void> _requireManagedGroup(String groupId, String actorId) async {
    if (groupId.trim().isEmpty) throw StateError('يجب اختيار مجموعة صالحة.');
    final group = await _operations.doc(groupId.trim()).get(const GetOptions(source: Source.server));
    if (!group.exists || group.data()?['_entity'] != 'group' ||
        group.data()?['isDeleted'] == true ||
        group.data()?['municipalityCoordinatorId'] != actorId) {
      throw StateError('المجموعة غير موجودة أو لا تتبع بلديتك.');
    }
  }

  void _requireOwnWorker(Map<String, dynamic>? data, String actorId) {
    if (data == null || data['role'] != 'worker' ||
        data['municipalityCoordinatorId'] != actorId ||
        data['isActive'] == false) {
      throw StateError('العامل غير نشط أو لا يتبع بلديتك.');
    }
  }

  Future<void> updateWorkerDetails({
    required String userId,
    required String name,
    required String phone,
    required String actorId,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != actorId) {
      throw StateError('انتهت الجلسة أو لا تملك صلاحية تعديل العامل.');
    }
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    if (cleanName.isEmpty) throw ArgumentError('اسم العامل مطلوب.');
    final ref = _users.doc(userId);
    final before = await ref.get(const GetOptions(source: Source.server));
    _requireOwnWorker(before.data(), actorId);
    await ref.update({
      'name': cleanName,
      'phone': cleanPhone,
      'updatedBy': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final after = await ref.get(const GetOptions(source: Source.server));
    if (after.data()?['name'] != cleanName || after.data()?['phone'] != cleanPhone) {
      throw StateError('تعذر تأكيد تعديل بيانات العامل على Firebase.');
    }
  }

  Future<void> transferWorker({
    required String userId,
    required String toGroupId,
    required String toCycleId,
    required String actorId,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != actorId) {
      throw StateError('انتهت الجلسة أو لا تملك صلاحية النقل.');
    }
    await _requireManagedGroup(toGroupId, actorId);
    final cycle = await _cycles.doc(toCycleId).get(const GetOptions(source: Source.server));
    if (!cycle.exists || cycle.data()?['status'] != 'active') {
      throw StateError('دورة العمل الجديدة غير نشطة.');
    }
    final ref = _users.doc(userId);
    final snap = await ref.get(const GetOptions(source: Source.server));
    _requireOwnWorker(snap.data(), actorId);
    await ref.update({
      'groupId': toGroupId,
      'cycleId': toCycleId,
      'updatedBy': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final confirmed = await ref.get(const GetOptions(source: Source.server));
    if (!confirmed.exists ||
        confirmed.data()?['groupId'] != toGroupId ||
        confirmed.data()?['cycleId'] != toCycleId) {
      throw StateError('لم يتم تأكيد نقل العامل على خادم Firebase. تحقق من بيانات العامل قبل إعادة المحاولة.');
    }
  }

  Future<void> swapWorkers({
    required String firstUserId,
    required String secondUserId,
    required String actorId,
  }) async {
    if (firstUserId == secondUserId) throw StateError('اختر عاملين مختلفين.');
    if (FirebaseAuth.instance.currentUser?.uid != actorId) {
      throw StateError('انتهت الجلسة أو لا تملك صلاحية التبديل.');
    }
    final aRef = _users.doc(firstUserId);
    final bRef = _users.doc(secondUserId);
    final workerA = await aRef.get(const GetOptions(source: Source.server));
    final workerB = await bRef.get(const GetOptions(source: Source.server));
    _requireOwnWorker(workerA.data(), actorId);
    _requireOwnWorker(workerB.data(), actorId);
    await _requireManagedGroup('${workerA.data()?['groupId'] ?? ''}', actorId);
    await _requireManagedGroup('${workerB.data()?['groupId'] ?? ''}', actorId);
    final results = await firestore.runTransaction((tx) async {
      final a = await tx.get(aRef);
      final b = await tx.get(bRef);
      _requireOwnWorker(a.data(), actorId);
      _requireOwnWorker(b.data(), actorId);
      final ag = a.data()?['groupId'];
      final bg = b.data()?['groupId'];
      tx.update(aRef, {'groupId': bg, 'updatedBy': actorId, 'updatedAt': FieldValue.serverTimestamp()});
      tx.update(bRef, {'groupId': ag, 'updatedBy': actorId, 'updatedAt': FieldValue.serverTimestamp()});
      return true;
    });
    if (results != true) throw StateError('Worker swap failed.');
  }

  Future<void> deactivateUser(String userId, {required String actorId}) async {
    if (FirebaseAuth.instance.currentUser?.uid != actorId || actorId == userId) {
      throw StateError('لا توجد صلاحية لإلغاء تنشيط هذا الحساب.');
    }
    final ref = _users.doc(userId);
    final before = await ref.get(const GetOptions(source: Source.server));
    final info = before.data();
    if (!before.exists || info?['municipalityCoordinatorId'] != actorId ||
        !const ['worker', 'group_supervisor'].contains(info?['role']) ||
        info?['isActive'] == false) {
      throw StateError('الحساب غير نشط أو لا يتبع بلديتك.');
    }
    await ref.update({
      'isActive': false,
      'status': 'deactivated',
      'deactivatedBy': actorId,
      'deactivatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final after = await ref.get(const GetOptions(source: Source.server));
    if (after.data()?['isActive'] != false ||
        after.data()?['status'] != 'deactivated') {
      throw StateError('لم يؤكد خادم Firebase إلغاء التنشيط.');
    }
  }
}
