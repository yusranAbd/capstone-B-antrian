import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'api.dart';
import 'config.dart';
import 'doctor_dashboard.dart';
import 'features/doctor/application/doctor_portal_cubit.dart';
import 'features/doctor/application/doctor_portal_state.dart';
import 'features/doctor/data/doctor_repository.dart';
import 'patient_sync.dart';

/// Read-only portal; backend derives the authenticated doctor's scope.
class DoctorPage extends StatelessWidget {
  const DoctorPage({super.key, required this.api, this.updates});
  final QueueApi api;
  final PatientUpdates? updates;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey((api, api.user?['id'], api.user?['peran'], updates)),
    create: (_) => DoctorPortalCubit(
      repository: ApiDoctorRepository(api: api, updates: updates),
      date: api.config.today,
    )..refresh(),
    child: BlocBuilder<DoctorPortalCubit, DoctorPortalState>(
      builder: (context, state) {
        final cubit = context.read<DoctorPortalCubit>();
        return DoctorDashboard(
          config: api.config,
          date: state.selectedDate,
          profile: state.data.profile,
          schedules: state.data.schedules,
          appointments: state.data.appointments,
          snapshots: state.data.snapshots,
          loading: state.loading,
          available: state.available,
          status: cubit.repository.connectionStatus,
          error: state.error?.toString(),
          onRefresh: cubit.refresh,
          onPickDate: () async {
            final today = DateTime.parse(api.config.today);
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.parse(state.selectedDate),
              firstDate: DateTime(today.year - 5),
              lastDate: DateTime(today.year + 5),
            );
            if (context.mounted && picked != null) {
              await cubit.selectDate(dateOnly(picked.toIso8601String()));
            }
          },
        );
      },
    ),
  );
}
