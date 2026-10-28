import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'config.dart';
import 'patient_design.dart';
import 'patient_home.dart';
import 'patient_ui.dart';

/// Home presentation only; booking and invalidation remain in PatientPage.
enum PatientHomeMode { walkIn, appointment }

abstract final class PatientHomeV6Style {
  static const walkIn = PatientDesign.primary;
  static const visit = PatientDesign.hero;
  static const soft = PatientDesign.soft;
}

// The existing API has no service-category field. These explicit service codes
// identify auxiliary desks, independently of the booking mode. No catalog rows
// are invented here; administrators still own the actual records in the API.
bool isAuxiliaryHomeService(Json clinic) => const {
  'PENDAFTARAN',
  'REGISTRASI',
  'ADMINISTRASI',
  'APOTEK',
  'APOTIK',
}.contains('${clinic['kode'] ?? ''}'.toUpperCase());

bool supportsHomeWalkIn(Json clinic) =>
    clinic['aktif'] != false &&
    isAuxiliaryHomeService(clinic) &&
    ['ANTREAN_HARIAN', 'HIBRIDA'].contains(clinic['modeReservasi']);

bool supportsHomeAppointment(Json clinic) =>
    clinic['aktif'] != false &&
    !isAuxiliaryHomeService(clinic) &&
    [
      'ANTREAN_HARIAN',
      'JANJI_TEMU_DOKTER',
      'HIBRIDA',
    ].contains(clinic['modeReservasi']);

List<Json> homeWalkInClinics(
  List<Json> clinics,
  List<Json> doctors,
  String query,
) => clinics.where((clinic) {
  if (!supportsHomeWalkIn(clinic)) return false;
  if ('${label(clinic)} ${clinic['deskripsi'] ?? ''} ${clinic['kode'] ?? ''}'
      .toLowerCase()
      .contains(query)) {
    return true;
  }
  return doctors.any(
    (doctor) =>
        doctor['aktif'] != false &&
        '${label(doctor)} ${doctor['spesialisasi'] ?? ''}'
            .toLowerCase()
            .contains(query) &&
        rows(doctor['dokterLayanan']).any(
          (link) => link['aktif'] == true && link['layananId'] == clinic['id'],
        ),
  );
}).toList();

class PatientHomeHeaderV6 extends StatelessWidget {
  const PatientHomeHeaderV6({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: PatientHomeV6Style.walkIn,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              size: 22,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 9),
          const Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'QueueB ',
                    style: TextStyle(color: PatientDesign.ink),
                  ),
                  TextSpan(
                    text: 'Hospital',
                    style: TextStyle(color: PatientHomeV6Style.walkIn),
                  ),
                ],
              ),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'Selamat datang,',
        style: TextStyle(fontSize: 12, color: PatientDesign.muted),
      ),
      Text(
        name,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: PatientDesign.ink,
        ),
      ),
    ],
  );
}

class PatientHomeModes extends StatelessWidget {
  const PatientHomeModes({
    super.key,
    required this.value,
    required this.onChanged,
    this.controller,
  });
  final PatientHomeMode value;
  final ValueChanged<PatientHomeMode>? onChanged;
  final TabController? controller;

  static double height(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(13) * 2 + 16).clamp(
        48,
        double.infinity,
      );

