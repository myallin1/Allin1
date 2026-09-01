// ================================================================
// csv_export_web.dart — Web (PWA) implementation
// ================================================================
// Swapped in for csv_export_stub.dart on web builds. Same package:web +
// dart:js_interop blob-download recipe already proven in
// qr_image_saver_web.dart — only the MIME type and payload differ.
//
// The leading '﻿' BOM matters: without it Excel opens a UTF-8 CSV
// as ANSI and mangles any non-ASCII text (Tamil names, ₹ symbols) into
// garbage. Sheets/LibreOffice don't need it but ignore it harmlessly,
// so it's always emitted.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class CsvExporter {
  Future<String> save(String csv, String fileName) async {
    final withBom = '﻿$csv';
    final blob = web.Blob(
      <JSString>[withBom.toJS].toJS,
      web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = fileName;
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return fileName;
  }
}
