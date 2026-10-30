import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Present safe, actionable Arabic messages instead of raw backend stack traces.
String friendlyMessagingError(Object error) {
  if (error is FirebaseFunctionsException) {
    switch (error.code.replaceFirst('functions/', '')) {
      case 'permission-denied':
        return 'ليست لديك صلاحية لتنفيذ هذه العملية أو أن المستلم خارج نطاقك.';
      case 'unauthenticated':
        return 'انتهت جلسة الدخول. أعد تسجيل الدخول ثم حاول مجددًا.';
      case 'invalid-argument':
        return 'راجع البيانات المدخلة واسم المستلم ورقم الهاتف.';
      case 'failed-precondition':
        if ((error.message ?? '').contains('Secret Manager')) {
          return 'يلزم تفعيل صلاحيات مدير الأسرار في Firebase قبل إعداد SMS.';
        }
        if ((error.message ?? '').toLowerCase().contains('twilio')) {
          return 'بيانات Twilio غير صحيحة أو الحساب لم يكتمل تفعيله.';
        }
        return 'الخدمة غير مهيأة بعد. راجع إعدادات SMS وصلاحيات Firebase.';
      case 'not-found':
        return 'لم يتم العثور على الحساب أو الرسالة المطلوبة.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'خدمة الاتصال غير متاحة الآن. تحقق من الإنترنت ثم أعد المحاولة.';
      case 'resource-exhausted':
        return 'تم بلوغ الحد المسموح لإرسال SMS خلال هذه الساعة.';
      default:
        return 'تعذر إكمال الطلب على الخادم. راجع حالة الاتصال أو إعدادات الخدمة.';
    }
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'لا توجد صلاحية للوصول إلى هذه الرسالة أو البيانات.';
      case 'unavailable':
        return 'Firebase غير متاح حاليًا. ستبقى الرسائل المحلية معلّقة.';
      default:
        return 'تعذر التواصل مع Firebase. تحقق من الصلاحيات والاتصال.';
    }
  }
  if (error is StateError) {
    final msg = error.message.toString();
    // StateError messages come from our own validated application layer.
    if (msg.contains('Firebase') || msg.contains('رسالة') ||
        msg.contains('صلاحية') || msg.contains('منسق') ||
        msg.contains('مجموعة') || msg.contains('المستلم')) {
      return msg;
    }
  }
  if (error is ArgumentError) {
    return 'تأكد من اختيار المستلم وإدخال نص صالح قبل الإرسال.';
  }
  return 'تعذر إكمال العملية. تحقق من اتصالك وإعدادات الخدمة ثم أعد المحاولة.';
}
