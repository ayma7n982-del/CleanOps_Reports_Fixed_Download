import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ImageService {
  final FirebaseStorage storage = FirebaseStorage.instance;

  Future<Uint8List> compress(Uint8List bytes, int targetKb) async {
    final limitBytes = targetKb * 1024;
    if (bytes.lengthInBytes <= limitBytes) return bytes;
    Uint8List smallest = bytes;
    for (final dimension in <int>[1600, 1280, 1024, 800, 640, 480, 360, 240]) {
      for (final quality in <int>[85, 70, 55, 40, 25, 15, 8]) {
        final output = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: dimension,
          minHeight: dimension,
          quality: quality,
          format: CompressFormat.jpeg,
        );
        final candidate = Uint8List.fromList(output);
        if (candidate.lengthInBytes < smallest.lengthInBytes) smallest = candidate;
        if (candidate.lengthInBytes <= limitBytes) return candidate;
      }
    }
    throw StateError('تعذر ضغط الصورة إلى $targetKb كيلوبايت؛ اختر صورة أخرى.');
  }

  Future<String> compressToLocal(XFile file, {int targetKb = 500}) async {
    final raw = await file.readAsBytes();
    final compressed = await compress(raw, targetKb);
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/field_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(compressed, flush: true);
    return path;
  }

  Future<String?> pickCompressUpload({required int targetKb, required String userId, required String operationId}) async {
    final localPath = await pickCompressLocal(targetKb: targetKb, context: null);
    if (localPath == null) return null;
    if (Firebase.apps.isEmpty) return localPath;
    try {
      final ref = storage.ref('photos/$userId/$operationId/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(File(localPath), SettableMetadata(contentType: 'image/jpeg', customMetadata: {'targetKb': '$targetKb'}));
      final url = await ref.getDownloadURL();
      try {
        await File(localPath).delete();
      } catch (_) {}
      return url;
    } catch (_) {
      return localPath;
    }
  }

  Future<ImageSource?> _chooseSource(BuildContext context) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF0A1F32),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('مصدر الصورة', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ListTile(leading: const CircleAvatar(child: Icon(Icons.camera_alt_rounded)), title: const Text('التقاط من الكاميرا', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)), onTap: () => Navigator.pop(sheetContext, ImageSource.camera)),
            ListTile(leading: const CircleAvatar(child: Icon(Icons.photo_library_rounded)), title: const Text('اختيار من الاستوديو', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)), onTap: () => Navigator.pop(sheetContext, ImageSource.gallery)),
          ]),
        ),
      ),
    );
  }

  Future<List<String>> pickTripPhotos({
    required int targetKb,
    required int remainingSlots,
    required BuildContext context,
  }) async {
    if (remainingSlots <= 0) return [];
    final source = await _chooseSource(context);
    if (source == null) return [];
    final picker = ImagePicker();
    final photos = source == ImageSource.gallery
        ? await picker.pickMultiImage(imageQuality: 100)
        : <XFile>[
            if (await picker.pickImage(source: ImageSource.camera, imageQuality: 100)
                case final XFile photo)
              photo,
          ];
    final paths = <String>[];
    for (final photo in photos.take(remainingSlots)) {
      paths.add(await compressToLocal(photo, targetKb: targetKb));
    }
    return paths;
  }

  Future<String?> pickCompressLocal({required int targetKb, BuildContext? context}) async {
    final picker = ImagePicker();
    final source = context == null ? ImageSource.camera : await _chooseSource(context);
    if (source == null) return null;
    final image = await picker.pickImage(source: source, imageQuality: 100);
    if (image == null) return null;
    return compressToLocal(image, targetKb: targetKb);
  }
}
