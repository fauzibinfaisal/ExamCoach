import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/auth/application/auth_state.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<LearningFlowCubit, LearningFlowState>(
          builder: (context, state) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'ExamCoach',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('account-button'),
                      tooltip: 'Akun & sinkronisasi',
                      onPressed: () => context.push('/account'),
                      icon: const Icon(Icons.account_circle_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 42),
                Text(
                  'Belajar dengan arah,\nbukan sekadar banyak soal.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  'Mulai tryout singkat. ExamCoach akan menghitung hasil, menemukan pola kelemahan, lalu menyiapkan latihan yang relevan.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                const _DemoNotice(),
                const SizedBox(height: 18),
                const _AccountSyncCard(),
                const SizedBox(height: 18),
                if (state.latestScore != null) ...[
                  _RecentResultCard(state: state),
                  const SizedBox(height: 18),
                ],
                if (state.errorMessage case final message?) ...[
                  _ErrorNotice(message: message),
                  const SizedBox(height: 18),
                ],
                if (state.hasActiveSession)
                  _ResumeSessionCard(state: state)
                else
                  _StartTryoutCard(state: state),
                const SizedBox(height: 22),
                const Row(
                  children: [
                    Expanded(
                      child: _ValueItem(
                        icon: Icons.insights_rounded,
                        title: 'Insight',
                        detail: 'Pahami pola',
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _ValueItem(
                        icon: Icons.track_changes_rounded,
                        title: 'Terarah',
                        detail: 'Latih prioritas',
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AccountSyncCard extends StatelessWidget {
  const _AccountSyncCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final (icon, title, detail) = switch (state.status) {
          AuthStatus.unavailable => (
            Icons.cloud_off_rounded,
            'Mode lokal',
            'Firebase belum dikonfigurasi; progres aman di perangkat.',
          ),
          AuthStatus.signedOut => (
            Icons.cloud_outlined,
            'Progres belum dicadangkan',
            'Masuk untuk sinkronisasi dan recovery lintas perangkat.',
          ),
          AuthStatus.processing => (
            Icons.sync_rounded,
            'Menghubungkan akun…',
            'Data lokal tetap tersedia selama proses berlangsung.',
          ),
          AuthStatus.signedIn => (
            Icons.cloud_done_rounded,
            'Akun terhubung',
            state.user?.email ?? 'Sinkronisasi Firebase aktif.',
          ),
        };
        return InkWell(
          key: const Key('account-sync-card'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/account'),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(detail),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StartTryoutCard extends StatelessWidget {
  const _StartTryoutCard({required this.state});

  final LearningFlowState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnostic TIU',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '6 soal • ±6 menit • Hasil langsung',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('start-tryout-button'),
              onPressed: state.isSaving
                  ? null
                  : () async {
                      final started = await context
                          .read<LearningFlowCubit>()
                          .startTryout();
                      if (started && context.mounted) {
                        context.go('/overview');
                      }
                    },
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(state.isSaving ? 'Menyiapkan…' : 'Mulai tryout'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeSessionCard extends StatelessWidget {
  const _ResumeSessionCard({required this.state});

  final LearningFlowState state;

  @override
  Widget build(BuildContext context) {
    final isReviewing = state.status == LearningFlowStatus.reviewing;
    final current = state.currentIndex + 1;
    final total = state.questions.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.offline_pin_rounded,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 9),
                Text(
                  'Sesi tersimpan',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isReviewing
                  ? 'Semua $total soal sudah direspons. Periksa jawaban sebelum hasil dihitung.'
                  : 'Lanjut dari soal $current dari $total. Jawaban sebelumnya sudah tersimpan di perangkat.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('resume-session-button'),
              onPressed: () =>
                  context.go(isReviewing ? '/session-review' : '/session'),
              icon: const Icon(Icons.restore_rounded),
              label: Text(isReviewing ? 'Periksa jawaban' : 'Lanjutkan sesi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF2D49A)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, size: 20, color: Color(0xFF8A5A00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mode pengembangan: pack draft hanya untuk pengujian. Materi resmi wajib berstatus published dan disetujui reviewer manusia.',
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentResultCard extends StatelessWidget {
  const _RecentResultCard({required this.state});

  final LearningFlowState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              child: Text(
                '${state.latestScore!.percentage}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hasil terakhir',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    state.profiles.isEmpty
                        ? 'Insight belum tersedia'
                        : 'Fokus: ${state.profiles.first.taxonomyLabel}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueItem extends StatelessWidget {
  const _ValueItem({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(detail, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
