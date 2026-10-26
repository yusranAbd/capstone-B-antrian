import 'display_selection_types.dart';
import 'display_selection_native.dart'
    if (dart.library.js_interop) 'display_selection_web.dart'
    as platform;
export 'display_selection_types.dart';

DisplaySelection createDisplaySelection(Uri apiBase) =>
    platform.createDisplaySelection(apiBase);
