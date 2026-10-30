import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Converts service failures to short Arabic explanations safe for UI display.
/// Never render raw platform exceptions (which may contain implementation details).
class MessagingFeedback {
  static String describe(Object error) {
    if (error is FirebaseFunctionsException) {
      return _code(error.code, external: true);
    }
    if (error is FirebaseException) {
      return _code(error.code, external: error.plugin == 'cloud_functions');
    }
    if (error is StateError) {
      final message = error.message.toString();
      if (message.contains('خارج') || message.contains('صلاحية') ||
          message.contains('المستلم') || message.contains('Firebase غير متاح') ||
          message.contains('تتطلب اتصال') || message.contains('منسق البلدية')) {
        return message;
      }
      return 'تعذّر تنفيذ الطلب. تحقق من إعدادات الاتصال والصلاحيات.';
    }
    if (error is ArgumentError) {
      return 'تحقق من البيانات المطلوبة ومن صحة النص والمستلم.';
    }
    return 'تعذّر تنفيذ العملية. تحقق من الاتصال، أو أعد المحاولة لاحقًا.';
  }

  static String _code(String code, {bool external = false}) {
    switch (code.replaceFirst('functions/', '').toLowerCase()) {
      case 'permission-denied':
        return 'ليس لديك صلاحية لهذه العملية، أو أن المستلم خارج نطاقك.';
      case 'unauthenticated':
        return 'انتهت جلسة الدخول. أعد تسجيل الدخول وحاول مرة أخرى.';
      case 'not-found':
        return external
            ? 'خدمة الرسائل الخارجية غير منشورة بعد، أو المستلم غير متوفر.'
            : 'العنصر المطلوب غير موجود.';
      case 'failed-precondition':
        return external
            ? 'خدمة SMS غير مكتملة الإعداد، أو رقم المستلم غير صالح. افتح إعدادات SMS.'
            : 'العملية غير متاحة قبل استكمال المتطلبات.';
      case 'resource-exhausted':
        return 'تم بلوغ الحد المسموح للإرسال. حاول لاحقًا.';
      case 'invalid-argument':
        return 'بيانات الإرسال غير صحيحة. راجع النص والمستلم.';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return 'تعذّر الوصول إلى الخادم. تحقق من الإنترنت ثم أعد المحاولة.';
      case 'internal':
      case 'unknown':
        return 'واجه الخادم مشكلة أثناء الطلب. لا يُفترض أن الرسالة أُرسلت.';
      case 'already-exists':
        return 'هذا الطلب مسجل مسبقًا.';
      default:
        return 'تعذّر إتمام العملية. راجع إعدادات الخدمة أو أعد المحاولة.';
    }
  }
}
