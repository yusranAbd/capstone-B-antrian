import '../../../config.dart';
import 'admin_catalog_models.dart';

/// Reuse the recursive freezing boundary from 2A, without a second catalog.
List<Json> immutableSlotRows(List<Json> source) =>
    AdminCatalogSnapshot({'slots': source}).rowsFor('slots');
