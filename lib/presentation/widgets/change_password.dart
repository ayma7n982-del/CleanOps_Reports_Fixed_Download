import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/services/auth_service.dart';

class ChangePasswordTile extends StatelessWidget {
  const ChangePasswordTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.lock_reset_outlined),
      title: const AppText('تغيير كلمة المرور'),
      onTap: () async {
        final auth = context.read<AuthService>();
        final changed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _ChangePasswordDialog(auth: auth),
        );
        if (changed == true && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: AppText('تم تغيير كلمة المرور.')),
          );
        }
      },
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.auth});

  final AuthService auth;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    final error = await widget.auth.changePassword(
      currentPassword: _current.text,
      newPassword: _new.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  TextFormField _passwordField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    TextInputAction action = TextInputAction.next,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_saving,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      textDirection: TextDirection.ltr,
      textInputAction: action,
      decoration: InputDecoration(label: AppText(label)),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const AppText('تغيير كلمة المرور'),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _passwordField(
                controller: _current,
                label: 'كلمة المرور الحالية',
                validator: (value) => value == null || value.isEmpty
                    ? 'أدخل كلمة المرور الحالية.'
                    : null,
              ),
              _passwordField(
                controller: _new,
                label: 'كلمة المرور الجديدة',
                validator: (value) {
                  if (value == null || value.length < 8) {
                    return 'أدخل ٨ أحرف على الأقل.';
                  }
                  if (value == _current.text) {
                    return 'اختر كلمة مرور مختلفة عن الحالية.';
                  }
                  return null;
                },
              ),
              _passwordField(
                controller: _confirm,
                label: 'تأكيد كلمة المرور الجديدة',
                action: TextInputAction.done,
                validator: (value) => value == _new.text
                    ? null
                    : 'كلمتا المرور غير متطابقتين.',
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: AppText(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const AppText('إلغاء'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const AppText('حفظ'),
          ),
        ],
      ),
    );
  }
}
