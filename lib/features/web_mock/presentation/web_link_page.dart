import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/auth/application/auth_state.dart';
import 'package:exam_coach/features/web_mock/application/web_link_cubit.dart';
import 'package:exam_coach/features/web_mock/domain/web_link_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class WebLinkPage extends StatefulWidget {
  const WebLinkPage({super.key});
  @override
  State<WebLinkPage> createState() => _WebLinkPageState();
}

class _WebLinkPageState extends State<WebLinkPage> with WidgetsBindingObserver {
  late final WebLinkCubit _cubit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cubit = WebLinkCubit(context.read<WebLinkRepository>());
    if (context.read<AuthCubit>().state.isAuthenticated) _cubit.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _cubit.clear();
    } else if (context.read<AuthCubit>().state.isAuthenticated) {
      _cubit.load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<AuthCubit, AuthState>(
    listenWhen: (before, after) =>
        before.user?.uid != after.user?.uid ||
        before.isAuthenticated != after.isAuthenticated,
    listener: (context, state) {
      _cubit.clear();
      if (state.isAuthenticated) _cubit.load();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Kerjakan di laptop')),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, auth) {
          if (!_cubit.repository.isAvailable) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Link tryout belum tersedia pada versi ini. Belajar di aplikasi tetap tersedia.',
                ),
              ),
            );
          }
          if (!auth.isAuthenticated) {
            return Center(
              child: FilledButton(
                onPressed: () => context.push('/account'),
                child: const Text('Masuk untuk membuat link'),
              ),
            );
          }
          return BlocBuilder<WebLinkCubit, WebLinkState>(
            bloc: _cubit,
            builder: (context, state) {
              final management = state.management;
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Lanjutkan dari komputer',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pratinjau pengembangan: pembuatan dan pencabutan link tersedia untuk uji lokal. Pengerjaan soal di browser belum tersedia.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Link berlaku maksimal 12 jam. Jangan bagikan ke orang lain. Setelah disalin atau halaman ditutup, link tidak dapat ditampilkan ulang.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: state.busy ? null : _cubit.load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Muat ulang status'),
                  ),
                  if (state.busy) const LinearProgressIndicator(),
                  if (state.message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(state.message!),
                      ),
                    ),
                  if (state.hasCopy)
                    FilledButton.icon(
                      key: const Key('copy-web-link'),
                      onPressed: () => _cubit.copy(
                        (url) => Clipboard.setData(ClipboardData(text: url)),
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('Salin link sekali'),
                    ),
                  if (management != null) ...[
                    if (management.tryouts.isEmpty)
                      const Text('Belum ada tryout yang tersedia.'),
                    for (final tryout in management.tryouts)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tryout.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${tryout.questionCount} soal • ${tryout.durationSeconds ~/ 60} menit',
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed:
                                    state.busy ||
                                        management.links.any(
                                          (l) =>
                                              l.tryoutId == tryout.id &&
                                              l.canRevoke,
                                        )
                                    ? null
                                    : () => _cubit.create(tryout),
                                child: const Text('Buat link'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final link in management.links)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                management.tryouts
                                        .where((t) => t.id == link.tryoutId)
                                        .firstOrNull
                                        ?.title ??
                                    'Link tryout sebelumnya',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text('Status: ${_status(link.status)}'),
                              Text('Batas berlaku: ${_date(link.expiresAt)}'),
                              if (link.canRevoke)
                                OutlinedButton(
                                  onPressed: state.busy
                                      ? null
                                      : () => _cubit.revoke(link),
                                  child: const Text('Cabut link'),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              );
            },
          );
        },
      ),
    ),
  );

  String _date(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)} (waktu perangkat)';
  }

  String _status(WebLinkStatus status) => switch (status) {
    WebLinkStatus.active => 'Aktif',
    WebLinkStatus.claimed => 'Sedang digunakan',
    WebLinkStatus.expired => 'Kedaluwarsa',
    WebLinkStatus.revoked => 'Dicabut',
    WebLinkStatus.completed => 'Selesai',
    WebLinkStatus.timeout => 'Waktu habis',
  };
}
