import 'package:audioplayers/audioplayers.dart';

class MusicService {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;
  bool _muted = false;

  bool get muted => _muted;

  Future<void> init({required bool muted}) async {
    _muted = muted;
    if (_initialized) {
      await _applyMute();
      return;
    }

    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(0.6);
    await _player.play(AssetSource('audio/bg_music.mp3'));

    _initialized = true;
    await _applyMute();
  }

  Future<void> setMuted(bool muted) async {
    _muted = muted;
    await _applyMute();
  }

  Future<void> _applyMute() async {
    // Volume mute is simplest + reliable
    await _player.setVolume(_muted ? 0.0 : 0.6);
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.resume();
  Future<void> dispose() => _player.dispose();
}