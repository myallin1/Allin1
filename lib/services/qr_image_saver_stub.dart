// ================================================================
// qr_image_saver_stub.dart — Android/iOS implementation
// ================================================================
// Default target for the conditional import in
// admin_qr_generator_screen.dart (see that file's `if (dart.library.html)`
// swap to qr_image_saver_web.dart). Follows the exact same
// save-to-temp-then-OpenFilex pattern already used for APK installs in
// notifications_screen.dart — the only new piece here is writing PNG
// bytes instead of streaming a Dio download to disk.
//
// OpenFilex.open() on a .png hands off to whatever the OS registers for
// image files — on Android that's normally a gallery/photos app with its
// own built-in Share button, which is the closest thing to a native
// "share this QR" flow this codebase can offer without adding a new
// share_plus dependency.
import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class QrImageSaver {
  Future<String> saveAndOpen(Uint8List pngBytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(pngBytes, flush: true);
    await OpenFilex.open(filePath);
    return filePath;
  }
}