  @override
  Widget build(BuildContext context) {
    final tabs = AbsorbPointer(
      absorbing: onChanged == null,
      child: ExcludeFocus(
        excluding: onChanged == null,
        child: TabBar(
          controller: controller,
          labelColor: PatientDesign.primary,
          unselectedLabelColor: PatientDesign.muted,
          dividerColor: PatientDesign.border,
          indicatorColor: PatientDesign.primary,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.tab,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          onTap: controller != null
              ? null
              : (index) => onChanged?.call(PatientHomeMode.values[index]),
          tabs: [
            for (final mode in PatientHomeMode.values)
              Tab(
                key: ValueKey('home-mode-${mode.name}'),
                height: height(context),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      mode == PatientHomeMode.walkIn
                          ? Icons.groups_outlined
                          : Icons.calendar_month_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        mode == PatientHomeMode.walkIn
                            ? 'Ambil Antrean'
                            : 'Janji Temu',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    return controller != null
        ? tabs
        : DefaultTabController(
            length: 2,
            initialIndex: value.index,
            child: tabs,
          );
  }
}

/// Coordinated vertical scroll keeps the common header outside both pages.
/// Each page remains lazy and stores its own vertical position. Only this widget
/// owns the tab animation; it has no network listener or data controller.
class PatientHomeTabs extends StatefulWidget {
  const PatientHomeTabs({
    super.key,
    required this.value,
    required this.onChanged,
    required this.headerSlivers,
    required this.walkInSlivers,
    required this.appointmentSlivers,
  });
  final PatientHomeMode value;
  final ValueChanged<PatientHomeMode>? onChanged;
  final List<Widget> headerSlivers, walkInSlivers, appointmentSlivers;
  @override
  State<PatientHomeTabs> createState() => _PatientHomeTabsState();
}

class _PatientHomeTabsState extends State<PatientHomeTabs>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: 2,
    initialIndex: widget.value.index,
    animationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    vsync: this,
  )..addListener(_selectionChanged);

  void _selectionChanged() {
    if (_tabs.index != widget.value.index && !_tabs.indexIsChanging) {
      widget.onChanged?.call(PatientHomeMode.values[_tabs.index]);
    }
  }

  @override
  void didUpdateWidget(covariant PatientHomeTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tabs.index != widget.value.index && widget.value != oldWidget.value) {
      _tabs.animateTo(
        widget.value.index,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
      );
    }
  }

  @override
  Widget build(BuildContext context) => NestedScrollView(
    key: const PageStorageKey('patient-home-v6'),
    headerSliverBuilder: (context, innerScrolled) => [
      ...widget.headerSlivers,
      SliverOverlapAbsorber(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        sliver: SliverPersistentHeader(
          pinned: true,
          delegate: _HomeTabHeader(
            height: PatientHomeModes.height(context) + 3,
            child: PatientHomeModes(
              value: widget.value,
              controller: _tabs,
              onChanged: widget.onChanged,
            ),
          ),
        ),
      ),
    ],
    body: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          ...ScrollConfiguration.of(context).dragDevices,
          PointerDeviceKind.mouse,
        },
      ),
      child: TabBarView(
        key: const ValueKey('patient-home-tab-pages'),
        controller: _tabs,
        physics: widget.onChanged == null
            ? const NeverScrollableScrollPhysics()
            : null,
        children: [
          Builder(
            builder: (context) => CustomScrollView(
              key: const PageStorageKey('home-walk-in-list'),
              slivers: [
                SliverOverlapInjector(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                ),
                ...widget.walkInSlivers,
              ],
            ),
          ),
          Builder(
            builder: (context) => CustomScrollView(
              key: const PageStorageKey('home-appointment-list'),
              slivers: [
                SliverOverlapInjector(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                ),
                ...widget.appointmentSlivers,
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _tabs.removeListener(_selectionChanged);
    _tabs.dispose();
    super.dispose();
  }
}

class _HomeTabHeader extends SliverPersistentHeaderDelegate {
  const _HomeTabHeader({required this.height, required this.child});
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: PatientDesign.background,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    ),
  );
  @override
  bool shouldRebuild(covariant _HomeTabHeader oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
}

class PatientHomeService extends StatelessWidget {
  const PatientHomeService({super.key, required this.clinic, this.onTap});
  final Json clinic;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => _HomeListTile(
    onTap: onTap,
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: PatientHomeV6Style.soft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(
        clinicIcon(label(clinic)),
        color: PatientHomeV6Style.walkIn,
        size: 23,
      ),
    ),
    title: label(clinic),
    subtitle: 'Antrean harian · Pilih tanggal pelayanan',
    accent: PatientHomeV6Style.walkIn,
  );
}

class PatientHomeDoctorV6 extends StatelessWidget {
  const PatientHomeDoctorV6({
    super.key,
    required this.preview,
    required this.config,
    this.onTap,
    this.scheduleUnavailable = false,
  });
  final HomeDoctorPreview preview;
  final AppConfig config;
  final VoidCallback? onTap;
  final bool scheduleUnavailable;
  @override
  Widget build(BuildContext context) => PatientHomeDoctor(
    preview: preview,
    config: config,
    onTap: onTap,
    scheduleUnavailable: scheduleUnavailable,
  );
}

class _HomeListTile extends StatelessWidget {
  const _HomeListTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.onTap,
  });
  final Widget leading;
  final String title, subtitle;
  final Color accent;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: PatientDesign.paper,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: PatientDesign.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: PatientDesign.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: PatientDesign.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 22, color: accent),
          ],
        ),
      ),
    ),
  );
}
