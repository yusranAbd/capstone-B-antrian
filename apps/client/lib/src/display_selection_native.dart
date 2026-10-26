import 'display_selection_types.dart';

// Native clients keep the existing encrypted cookie transport and lifecycle.
DisplaySelection createDisplaySelection(Uri apiBase) =>
    MemoryDisplaySelection(isolated: false);
