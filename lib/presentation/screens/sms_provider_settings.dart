import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/messaging_error_text.dart';
import '../widgets/app_design.dart';

class SmsProviderSettingsPage extends StatefulWidget {
  const SmsProviderSettingsPage({super.key});

  @override
  State<SmsProviderSettingsPage> createState() => _SmsProviderSettingsPageState();
}

class _SmsProviderSettingsPageState extends State<SmsProviderSettingsPage> {
  final sid = TextEditingController();
  final token = TextEditingController();
  final sender = TextEditingController();
  bool loading = true;
  bool saving = false;
  bool showToken = false;
  bool ready = false;
  String maskedSender = '';
  String statusText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkStatus());
  }

  @override
  void dispose() {
    sid.dispose();
    token.dispose();
    sender.dispose();
    super.dispose();
  }

  HttpsCallable _function(String name) =>
      FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(name);

  Future<void> _checkStatus() async {
    if (!mounted) return;
    setState(() { loading = true; statusText = ''; });
    if (Firebase.apps.isEmpty) {
      setState(() {
        loading = false;
        ready = false;
        statusText = 'Firebase غير متاح. تحقق من اتصال الحساب.';
      });
      return;
    }
    try {
      final result = await _function('getSmsProviderStatus').call<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        ready = result.data['ready'] == true;
        maskedSender = '${result.data['sender'] ?? ''}';
        statusText = ready
            ? 'بيانات مزود SMS محفوظة على خادم Firebase.'
            : 'مزود SMS غير جاهز. يجب إعداد Twilio وإتاحة صلاحيات Secret Manager.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        ready = false;
        statusText = friendlyMessagingError(e);
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (saving) return;
    if (sid.text.trim().isEmpty || token.text.trim().isEmpty ||
        sender.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: AppText('أدخل Account SID وAuth Token ورقم المرسل أولًا.')));
      return;
    }
    setState(() => saving = true);
    try {
      await _function('configureSmsProvider').call<Map<String, dynamic>>({
        'accountSid': sid.text.trim(),
        'authToken': token.text.trim(),
        'from': sender.text.trim(),
      });
      sid.clear();
      token.clear();
      sender.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: AppText('تم حفظ إعدادات Twilio على خادم Firebase.')));
      }
      await _checkStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: AppText(friendlyMessagingError(e))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    if (user == null) return const Scaffold(
      body: Center(child: AppText('سجّل الدخول للوصول إلى إعدادات الرسائل.')),
    );
    final canConfigure = user.role == 'donor_manager';
    final canView = canConfigure ||
        const ['jsc_coordinator', 'municipality_coordinator'].contains(user.role);
    return Scaffold(
      appBar: AppBar(
        title: const AppText('إعدادات SMS'),
        actions: [
          IconButton(
            tooltip: 'فحص الاتصال بالخادم',
            onPressed: loading ? null : _checkStatus,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          AiHero(
            user: user,
            eyebrow: 'SECURE SMS • CLEANOPS',
            title: 'ربط مزوّد الرسائل الخارجية',
            subtitle: 'إعدادات Twilio تحفظ بأمان على الخادم، ولا تُخزن المفاتيح في التطبيق.',
          ),
          const SizedBox(height: 16),
          AiSectionCard(
            title: 'حالة اتصال SMS',
            feature: 'messages',
            subtitle: 'SMS مستقل عن إعدادات API العامة والرسائل الداخلية المجانية.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (loading) const LinearProgressIndicator(),
                ListTile(
                  leading: Icon(ready ? Icons.verified_rounded : Icons.sms_failed_outlined,
                      color: ready ? aiGreen : orange),
                  title: AppText(ready ? 'تم حفظ إعدادات الخدمة' : 'الخدمة غير جاهزة للإرسال'),
                  subtitle: AppText(statusText),
                ),
                if (ready && maskedSender.isNotEmpty)
                  ListTile(
                    title: const AppText('رقم المرسل'),
                    subtitle: Text(maskedSender, textDirection: TextDirection.ltr),
                  ),
                OutlinedButton.icon(
                  onPressed: loading ? null : _checkStatus,
                  icon: const Icon(Icons.wifi_tethering_rounded),
                  label: const AppText('فحص إعدادات المزود'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (canConfigure)
            AiSectionCard(
              title: 'إدخال بيانات Twilio',
              feature: 'settings',
              subtitle: 'هذه العملية متاحة لمدير النظام فقط، عبر اتصال مشفر بوظائف Firebase.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: sid,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Account SID',
                      hintText: 'AC...',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: token,
                    obscureText: !showToken,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Auth Token / API Secret',
                      helperText: 'لا ترسل هذا المفتاح في محادثة أو صورة.',
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: IconButton(
                        tooltip: showToken ? 'إخفاء المفتاح' : 'إظهار المفتاح',
                        icon: Icon(showToken
                            ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => showToken = !showToken),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sender,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'رقم مرسل Twilio',
                      hintText: '+12345678900',
                      helperText: 'أدخل الرقم بصيغة دولية.',
                      prefixIcon: Icon(Icons.phone_iphone_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: saving ? null : _saveSettings,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: AppText(saving ? 'جارٍ التحقق والحفظ...' : 'التحقق من Twilio وحفظ البيانات'),
                    ),
                  ),
                ],
              ),
            )
          else if (canView)
            const AiSectionCard(
              title: 'إعدادات محمية',
              feature: 'settings',
              child: AppText('إعداد مفاتيح SMS متاح لمدير النظام (L4) فقط. يمكنك إرسال الرسائل بعد تفعيل الخدمة.'),
            ),
          const SizedBox(height: 12),
          const AiSectionCard(
            title: 'قبل إرسال أول SMS',
            feature: 'operations',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: Icon(Icons.account_balance_wallet_outlined, color: orange),
                  title: AppText('قد توجد تكاليف من مزود SMS'),
                  subtitle: AppText('الرسائل الداخلية عبر Firestore لا تحتاج اشتراك Twilio. رسائل SMS ليست مجانية بالضرورة.'),
                ),
                ListTile(
                  leading: Icon(Icons.security_rounded, color: aiCyan),
                  title: AppText('متطلبات Firebase'),
                  subtitle: AppText('يجب نشر وظيفة SMS وتفعيل Secret Manager ومنح حساب خدمة الوظيفة صلاحيات إدارة الأسرار.'),
                ),
                ListTile(
                  leading: Icon(Icons.person_pin_circle_outlined, color: aiCyan),
                  title: AppText('بيانات المستلمين'),
                  subtitle: AppText('رقم هاتف كل مستلم يجب أن يكون محفوظًا بصيغة دولية في حسابه.'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
