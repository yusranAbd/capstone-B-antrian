import '../../../api.dart';
import '../../../config.dart';
import '../models/patient_models.dart';
import 'patient_repository.dart';

/// Commands and parameterized reads; no second catalog/visit cache or client.
class PatientBookingRepository {
  PatientBookingRepository(this.patient);
  final PatientRepository patient;
  bool _writing = false;
  Future<List<Json>> read(String path, Map<String, String> query) async {
    patient.check();
    try {
      final result = patientRows(
        await patient.api.request('GET', path, query: query),
      );
      patient.check();
      return result;
    } catch (error) {
      throw patientError(error);
    }
  }

  Future<Json> book(bool appointment, Json body) async {
    patient.check();
    if (_writing) throw const ApiException(409, 'Pendaftaran masih diproses.');
    _writing = true;
    try {
      final result = patientObject(
        await patient.api.request(
          'POST',
          appointment ? '/janji-temu' : '/reservasi',
          body: body,
        ),
      );
      patient.check();
      final ticket = appointment ? object(result['tiket']) : result;
      if (result['id'] is! String || ticket['id'] is! String) {
        throw const ApiException(
          0,
          'Identitas pendaftaran belum terverifikasi.',
        );
      }
      return result;
    } catch (error) {
      throw patientError(error);
    } finally {
      _writing = false;
    }
  }
}
