class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;

  const SemVer(this.major, this.minor, this.patch);

  static SemVer parse(String input) {
    var s = input.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final parts = s.split('.');
    if (parts.length < 2 || parts.length > 3) {
      throw FormatException('Invalid semver: $input');
    }
    final major = int.parse(parts[0]);
    final minor = int.parse(parts[1]);
    final patch = parts.length == 3 ? int.parse(parts[2]) : 0;
    return SemVer(major, minor, patch);
  }

  static SemVer? tryParse(String input) {
    try {
      return parse(input);
    } catch (_) {
      return null;
    }
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(SemVer other) => compareTo(other) > 0;
  bool operator <(SemVer other) => compareTo(other) < 0;
  bool operator >=(SemVer other) => compareTo(other) >= 0;
  bool operator <=(SemVer other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
