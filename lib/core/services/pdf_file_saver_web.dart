import 'dart:html' as html;
import 'dart:typed_data';

Future<String?> savePdfBytes(List<int> bytes, String fileName) async {
  return saveReportBytes(bytes, fileName, mimeType: 'application/pdf');
}

Future<String?> saveReportBytes(List<int> bytes, String fileName, {String? mimeType}) async {
  final blob = html.Blob([Uint8List.fromList(bytes)], mimeType ?? 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  return fileName;
}
