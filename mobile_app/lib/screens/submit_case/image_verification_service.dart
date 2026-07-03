import 'dart:io';
import 'package:exif/exif.dart';

// ─────────────────────────────────────────────────────────────────
// CapturedImage — wraps a captured photo File with its verification
// status. Replaces the previous bare `File` entries in the photo list
// so each photo can carry per-item verification state.
// ─────────────────────────────────────────────────────────────────
class CapturedImage {
  final File file;
  final bool isVerified;

  const CapturedImage({required this.file, required this.isVerified});

  CapturedImage copyWith({File? file, bool? isVerified}) {
    return CapturedImage(
      file: file ?? this.file,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Result of verifying a single image. Kept intentionally minimal —
// no reason/rule information is surfaced to the UI layer, per the
// requirement that verification internals stay hidden from users.
// ─────────────────────────────────────────────────────────────────
class ImageVerificationResult {
  final bool isValid;

  const ImageVerificationResult({required this.isValid});
}

// ─────────────────────────────────────────────────────────────────
// ImageVerificationService
//
// Lightweight, metadata-only authenticity check performed after
// capture and before submission. Not an image-quality check (that
// already happens live during capture) and not a full forensic
// analysis — this only makes casual post-capture tampering harder.
//
// Two checks, agreed after reviewing actual platform/plugin behavior:
//
// 1. Capture timestamp (EXIF DateTimeOriginal, fallback CreateDate)
//    — only evaluated if present. The `camera` plugin used by
//    GuidedCameraScreen is confirmed (via camera plugin issue
//    tracker research, see flutter/flutter#39070) to omit full EXIF
//    on iOS in many cases, while Android reliably includes it. Since
//    we cannot distinguish "tampered" from "platform stripped it",
//    a missing timestamp is treated as inconclusive, not a failure.
//    A *present but inconsistent* timestamp is still a hard failure.
//
// 2. Editing-software tag (EXIF Software / ProcessingSoftware /
//    CreatorTool) — a hard rule regardless of platform. This is the
//    check that does most of the real work, since it doesn't depend
//    on platform EXIF completeness the way timestamps do.
// ─────────────────────────────────────────────────────────────────
class ImageVerificationService {
  // Configurable blacklist — extend as needed. Kept as a const list
  // per team decision; revisit only if evidence shows this needs to
  // be remotely updatable.
  static const List<String> _softwareBlacklist = [
    'adobe photoshop',
    'adobe lightroom',
    'gimp',
    'snapseed',
    'canva',
    'pixlr',
  ];

  // How far before session start a capture timestamp can be and
  // still be considered consistent. Guards against clock skew while
  // still catching clearly-reused old photos. Widened from an initial
  // 10-minute placeholder to reduce false positives from normal gaps
  // between session start and actual photo capture — revisit with
  // real usage data if needed.
  static const Duration _maxAgeBeforeSession = Duration(hours: 1);

  // ── TEMPORARY: set true to print raw EXIF tags + derived check
  //    results to console for real-device testing. Answers the open
  //    question of what this specific camera plugin/version actually
  //    writes on Android vs iOS. Remove once confirmed. ──
  static const bool _debugLogging = false;

  Future<ImageVerificationResult> verify(
    File image, {
    required DateTime sessionStart,
  }) async {
    Map<String, IfdTag> tags;
    try {
      final bytes = await image.readAsBytes();
      tags = await readExifFromBytes(bytes);
    } catch (e) {
      // Unreadable/corrupt metadata — treat like "no metadata at all"
      // rather than failing outright, consistent with how a missing
      // timestamp is handled below. Software-tag check simply can't
      // run either in this case.
      tags = {};
      if (_debugLogging) {
        print('[ImageVerification] EXIF read failed for ${image.path}: $e');
      }
    }

    if (_debugLogging) {
      print('[ImageVerification] ── ${image.path} ──');
      print('[ImageVerification] raw tag keys: ${tags.keys.toList()}');
      for (final key in tags.keys) {
        print('[ImageVerification]   $key = ${tags[key]?.printable}');
      }
    }

    // ── Check 2: editing-software tag — hard rule ──
    final hasBlacklistedTag = _hasBlacklistedSoftwareTag(tags);
    if (_debugLogging) {
      print(
        '[ImageVerification] Check 2 (software tag) flagged: $hasBlacklistedTag',
      );
    }
    if (hasBlacklistedTag) {
      return const ImageVerificationResult(isValid: false);
    }

    // ── Check 1: capture timestamp — only if present ──
    final capturedAt = _extractCaptureTimestamp(tags);
    if (_debugLogging) {
      print('[ImageVerification] Check 1 parsed capturedAt: $capturedAt');
      print('[ImageVerification] Check 1 sessionStart: $sessionStart');
    }
    if (capturedAt != null) {
      final earliestAcceptable = sessionStart.subtract(_maxAgeBeforeSession);
      final failsCheck1 = capturedAt.isBefore(earliestAcceptable);
      if (_debugLogging) {
        print(
          '[ImageVerification] Check 1 earliestAcceptable: $earliestAcceptable, fails: $failsCheck1',
        );
      }
      if (failsCheck1) {
        return const ImageVerificationResult(isValid: false);
      }
    } else if (_debugLogging) {
      print('[ImageVerification] Check 1 skipped — no timestamp present');
    }
    // If capturedAt is null, we simply don't evaluate this check —
    // absence of a timestamp is a known platform limitation, not
    // evidence of tampering.

    return const ImageVerificationResult(isValid: true);
  }

  bool _hasBlacklistedSoftwareTag(Map<String, IfdTag> tags) {
    final candidates = [
      tags['Image Software']?.printable,
      tags['EXIF ProcessingSoftware']?.printable,
      tags['Image ProcessingSoftware']?.printable,
      tags['EXIF CreatorTool']?.printable,
    ];

    for (final raw in candidates) {
      if (raw == null) continue;
      final normalized = raw.toLowerCase();
      for (final blocked in _softwareBlacklist) {
        if (normalized.contains(blocked)) return true;
      }
    }
    return false;
  }

  DateTime? _extractCaptureTimestamp(Map<String, IfdTag> tags) {
    final raw =
        tags['EXIF DateTimeOriginal']?.printable ??
        tags['Image DateTimeOriginal']?.printable ??
        tags['EXIF DateTimeDigitized']?.printable ??
        tags['Image DateTime']?.printable; // CreateDate fallback

    if (raw == null || raw.trim().isEmpty) return null;

    // EXIF datetime format: "YYYY:MM:DD HH:MM:SS"
    final match = RegExp(
      r'^(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$',
    ).firstMatch(raw.trim());
    if (match == null) return null;

    try {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }
}
