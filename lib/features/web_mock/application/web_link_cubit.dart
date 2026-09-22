import 'dart:convert';
import 'dart:math';

import 'package:exam_coach/features/web_mock/domain/web_link_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class WebLinkState {
  const WebLinkState({
    this.management,
    this.busy = false,
    this.hasCopy = false,
    this.message,
  });
  final WebLinkManagement? management;
  final bool busy;
  final bool hasCopy;
  final String? message;
}

class WebLinkCubit extends Cubit<WebLinkState> {
  WebLinkCubit(this.repository) : super(const WebLinkState());
  final WebLinkRepository repository;
  String? _launchUrl;
  String? _owner;
  int _generation = 0;

  // Capability is deliberately absent from emitted states, routes and logs.
  void clear() {
    _generation++;
    _launchUrl = null;
    _owner = null;
    if (!isClosed) emit(const WebLinkState());
  }

  Future<void> load() => _run(() async {
    final management = await repository.load();
    return WebLinkState(management: management);
  });

  Future<void> create(WebTryout tryout) => _run(() async {
    final random = Random.secure();
    final requestId = base64Url
        .encode(List.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final result = await repository.create(tryout, requestId);
    // _run checks account and lifecycle generation before exposing this result.
    return _CreatedState(result, state.management);
  });

  Future<void> revoke(WebLinkSummary link) => _run(() async {
    final result = await repository.revoke(link.id);
    final before = state.management;
    return WebLinkState(
      management: before == null
          ? null
          : WebLinkManagement(
              serverNow: before.serverNow,
              tryouts: before.tryouts,
              links: before.links
                  .map((l) => l.id == result.id ? result : l)
                  .toList(),
            ),
      message: 'Status link sudah diperbarui.',
    );
  });

  Future<void> _run(Future<WebLinkState> Function() action) async {
    if (state.busy || isClosed) return;
    _launchUrl = null;
    final uid = repository.currentUserId;
    _owner = uid;
    final generation = ++_generation;
    emit(WebLinkState(management: state.management, busy: true));
    try {
      if (!repository.isAvailable) throw const WebLinkFailure('unavailable');
      if (uid == null) throw const WebLinkFailure('unauthenticated');
      final result = await action();
      if (!_accept(generation, uid)) return;
      if (result is _CreatedState) {
        _launchUrl = result.created.launchUrl;
        final link = result.created.link;
        emit(
          WebLinkState(
            management: WebLinkManagement(
              serverNow: result.created.serverNow,
              tryouts: result.before?.tryouts ?? [],
              links: [
                ...?result.before?.links.where(
                  (l) => l.tryoutId != link.tryoutId,
                ),
                link,
              ],
            ),
            hasCopy: _launchUrl != null,
            message: _launchUrl == null
                ? 'Link sudah dibuat sebelumnya. Token tidak dapat ditampilkan ulang; cabut untuk membuat pengganti.'
                : 'Link siap disalin sekali. Salin hanya ke perangkat Anda.',
          ),
        );
      } else {
        emit(result);
      }
    } on Object catch (error) {
      if (!_accept(generation, uid)) return;
      emit(
        WebLinkState(
          management: state.management,
          message:
              (error is WebLinkFailure
                      ? error
                      : const WebLinkFailure('unknown'))
                  .message,
        ),
      );
    }
  }

  bool _accept(int generation, String? uid) {
    if (isClosed || generation != _generation) return false;
    if (repository.currentUserId != uid) {
      clear();
      return false;
    }
    return true;
  }

  Future<bool> copy(Future<void> Function(String) write) async {
    final url = _launchUrl;
    if (url == null ||
        _owner == null ||
        repository.currentUserId != _owner ||
        state.busy) {
      clear();
      return false;
    }
    _launchUrl = null;
    final generation = _generation;
    emit(WebLinkState(management: state.management));
    try {
      await write(url);
      if (isClosed ||
          generation != _generation ||
          repository.currentUserId != _owner) {
        return false;
      }
      emit(
        WebLinkState(
          management: state.management,
          message:
              'Link disalin. Simpan hanya pada perangkat Anda; tautan memberi akses ke sesi.',
        ),
      );
      return true;
    } on Object {
      if (!isClosed && generation == _generation) {
        emit(
          WebLinkState(
            management: state.management,
            message: 'Link gagal disalin. Cabut link dan buat pengganti.',
          ),
        );
      }
      return false;
    }
  }

  @override
  Future<void> close() {
    _generation++;
    _launchUrl = null;
    _owner = null;
    return super.close();
  }
}

// Never emitted: holds the transient response only while _run verifies ownership.
class _CreatedState extends WebLinkState {
  const _CreatedState(this.created, this.before);
  final WebLinkCreated created;
  final WebLinkManagement? before;
}
