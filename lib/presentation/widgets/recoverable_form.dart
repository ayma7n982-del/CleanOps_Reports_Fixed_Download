import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/form_draft_store.dart';

/// Text is captured on every edit; selections are captured after setState.
/// Only clear after the real operation has been durably queued/saved.
mixin RecoverableForm<T extends StatefulWidget> on State<T> {
  String get draftId;
  Map<String, TextEditingController> get draftFields;
  Map<String, dynamic> get draftValues => {};
  void restoreDraftValues(Map<String, dynamic> values) {}
  bool get draftBusy => false;

  String? _draftKey;
  String _baseline = '';
  String _lastSnapshot = '';
  bool _ready = false, _disposed = false, _restoring = false;
  bool _restored = false, _hasDraft = false, _failed = false;
  int _revision = 0;
  Map<String, TextEditingController> _fields = {};

  Map<String, dynamic> _snapshot() => {
    'fields': {for (final e in _fields.entries) e.key: e.value.text},
    'values': draftValues,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draftKey != null) return;
    final user = context.read<AuthService>().currentUser;
    _draftKey = FormDraftStore.key([
      user?.id ?? 'anonymous',
      user?.role ?? '',
      user?.groupId ?? '',
      user?.scope ?? '',
      user?.municipalityCoordinatorId ?? '',
      draftId,
    ]);
    _fields = draftFields;
    _baseline = jsonEncode(_snapshot());
    _lastSnapshot = _baseline;
    for (final controller in _fields.values) {
      controller.addListener(_captureDraft);
    }
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    try {
      final saved = await FormDraftStore.read(_draftKey!);
      if (_disposed || !mounted) return;
      _restoring = true;
      if (saved != null) {
        final fields = Map<String, dynamic>.from(saved['fields'] as Map);
        final values = Map<String, dynamic>.from(saved['values'] as Map);
        for (final entry in fields.entries) {
          if (entry.value is String) _fields[entry.key]?.text = entry.value;
        }
        restoreDraftValues(values);
        _lastSnapshot = jsonEncode(_snapshot());
        _restored = true;
        _hasDraft = true;
      }
      _failed = false;
    } catch (_) {
      _failed = true;
    } finally {
      _restoring = false;
      _ready = true;
      if (!_disposed && mounted) super.setState(() {});
    }
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _captureDraft();
  }

  void _captureDraft() {
    if (!_ready || _disposed || _restoring || _draftKey == null) return;
    final snapshot = _snapshot();
    final encoded = jsonEncode(snapshot);
    if (encoded == _lastSnapshot) return;
    _lastSnapshot = encoded;
    final revision = ++_revision;
    _hasDraft = encoded != _baseline;
    final write = _hasDraft
        ? FormDraftStore.write(_draftKey!, snapshot)
        : FormDraftStore.clear(_draftKey!);
    write.then(
      (_) {
        if (_disposed || !mounted || revision != _revision) return;
        super.setState(() => _failed = false);
      },
      onError: (Object _) {
        if (_disposed || !mounted || revision != _revision) return;
        super.setState(() => _failed = true);
      },
    );
  }

  Future<void> clearFormDraft() async {
    _baseline = jsonEncode(_snapshot());
    _lastSnapshot = _baseline;
    ++_revision;
    try {
      await FormDraftStore.clear(_draftKey!);
      _hasDraft = false;
      _restored = false;
      _failed = false;
    } catch (_) {
      _failed = true;
    }
    if (!_disposed && mounted) super.setState(() {});
  }

  Widget protectDraft(Widget child, {bool compact = false}) => PopScope(
    canPop: _ready && !draftBusy && !_failed,
    child: Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (_ready && (_hasDraft || _restored || _failed))
          Material(
            color: _failed ? Colors.orange.shade50 : Colors.green.shade50,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Icon(
                      _failed ? Icons.error_outline : Icons.edit_note,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _failed
                            ? 'تعذر حفظ المسودة على الجهاز. أعد المحاولة قبل الخروج.'
                            : _restored
                            ? 'استُعيدت مدخلاتك السابقة. راجعها قبل الحفظ.'
                            : 'تُحفظ مدخلاتك تلقائيًا كمسودة على هذا الجهاز.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (_failed)
                      TextButton(
                        onPressed: () {
                          _lastSnapshot = '';
                          _captureDraft();
                        },
                        child: const Text('إعادة المحاولة'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Flexible(
          fit: compact ? FlexFit.loose : FlexFit.tight,
          child: Stack(
            children: [
              AbsorbPointer(absorbing: !_ready || draftBusy, child: child),
              if (!_ready)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0xDDFFFFFF),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _captureDraft();
    _disposed = true;
    for (final controller in _fields.values) {
      controller.removeListener(_captureDraft);
    }
    super.dispose();
  }
}

/// Use the same protection in dialogs whose controllers live in the caller.
class RecoverableDraftPanel extends StatefulWidget {
  final String id;
  final bool Function()? busy;
  final Map<String, TextEditingController> fields;
  final Map<String, dynamic> Function() values;
  final void Function(Map<String, dynamic>) restore;
  final Widget Function(
    BuildContext,
    void Function(VoidCallback),
    Future<void> Function(),
  )
  builder;
  const RecoverableDraftPanel({
    super.key,
    required this.id,
    this.busy,
    required this.fields,
    required this.values,
    required this.restore,
    required this.builder,
  });
  @override
  State<RecoverableDraftPanel> createState() => _RecoverableDraftPanelState();
}

class _RecoverableDraftPanelState extends State<RecoverableDraftPanel>
    with RecoverableForm<RecoverableDraftPanel> {
  @override
  String get draftId => widget.id;
  @override
  bool get draftBusy => widget.busy?.call() ?? false;
  @override
  Map<String, TextEditingController> get draftFields => widget.fields;
  @override
  Map<String, dynamic> get draftValues => widget.values();
  @override
  void restoreDraftValues(Map<String, dynamic> values) =>
      widget.restore(values);
  @override
  Widget build(BuildContext context) => protectDraft(
    widget.builder(context, setState, clearFormDraft),
    compact: true,
  );
}
