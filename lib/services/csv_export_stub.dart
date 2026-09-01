// ================================================================
// csv_export_stub.dart — Android/iOS implementation
// ================================================================
// Default target for the conditional import in
// admin_affiliate_leads_screen.dart (see that file's
// `if (dart.library.html)` swap to csv_export_web.dart). Mirrors the
// existing qr_image_saver_stub.dart pattern exactly: write to the temp
// directory, then hand the file to the OS, which on Android opens
// whatever is registered for .csv (Excel, Sheets, Files) — each of
// which has its own Share button.
//
// CSV was chosen over real .xlsx/.pdf deliberately (Nizam's export
// requirement): Excel and Google Sheets both open CSV natively with
// full sorting/filtering, and it needs ZERO new packages, so the admin
// bundle doesn't grow at all.
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class CsvExporter {
  Future<String> save(String csv, String fileName) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsString(csv, flush: true);
    await OpenFilex.open(filePath);
    return filePath;
  }
}
