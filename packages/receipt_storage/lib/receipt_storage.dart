/// Private per-installation persistence. Opening a database is explicit;
/// importing this library never creates files or writes a draft.
library;

export 'src/repository.dart';
export 'src/history_filter.dart';
export 'src/text_search.dart';

export 'src/protected_backup.dart';
export 'src/workspace.dart';
