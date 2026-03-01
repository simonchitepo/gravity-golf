import 'package:shared_preferences/shared_preferences.dart';

class AudioSettings {
  static const _kMusicMuted = 'music_muted';

  static Future<bool> loadMuted() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kMusicMuted) ?? false;
  }

  static Future<void> saveMuted(bool muted) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kMusicMuted, muted);
  }
}