import 'admin_delete.dart';
import 'admin_doctor_profile.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'admin_schema.dart';
import 'admin_display.dart';
import 'admin_practice_form.dart';
import 'doctor_account.dart';
import 'admin_data.dart';
import 'admin_navigation.dart';
import 'admin_ui.dart';
import 'admin_dashboard.dart';
import 'admin_schedules.dart';
import 'admin_staff.dart';
import 'api.dart';
import 'config.dart';
import 'widgets.dart';
import 'features/admin/application/admin_catalog_cubit.dart';
import 'features/admin/application/admin_catalog_state.dart';
import 'features/admin/data/admin_catalog_repository.dart';
import 'features/admin/data/admin_schedule_repository.dart';
import 'features/admin/application/practice_schedule_cubit.dart';
import 'features/admin/application/slot_session_cubit.dart';
import 'features/admin/data/admin_slot_repository.dart';
import 'features/admin/data/admin_staff_repository.dart';
import 'features/admin/application/staff_management_cubit.dart';
import 'features/admin/application/display_management_cubit.dart';
import 'features/admin/application/display_management_state.dart';
import 'features/admin/data/admin_display_repository.dart';
import 'queueb_motion.dart';
import 'queueb_interaction_motion.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({
    super.key,
    required this.api,
    this.initialSection = -1,
    this.onProfile,
    this.section,
    this.onSection,
    this.routeChild,
  }) : assert(initialSection >= -1 && initialSection < 8);
  final QueueApi api;
  final int? section;
  final ValueChanged<int>? onSection;
  final Widget? routeChild;
  final int initialSection;
  final VoidCallback? onProfile;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _selected = -1;
  int get selected => widget.section ?? _selected;
  int staffTab = 0;
  bool collapsed = false;
  late final AdminCatalogRepository catalogRepository;
  late final List<AdminCatalogCubit> catalogCubits;
  late final AdminScheduleRepository scheduleRepository;
  late final AdminSlotRepository slotRepository;
  late final StaffAccountCubit staffAccounts;
  late final AssignmentCubit assignments;
  late final DisplayManagementCubit displayManagement;
  final slotSessions = <String, SlotSessionCubit>{};
  SlotSessionCubit slotsFor(Json session) => slotSessions.putIfAbsent(
    '${session['id']}',
    () => SlotSessionCubit(slotRepository, session),
  );
  SlotSessionCubit slotsById(String id) {
    final session = (catalog['/jadwal-praktik'] ?? [])
        .where((r) => r['id'] == id)
        .firstOrNull;
    if (session == null) {
      throw const ApiException(
        404,
        'Sesi praktik tidak lagi tersedia. Muat ulang daftar.',
      );
    }
    return slotsFor(session);
  }

  Map<String, List<Json>> get catalog => catalogRepository.snapshot.collections;
  AdminCatalogCubit? get masterCubit => selected >= 0 && selected < 5
      ? catalogCubits[selected]
      : selected == 6
      ? staffTab == 0
            ? staffAccounts
            : assignments
      : null;
  List<Json> get data => masterCubit?.rows ?? const [];
  String? session, _error, _message;
  QueueBMotionOnce? _messageMotion;
  String? get message => _message;
  set message(String? value) {
    _message = value;
    // Existing assignments occur at successful CRUD/dialog completion. This
    // presentation identity also distinguishes repeated identical save text.
    _messageMotion =
        value != null && catalogRepository.active && widget.routeChild == null
        ? QueueBMotionOnce()
        : null;
  }

  String? get error => selected == 6 && staffTab == 0
      ? _error
      : masterCubit?.state.error?.toString() ?? _error;
  set error(String? value) => _error = value;
  String scheduleSearch = '';
  bool _loading = true;
  bool get loading => selected == 7
      ? displayManagement.state.busy
      : masterCubit?.state.busy ?? _loading;
  set loading(bool value) => _loading = value;
  int revision = 0;
  int _requestRevision = 0;
  AdminResource get resource =>
      resources[selected >= 0 && selected < resources.length ? selected : 0];
  @override
  void initState() {
    super.initState();
    catalogRepository = AdminCatalogRepository(widget.api);
    scheduleRepository = AdminScheduleRepository(catalogRepository);
    slotRepository = AdminSlotRepository(catalogRepository);
    displayManagement = DisplayManagementCubit(
      AdminDisplayRepository(catalogRepository),
    );
    final staffRepository = AdminStaffRepository(catalogRepository);
    staffAccounts = StaffAccountCubit(staffRepository);
    assignments = AssignmentCubit(staffRepository);
    catalogCubits = [
      PolyclinicCubit(catalogRepository),
      DoctorCatalogCubit(catalogRepository),
      RoomCubit(catalogRepository),
      ServiceScheduleCubit(scheduleRepository),
      PracticeScheduleCubit(scheduleRepository),
      staffAccounts,
      assignments,
    ];
    catalogRepository.addListener(_catalogChanged);
    _selected = widget.initialSection;
    load();
  }

  void _catalogChanged() {
    if (mounted) {
      setState(() {
        revision++;
        if (!catalogRepository.active) {
          _requestRevision++;
          session = null;
          _error = null;
          message = null;
          _loading = false;
        }
      });
    }
  }

  @override
  void dispose() {
    catalogRepository.removeListener(_catalogChanged);
    for (final cubit in catalogCubits) {
      cubit.close();
    }
    for (final cubit in slotSessions.values) {
      cubit.close();
    }
    displayManagement.close();
    catalogRepository.dispose();
    super.dispose();
  }

  Future<void> load({bool reloadCatalog = false}) async {
    if (selected == 7) {
      await displayManagement.refresh();
      return;
    }
    final openSlots = selected == 5
        ? {
            for (final c in slotSessions.values.where((c) => c.expanded))
              c: c.invalidationRevision,
          }
        : <SlotSessionCubit, int>{};
    final current = ++_requestRevision;
    final selectedResource = resource;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final paths = catalog.isEmpty || reloadCatalog || selected == -1
          ? resources
                .where((r) => r.path != '/slot-praktik')
                .map((r) => r.path)
                .toList()
          : selectedResource.path == '/slot-praktik'
          ? ['/jadwal-praktik', '/dokter', '/layanan', '/loket']
          : [selectedResource.path];
      if (selected == 6) paths.add('/akun-petugas');
      if (masterCubit case final cubit?) {
        await cubit.refresh(paths: paths);
        return;
      }
      await catalogRepository.refresh(paths);
      // A manual page reload refreshes open sessions even if their reference
      // projection is unchanged; dependency invalidations already start a read.
      await Future.wait(
        openSlots.entries.map(
          (e) => e.key.invalidationRevision == e.value
              ? e.key.refresh()
              : e.key.settled,
        ),
      );
      final next = catalog;
      if (mounted &&
          current == _requestRevision &&
          selectedResource.path == '/slot-praktik') {
        if (!next['/jadwal-praktik']!.any((v) => v['id'] == session)) {
          session = next['/jadwal-praktik']!.firstOrNull?['id'];
        }
      }
    } catch (e) {
      if (mounted && current == _requestRevision) setState(() => error = '$e');
    } finally {
      if (mounted && current == _requestRevision) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> edit([Json? row]) async {
    final cubit = masterCubit;
    final slot = resource.path == '/slot-praktik';
    final bulk = resource.path == '/jadwal-layanan' && row == null;
    final changed = await showDialog<bool>(
      context: context,
      animationStyle: QueueBMotion.modalStyle(context),
      barrierDismissible: false,
      builder: (context) => QueueBModalMotion(
        child: bulk
            ? BulkScheduleEditor(
                api: widget.api,
                clinics: catalog['/layanan'] ?? [],
                repository: scheduleRepository,
              )
            : resource.path == '/jadwal-praktik'
            ? PracticeScheduleEditor(
                api: widget.api,
                catalog: catalog,
                catalogSource: catalogRepository,
                row: row,
                onSave: cubit == null
                    ? null
                    : (body) => cubit.save(body, id: row?['id'] as String?),
              )
            : resource.path == '/dokter'
            ? AdminDoctorEditor(
                api: widget.api,
                row: row,
                saveProfile: cubit == null
                    ? null
                    : (id, body) => cubit.save(body, id: id),
              )
            : _AdminEditor(
                api: widget.api,
                resource: resource,
                row: row,
                catalog: catalog,
                initialSession: session,
                catalogSource:
                    resource.path == '/jadwal-layanan' ||
                        resource.path == '/penugasan-petugas'
                    ? catalogRepository
                    : null,
                onSave: cubit == null
                    ? slot
                          ? (body) => slotsById(
                              '${row?['jadwalPraktikId'] ?? body['jadwalPraktikId']}',
                            ).save(body, id: row?['id'] as String?)
                          : null
                    : (body) => cubit.save(body, id: row?['id'] as String?),
              ),
      ),
    );
    if (mounted && (changed == true || bulk || resource.path == '/dokter')) {
      if ((cubit != null || slot) && changed == true) _error = null;
      setState(
        () => message = changed != true
            ? null
            : bulk
            ? 'Proses jadwal selesai. Daftar diperbarui; periksa hasil per hari.'
            : resource.path == '/dokter' && row == null
            ? 'Profil dokter disimpan. Lanjutkan Hubungkan poliklinik, lalu Buat akun login pada baris dokter.'
            : 'Data disimpan.',
      );
      // Keep the batch close refresh, including recovery after a failed final
      // reconciliation. Photos/accounts still remain separate doctor flows.
      if (bulk || (cubit == null && !slot) || resource.path == '/dokter') {
        await load(reloadCatalog: true);
      }
    }
  }

  Future<void> deleteRow(Json row) async {
    final cubit = masterCubit;
    final slot = resource.path == '/slot-praktik'
        ? slotsById('${row['jadwalPraktikId']}')
        : null;
    final result = await showAdminDelete(
      context,
      widget.api,
      resource.path,
      row,
      onDelete: cubit == null
          ? slot == null
                ? null
                : () async {
                    await slot.delete('${row['id']}');
                  }
          : () async {
              await cubit.delete('${row['id']}');
            },
      name: resource.path == '/jadwal-layanan'
          ? '${label(object(row['layanan']))} · ${dayLabel('${row['hari']}')}'
          : resource.path == '/penugasan-petugas'
          ? label(object(row['petugas']))
          : null,
    );
    if (!mounted) return;
    if (result == AdminDeleteResult.deactivate) {
      await deactivateRow(row);
      return;
    }
    if (result == AdminDeleteResult.deleted) {
      _error = null;
      setState(() => message = 'Data berhasil dihapus permanen.');
      if (cubit == null && slot == null) await load(reloadCatalog: true);
    }
  }

  Future<void> deactivateRow(Json row) async {
    if (!await confirm(
      context,
      'Nonaktifkan ${resource.path == '/jadwal-layanan' ? '${label(object(row['layanan']))} · ${dayLabel('${row['hari']}')}' : label(row)}? Riwayat tetap disimpan.',
    )) {
      return;
    }
    if (resource.path == '/slot-praktik') {
      setState(() {
        _error = null;
        message = null;
      });
      try {
        await slotsById('${row['jadwalPraktikId']}').deactivate('${row['id']}');
        if (mounted) setState(() => message = 'Data dinonaktifkan.');
      } catch (e) {
        if (mounted) setState(() => error = '$e');
      }
      return;
    }
    if (masterCubit case final cubit?) {
      setState(() {
        _error = null;
        message = null;
      });
      try {
        await cubit.deactivate('${row['id']}');
        if (mounted) setState(() => message = 'Data dinonaktifkan.');
      } catch (e) {
        if (mounted) setState(() => error = '$e');
      }
      return;
    }
    setState(() => loading = true);
    try {
      await widget.api.request('DELETE', '${resource.path}/${row['id']}');
      if (mounted) setState(() => message = 'Data dinonaktifkan.');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) {
        final previousError = error;
        await load(reloadCatalog: true);
        if (mounted && previousError != null) {
          setState(() => error = previousError);
        }
      }
    }
  }

  Future<void> doctorLinks(Json doctor) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _DoctorLinks(
        api: widget.api,
        doctor: doctor,
        services: catalog['/layanan'] ?? [],
      ),
    );
    if (mounted) await load(reloadCatalog: true);
  }

  String detail(Json row) => switch (resource.path) {
    '/layanan' =>
      '${row['kode']} · ${row['modeReservasi']} · ${row['durasiDasarMenit']} menit',
    '/dokter' =>
      '${row['kode']} · ${row['spesialisasi'] ?? 'Dokter'}\n${rows(row['dokterLayanan']).where((v) => v['aktif'] == true).map((v) => label(object(v['layanan']))).join(', ')}',
    '/jadwal-praktik' =>
      '${label(object(object(row['dokterLayanan'])['dokter']))} · ${label(object(row['loket']))}\n${widget.api.config.instantLabel(row['mulaiPada'])} – ${widget.api.config.instantLabel(row['selesaiPada'])}',
    '/slot-praktik' =>
      '${widget.api.config.instantLabel(row['mulaiPada'])} – ${widget.api.config.instantLabel(row['selesaiPada'])}\n${row['jumlahJanjiTemu']} terisi / ${row['kapasitas']} · ${row['tersedia'] == true ? 'Tersedia' : 'Tidak tersedia'}',
    '/jadwal-layanan' =>
      '${label(object(row['layanan']))} · ${row['hari']}\n${clockOnly(row['jamBuka'])}–${clockOnly(row['jamTutup'])} · Kuota ${row['kapasitasHarian']}',
    '/penugasan-petugas' =>
      '${label(object(row['petugas']))} · ${label(object(row['loket']))}\n${dateOnly(row['tanggalMulai'])} → ${row['tanggalSelesai'] == null ? 'Tanpa akhir' : dateOnly(row['tanggalSelesai'])}',
    _ => '${label(object(row['layanan']))} · ${row['lokasi'] ?? ''}',
  };
  @override
  void didUpdateWidget(covariant AdminPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.section != oldWidget.section) {
      message = null;
      error = null;
      if (selected != 7) load();
    }
  }

  void selectResource(int value) {
    if (widget.onSection case final navigate?) {
      navigate(value);
      return;
    }
    setState(() {
      _selected = value;
      message = null;
      error = null;
    });
    if (value != 7) load();
  }

  Future<void> openMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: QueueBMotion.modalStyle(context),
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: AdminNavigation(
            selected: selected,
            onProfile: widget.onProfile == null
                ? null
                : () {
                    Navigator.pop(sheetContext);
                    widget.onProfile!();
                  },
            onSelect: loading
                ? null
                : (value) {
                    Navigator.pop(sheetContext);
                    selectResource(value);
                  },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider<PolyclinicCubit>.value(
        value: catalogCubits[0] as PolyclinicCubit,
      ),
      BlocProvider<DoctorCatalogCubit>.value(
        value: catalogCubits[1] as DoctorCatalogCubit,
      ),
      BlocProvider<RoomCubit>.value(value: catalogCubits[2] as RoomCubit),
      BlocProvider<ServiceScheduleCubit>.value(
        value: catalogCubits[3] as ServiceScheduleCubit,
      ),
      BlocProvider<PracticeScheduleCubit>.value(
        value: catalogCubits[4] as PracticeScheduleCubit,
      ),
      BlocProvider<StaffAccountCubit>.value(value: staffAccounts),
      BlocProvider<AssignmentCubit>.value(value: assignments),
      BlocProvider<DisplayManagementCubit>.value(value: displayManagement),
    ],
    child: _AdminViewScope(
      owner: this,
      child: widget.routeChild ?? _standaloneContent(),
    ),
  );

  Widget _standaloneContent() => selected == 7
      ? BlocSelector<DisplayManagementCubit, DisplayManagementState, bool>(
          bloc: displayManagement,
          selector: (s) => s.busy,
          builder: (context, _) => _buildContent(context),
        )
      : masterCubit == null
      ? _buildContent(context)
      : BlocBuilder<AdminCatalogCubit, AdminCatalogState>(
          bloc: masterCubit,
          builder: (context, _) => _buildContent(context),
        );

  Widget _buildContent(BuildContext context) {
    final toolbarActions = <Widget>[
      FilledButton.icon(
        onPressed: loading ? null : () => edit(),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Tambah'),
      ),
      OutlinedButton.icon(
        onPressed: loading ? null : () => load(reloadCatalog: true),
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Muat ulang'),
      ),
    ];
    final content = selected == 7
        ? AdminDisplayPage(api: widget.api, cubit: displayManagement)
        : selected == -1
        ? ListView(
            padding: const EdgeInsets.all(AdminStyle.pagePadding),
            children: [
              SizedBox(
                height: loading ? 4 : 0,
                child: loading ? const LinearProgressIndicator() : null,
              ),
              error != null
                  ? AdminNotice(error!, error: true)
                  : const SizedBox.shrink(),
              AdminDashboard(
                administratorName: widget.api.user?['nama'] as String?,
                onRefresh: () => load(reloadCatalog: true),
                catalog: catalog,
                config: widget.api.config,
                loading: loading,
                onSelect: selectResource,
              ),
            ],
          )
        : ListView(
            padding: const EdgeInsets.all(AdminStyle.pagePadding),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      resource.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (selected == 1)
                    TextButton.icon(
                      icon: const Icon(Icons.help_outline, size: 18),
                      label: const Text('Panduan dokter'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Pengelolaan dokter'),
                          content: const Text(
                            '1. Buat profil → 2. Hubungkan poliklinik → 3. Buat akun login.\n\nStatus profil dan akun login dikelola terpisah; profil nonaktif tidak dapat mengakses portal.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Mengerti'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              error != null
                  ? AdminNotice(error!, error: true)
                  : const SizedBox.shrink(),
              if (message != null)
                if (_messageMotion case final event?)
                  QueueBMicroEntrance(
                    key: const ValueKey('admin-crud-feedback'),
                    once: event,
                    child: AdminNotice(message!),
                  )
                else
                  AdminNotice(message!),
              if (selected == 6) ...[
                const SizedBox(height: 8),
                TabBar(
                  controller: null,
                  tabs: const [
                    Tab(text: 'Akun Petugas'),
                    Tab(text: 'Penugasan Loket'),
                  ],
                  onTap: (v) => setState(() => staffTab = v),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: loading ? 4 : 0,
                child: loading ? const LinearProgressIndicator() : null,
              ),
              if (selected == 6 && staffTab == 0)
                AdminStaffAccounts(
                  cubit: staffAccounts,
                  api: widget.api,
                  accounts: catalog['/akun-petugas'] ?? [],
                  busy: loading,
                  onChanged: () => load(reloadCatalog: true),
                )
              else if (resource.path == '/jadwal-layanan')
                GroupedClinicSchedules(
                  toolbarActions: toolbarActions,
                  clinics: catalog['/layanan'] ?? [],
                  schedules: data,
                  search: scheduleSearch,
                  onSearch: (value) => setState(() => scheduleSearch = value),
                  onEdit: edit,
                  onDeactivate: deactivateRow,
                  onDelete: deleteRow,
                  busy: loading,
                )
              else
                AdminDataView(
                  slotSession: slotsFor,
                  toolbarActions: toolbarActions,
                  key: ValueKey(resource.path),
                  resource: resource,
                  data: data,
                  catalog: catalog,
                  api: widget.api,
                  busy: loading,
                  revision: revision,
                  onEdit: edit,
                  onDeactivate: deactivateRow,
                  onDelete: deleteRow,
                  onDoctorAccount: (doctor) async {
                    final changed = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          DoctorAccountDialog(api: widget.api, doctor: doctor),
                    );
                    if (mounted) {
                      if (changed == true) {
                        setState(
                          () => message = 'Akun login dokter berhasil ditautkan. Profil dan hubungan poliklinik dipertahankan.',
                        );
                      }
                      await load(reloadCatalog: true);
                    }
                  },
                  onDoctorLinks: doctorLinks,
                  detail: detail,
                ),
            ],
          );
    return Theme(
      data: AdminStyle.theme,
      child: DefaultTabController(
        length: 2,
        initialIndex: staffTab,
        child: Material(
          color: AdminStyle.theme.scaffoldBackgroundColor,
          child: LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 960
                ? Row(
                    children: [
                      SizedBox(
                        width: collapsed ? 64 : 216,
                        child: Material(
                          color: Colors.white,
                          child: AdminNavigation(
                            selected: selected,
                            onProfile: widget.onProfile,
                            onSelect: loading ? null : selectResource,
                            collapsed: collapsed,
                            onToggle: () =>
                                setState(() => collapsed = !collapsed),
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(
                          children: [
                            Tooltip(
                              message: 'Menu administrasi',
                              child: OutlinedButton.icon(
                                onPressed: loading ? null : openMenu,
                                icon: const Icon(Icons.menu),
                                label: Text(
                                  box.maxWidth < 375
                                      ? 'Menu'
                                      : 'Menu administrasi',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                selected == -1
                                    ? 'Dashboard'
                                    : selected == 7
                                    ? 'Manajemen Display'
                                    : resource.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: content),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The shell owns repositories/providers; leaf routes only render this projection.
class AdminRouteView extends StatelessWidget {
  const AdminRouteView({super.key});
  @override
  Widget build(BuildContext context) {
    final owner = context
        .dependOnInheritedWidgetOfExactType<_AdminViewScope>()!
        .owner;
    return owner._standaloneContent();
  }
}

class _AdminViewScope extends InheritedWidget {
  const _AdminViewScope({required this.owner, required super.child});
  final _AdminPageState owner;
  @override
  bool updateShouldNotify(_AdminViewScope oldWidget) => true;
}

class _AdminEditor extends StatefulWidget {
  const _AdminEditor({
    required this.api,
    required this.resource,
    required this.catalog,
    this.row,
    this.initialSession,
    this.onSave,
    this.catalogSource,
  });
  final QueueApi api;
  final Future<Json> Function(Json)? onSave;
  final AdminCatalogRepository? catalogSource;
  final AdminResource resource;
  final Map<String, List<Json>> catalog;
  final Json? row;
  final String? initialSession;
  @override
  State<_AdminEditor> createState() => _AdminEditorState();
}

class _AdminEditorState extends State<_AdminEditor> {
  Map<String, List<Json>> get catalog =>
      widget.catalogSource?.snapshot.collections ?? widget.catalog;
  final form = GlobalKey<FormState>();
  final Map<String, TextEditingController> controllers = {};
  final Map<String, String> values = {};
  bool busy = false;
  String? error;
  bool get editing => widget.row != null;
  List<AdminField> get fields => widget.resource.fields
      .where((f) => !(editing && f.createOnly) && !(!editing && f.editOnly))
      .toList();
  @override
  void initState() {
    super.initState();
    for (final f in fields) {
      final v = widget.row?[f.key];
      values[f.key] = v == null
          ? f.key == 'jadwalPraktikId'
                ? widget.initialSession ?? ''
                : f.initial
          : switch (f.kind) {
              FieldKind.instant => widget.api.config.localInput(v),
              FieldKind.clock => clockOnly(v),
              FieldKind.date => dateOnly(v),
              _ => '$v',
            };
      controllers[f.key] = TextEditingController(text: values[f.key]);
    }
  }

  List<(String, String)> options(AdminField field) {
    if (field.options.isNotEmpty) {
      return field.options.map((v) => (v, v.replaceAll('_', ' '))).toList();
    }
    if (field.key == 'layananId') {
      return choicesOf(catalog['/layanan'] ?? []);
    }
    if (field.key == 'loketId') {
      final links = (catalog['/dokter'] ?? []).expand(
        (d) => rows(d['dokterLayanan']),
      );
      final service = links
          .where((v) => v['id'] == values['dokterLayananId'])
          .firstOrNull?['layananId'];
      return choicesOf(
        (catalog['/loket'] ?? [])
            .where(
              (v) =>
                  (service == null || v['layananId'] == service) &&
                  (widget.resource.path != '/penugasan-petugas' ||
                      (v['aktif'] == true &&
                          object(v['layanan'])['aktif'] == true) ||
                      v['id'] == widget.row?['loketId']),
            )
            .toList(),
      );
    }
    if (field.key == 'dokterLayananId') {
      return [
        for (final d in catalog['/dokter'] ?? <Json>[])
          for (final l in rows(
            d['dokterLayanan'],
          ).where((v) => v['aktif'] == true))
            ('${l['id']}', '${label(d)} · ${label(object(l['layanan']))}'),
      ];
    }
    if (field.key == 'jadwalPraktikId') {
      return (catalog['/jadwal-praktik'] ?? [])
          .map(
            (v) => (
              '${v['id']}',
              '${dateOnly(v['tanggal'])} · ${label(object(object(v['dokterLayanan'])['dokter']))} · ${label(object(v['loket']))}',
            ),
          )
          .toList();
    }
    return [];
  }

  Future<void> pick(AdminField f) async {
    if (busy) return;
    var input = values[f.key] ?? '';
    final session = (catalog['/jadwal-praktik'] ?? [])
        .where((s) => s['id'] == values['jadwalPraktikId'])
        .firstOrNull;
    var day =
        DateTime.tryParse(input.split('T').first) ??
        DateTime.tryParse(dateOnly(session?['tanggal'])) ??
        DateTime.parse(widget.api.config.today);
    if (f.kind != FieldKind.clock) {
      final chosen = await showDatePicker(
        context: context,
        initialDate: day,
        firstDate: DateTime(1000),
        lastDate: DateTime(9999, 12, 31),
        initialEntryMode: DatePickerEntryMode.calendarOnly,
      );
      if (!mounted || chosen == null) return;
      day = chosen;
      if (f.kind == FieldKind.date) {
        setState(() {
          values[f.key] = calendarDate(day);
          controllers[f.key]!.text = values[f.key]!;
        });
        return;
      }
    }
    if (!mounted) return;
    final clock = f.kind == FieldKind.clock ? input : input.split('T').last;
    final valid = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(clock);
    final chosen = await showTimePicker(
      context: context,
      initialTime: valid
          ? TimeOfDay(
              hour: int.parse(clock.substring(0, 2)),
              minute: int.parse(clock.substring(3, 5)),
            )
          : const TimeOfDay(hour: 8, minute: 0),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || chosen == null) return;
    setState(() {
      values[f.key] =
          '${f.kind == FieldKind.instant ? '${calendarDate(day)}T' : ''}${two(chosen.hour)}:${two(chosen.minute)}';
      controllers[f.key]!.text = values[f.key]!;
    });
  }

  Widget input(AdminField f) => TextFormField(
    controller: controllers[f.key],
    enabled: !busy,
    readOnly: [
      FieldKind.date,
      FieldKind.clock,
      FieldKind.instant,
    ].contains(f.kind),
    onTap: [FieldKind.date, FieldKind.clock, FieldKind.instant].contains(f.kind)
        ? () => pick(f)
        : null,
    decoration: InputDecoration(
      labelText: f.title,
      suffixIcon:
          [FieldKind.date, FieldKind.clock, FieldKind.instant].contains(f.kind)
          ? IconButton(
              tooltip: 'Pilih ${f.title}',
              onPressed: busy ? null : () => pick(f),
              icon: Icon(
                f.kind == FieldKind.clock
                    ? Icons.schedule
                    : Icons.calendar_month_outlined,
              ),
            )
          : null,
    ),
    keyboardType: f.kind == FieldKind.integer
        ? TextInputType.number
        : TextInputType.text,
    onChanged: (v) => values[f.key] = v.trim(),
    validator: (v) {
      final invalid = validateAdminField(f, v?.trim() ?? '', widget.api.config);
      if (invalid != null) return invalid;
      if (f.key == 'jamTutup' &&
          !scheduleClosesAfter(
            values['jamBuka'] ?? '',
            values['jamTutup'] ?? '',
          )) {
        return 'Jam tutup harus sesudah jam buka.';
      }
      if (f.key == 'selesaiPada' &&
          (values['mulaiPada'] ?? '').isNotEmpty &&
          (values['selesaiPada'] ?? '').compareTo(values['mulaiPada']!) <= 0) {
        return 'Jam selesai harus sesudah jam mulai.';
      }
      return null;
    },
  );

  Widget staffField(AdminField f) {
    final accounts = catalog['/akun-petugas'] ?? <Json>[];
    final eligible = accounts
        .where(
          (a) =>
              a['peran'] == 'PETUGAS' &&
              (a['aktif'] == true || a['id'] == widget.row?['petugasId']),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSearchChoice(
          label: 'Petugas (nama / email)',
          choices: eligible
              .map(
                (a) => (
                  '${a['id']}',
                  '${a['nama']} · ${a['email']}${a['aktif'] == true ? '' : ' (akun nonaktif)'}',
                ),
              )
              .toList(),
          value: (values[f.key] ?? '').isEmpty ? null : values[f.key],
          onChanged: busy
              ? null
              : (v) => setState(() => values[f.key] = v ?? ''),
        ),
        if (!accounts.any((a) => a['aktif'] == true))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Belum ada akun PETUGAS aktif. Buat atau aktifkan akun pada tab Akun Petugas.',
            ),
          ),
      ],
    );
  }

  Widget field(AdminField f) => f.key == 'petugasId'
      ? staffField(f)
      : switch (f.kind) {
          FieldKind.flag => SwitchListTile(
            title: Text(f.title),
            value: values[f.key] == 'true',
            onChanged: busy
                ? null
                : (v) => setState(() => values[f.key] = '$v'),
          ),
          FieldKind.choice =>
            options(f).length > 10
                ? AdminSearchChoice(
                    label: f.title,
                    choices: options(f),
                    value: values[f.key],
                    required: f.required,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            values[f.key] = v ?? '';
                            if (f.key == 'dokterLayananId') {
                              values['loketId'] = '';
                            }
                          }),
                  )
                : ChoiceField(
                    label: f.title,
                    choices: options(f),
                    value: values[f.key],
                    required: f.required,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            values[f.key] = v ?? '';
                            if (f.key == 'dokterLayananId') {
                              values['loketId'] = '';
                            }
                          }),
                  ),
          _ => input(f),
        };

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final payload = adminPayload(
        widget.resource,
        values,
        editing,
        widget.api.config,
      );
      if (widget.onSave != null) {
        await widget.onSave!(payload);
      } else {
        await widget.api.request(
          editing ? 'PATCH' : 'POST',
          '${widget.resource.path}${editing ? '/${widget.row!['id']}' : ''}',
          body: payload,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error =
              widget.resource.path == '/layanan' &&
                  e is ApiException &&
                  e.status >= 500
              ? 'Server belum dapat menyimpan poliklinik (${e.status}). Minta pengelola memeriksa log API dan migration database. Periksa daftar sebelum mencoba lagi.'
              : '$e';
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.catalogSource == null
      ? _dialog(context)
      : ListenableBuilder(
          listenable: widget.catalogSource!,
          builder: (context, _) => _dialog(context),
        );
  Widget _dialog(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${editing ? 'Ubah' : 'Tambah'} ${widget.resource.title}'),
          const SizedBox(height: 8),
          const Text(
            'Kelola data layanan rumah sakit. Periksa isian sebelum menyimpan.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Zona waktu: ${widget.api.config.serviceTimeZone}'),
                error != null
                    ? AdminNotice(error!, error: true)
                    : const SizedBox.shrink(),
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: field(f),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Kembali'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Menyimpan…' : 'Simpan'),
        ),
      ],
    ),
  );
}

class _DoctorLinks extends StatefulWidget {
  const _DoctorLinks({
    required this.api,
    required this.doctor,
    required this.services,
  });
  final QueueApi api;
  final Json doctor;
  final List<Json> services;
  @override
  State<_DoctorLinks> createState() => _DoctorLinksState();
}

class _DoctorLinksState extends State<_DoctorLinks> {
  List<Json> links = [];
  String? service, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    links = rows(widget.doctor['dokterLayanan']);
  }

  Future<void> mutate([String? remove]) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final path = '/dokter/${widget.doctor['id']}/layanan';
      await widget.api.request(
        remove == null ? 'POST' : 'DELETE',
        remove == null ? path : '$path/$remove',
        body: remove == null ? {'layananId': service} : null,
      );
      final result = rows(await widget.api.request('GET', path));
      if (mounted) setState(() => links = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text('Poliklinik ${label(widget.doctor)}'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) Notice(error!, error: true),
              ...links
                  .where((l) => l['aktif'] == true)
                  .map(
                    (l) => ListTile(
                      title: Text(label(object(l['layanan']))),
                      trailing: IconButton(
                        tooltip: 'Lepaskan poliklinik',
                        onPressed: busy
                            ? null
                            : () => mutate('${l['layananId']}'),
                        icon: const Icon(Icons.link_off),
                      ),
                    ),
                  ),
              ChoiceField(
                label: 'Poliklinik untuk dihubungkan',
                choices: choicesOf(
                  widget.services.where((v) => v['aktif'] == true).toList(),
                ),
                value: service,
                onChanged: busy ? null : (v) => setState(() => service = v),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy || service == null ? null : () => mutate(),
                child: const Text('Hubungkan'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}
