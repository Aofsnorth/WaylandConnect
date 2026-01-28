import 'dart:io';

void main() async {
  print("Testing Autostart Logic...");
  final String home = Platform.environment['HOME'] ?? '/';
  final String autostartDir = '$home/.config/autostart';
  final File desktopFile = File('$autostartDir/wayland_connect_test.desktop'); // Use a test name

  print("Target File: ${desktopFile.path}");

  try {
    final Directory dir = Directory(autostartDir);
    if (!await dir.exists()) {
      print("Creating directory: $autostartDir");
      await dir.create(recursive: true);
    }
    
    // Simulate "Toggle ON"
    print("Simulating Toggle ON...");
    final String execPath = "/usr/bin/test_exec"; // Dummy path
    final String content = '''[Desktop Entry]
Type=Application
Name=Wayland Connect Test
Exec=$execPath
X-GNOME-Autostart-enabled=true
''';
    await desktopFile.writeAsString(content);
    
    if (await desktopFile.exists()) {
      print("SUCCESS: File created successfully.");
      print("Content:");
      print(await desktopFile.readAsString());
    } else {
      print("FAILURE: File was not found after writing.");
    }

    // Simulate "Toggle OFF"
    print("Simulating Toggle OFF...");
    await desktopFile.delete();
    if (!await desktopFile.exists()) {
       print("SUCCESS: File deleted successfully.");
    } else {
       print("FAILURE: File still exists after delete.");
    }

  } catch (e) {
    print("ERROR: $e");
  }
}
