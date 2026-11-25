import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_reader/backup_files.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runPicker = bool.fromEnvironment("INTERACTIVE_BACKUP_PICKER");
  if (runPicker) {
    // Native UI automation can enable the screen-reader bridge during a dialog.
    // Establish that state before testWidgets records its owned semantics handles.
    setUpAll(() => binding.platformDispatcher.semanticsEnabledTestValue = true);
    tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  }
  testWidgets(
    'native save/open selectors preserve the encrypted synthetic file',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Synthetic backup picker check')),
          ),
        ),
      );
      final bytes = base64Decode(
        'UlJCQUNLVVABAQABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhtMGBPPZsh55NFYRink3feznyfVBk6dDneu0Tl/RfaV6jhuffPfzhW9n/ol2eVmNXF2TWVTC8P3jdcdnVSCQ9RUmV9MMKA+JhTzeff5SuLxHR+LVLxe3JYzmYK7bECFAsqIHIqkGBkSzYvcG/gv7UneFOZLWtVDrReTbuQ3+cITMWEqizC6bvwnmI5VfuLdQ2IbcpI9By1fbyQV2h0QOdEszPUJlcraSnsP45cGLs08zgZU04kF7tg0P6d71IQHqvvE+FxwinuLrvckD31KF9iI5b5cE4fvdxvj8tBRLowiWxpZkyQdnRD8wkLzwbzJGo/BFVSe+Iee0zcEzfCEpr0bnkZ88z0x7MKzuXBVnO9g/HQQT0azLUJ6WRJqDaf4qZomtGzbhZguFAvi2LSm16dUU/vJo6sVaiw+9ZPxjiBsTHKS57bFxnknsp/Zc2l0sFjK2wSnIx21kkzp5tnz+zATLL3M0HJE7qeNdObV3pjP+5dj',
      );
      const files = NativeBackupFiles();
      expect(await files.save(bytes), isTrue);
      expect(await files.read(), bytes);
    },
    skip: !runPicker,
  );
}
