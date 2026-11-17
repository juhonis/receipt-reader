import 'package:flutter/widgets.dart';

import 'app.dart';
import 'local_store.dart';

void main() => runApp(
  const ReceiptReaderApp(
    storageOpener: openApplicationStore,
    recoveryOpener: openApplicationRecoveryStore,
  ),
);
