/// Value types for one parsed DMARC aggregate report, plus the derived
/// alignment and failure-cause columns.
library;

import 'package:dmarc_logger/src/results.dart';

/// Who sent the report and which period it covers.
class ReportMetadata {
  const ReportMetadata({
    required this.orgName,
    required this.reportId,
    required this.begin,
    required this.end,
    this.email,
    this.extraContactInfo,
  });

  final String orgName;
  final String reportId;
  final DateTime begin;
  final DateTime end;
  final String? email;
  final String? extraContactInfo;
}

/// The published DMARC policy the receiver evaluated against.
class PolicyPublished {
  const PolicyPublished({
    required this.domain,
    required this.adkim,
    required this.aspf,
    required this.p,
    this.sp,
    this.pct,
  });

  final String domain;
  final Lenient<AlignmentMode> adkim;
  final Lenient<AlignmentMode> aspf;
  final Lenient<Disposition> p;
  final Lenient<Disposition>? sp;
  final int? pct;
}

/// One DKIM authentication result. A record can carry several, one per
/// signature the receiver checked.
class DkimAuthDetail {
  const DkimAuthDetail({
    required this.domain,
    required this.result,
    this.selector,
  });

  final String domain;
  final String? selector;
  final Lenient<DkimAuthResult> result;
}

/// One SPF authentication result with the scope it was evaluated against.
class SpfAuthDetail {
  const SpfAuthDetail({required this.domain, required this.result, this.scope});

  final String domain;
  final Lenient<SpfScope>? scope;
  final Lenient<SpfAuthResult> result;
}

/// A receiver override of the policy evaluation, from
/// `policy_evaluated/reason`.
class PolicyReason {
  const PolicyReason({required this.type, this.comment});

  final String type;
  final String? comment;
}

/// One record of the report: traffic from one source IP with one evaluation.
class DmarcRecord {
  const DmarcRecord({
    required this.sourceIp,
    required this.count,
    required this.disposition,
    required this.dkimPolicy,
    required this.spfPolicy,
    required this.reasons,
    required this.headerFrom,
    required this.dkimResults,
    required this.spfResults,
  });

  final String sourceIp;
  final int count;
  final Lenient<Disposition> disposition;
  final Lenient<PolicyResult> dkimPolicy;
  final Lenient<PolicyResult> spfPolicy;
  final List<PolicyReason> reasons;
  final String headerFrom;
  final List<DkimAuthDetail> dkimResults;
  final List<SpfAuthDetail> spfResults;
}

/// A whole parsed aggregate report.
class DmarcReport {
  const DmarcReport({
    required this.metadata,
    required this.policy,
    required this.records,
  });

  final ReportMetadata metadata;
  final PolicyPublished policy;
  final List<DmarcRecord> records;
}

/// The DKIM evidence of one record, reduced to one outcome for the
/// failure-cause derivation.
enum DkimSummary {
  /// A signature passed and its `d=` aligns with `header_from`.
  passAligned,

  /// A signature passed, but for a third-party domain.
  passUnaligned,

  /// Definitive failure: `fail`, `policy` or `permerror`.
  failed,

  /// No usable signal: no `dkim` elements, `none` or `neutral`.
  absent,

  /// A transient error; the verdict is provisional.
  temperror,

  /// A value outside the RFC set.
  other,
}

/// The SPF evidence of one record, reduced like [DkimSummary].
enum SpfSummary { passAligned, passUnaligned, failed, absent, temperror, other }

/// Whether [candidate] (a passing DKIM `d=` or SPF domain) aligns with
/// [headerFrom] under [mode]: exact match for strict, same-or-subdomain for
/// relaxed.
///
/// Relaxed alignment per RFC 7489 compares organizational domains, which
/// needs a public-suffix list. The subdomain check used here agrees with that
/// for ordinary domains and errs only on multi-level public suffixes; the
/// receiver's own verdict in the neighboring `dkim`/`spf` columns stays the
/// authority, and any disagreement surfaces as the `verdict-differs` cause.
bool domainsAlign(
  String candidate,
  String headerFrom,
  Lenient<AlignmentMode> mode,
) {
  final left = _normalizeDomain(candidate);
  final right = _normalizeDomain(headerFrom);
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  return switch (mode) {
    Known(value: AlignmentMode.strict) => left == right,
    Known(value: AlignmentMode.relaxed) =>
      left == right || left.endsWith('.$right') || right.endsWith('.$left'),
    // An unknown mode constrains nothing; only an exact match counts then.
    Unknown() => left == right,
  };
}

String _normalizeDomain(String domain) {
  var normalized = domain.trim().toLowerCase();
  if (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// Whether any passing DKIM `d=` aligns with `header_from`: `null` when
/// nothing passed, so "no signature" stays distinct from "unaligned".
bool? dkimAligned(DmarcRecord record, Lenient<AlignmentMode> adkim) {
  var sawPass = false;
  var aligned = false;
  for (final detail in record.dkimResults) {
    final passes = switch (detail.result) {
      Known(value: DkimAuthResult.pass) => true,
      Known(
        value: DkimAuthResult.none ||
            DkimAuthResult.fail ||
            DkimAuthResult.policy ||
            DkimAuthResult.neutral ||
            DkimAuthResult.temperror ||
            DkimAuthResult.permerror,
      ) =>
        false,
      Unknown() => false,
    };
    if (passes) {
      sawPass = true;
      aligned =
          aligned || domainsAlign(detail.domain, record.headerFrom, adkim);
    }
  }
  if (!sawPass) {
    return null;
  }
  return aligned;
}

/// Whether any passing SPF domain aligns with `header_from`, like
/// [dkimAligned].
bool? spfAligned(DmarcRecord record, Lenient<AlignmentMode> aspf) {
  var sawPass = false;
  var aligned = false;
  for (final detail in record.spfResults) {
    final passes = switch (detail.result) {
      Known(value: SpfAuthResult.pass) => true,
      Known(
        value: SpfAuthResult.none ||
            SpfAuthResult.neutral ||
            SpfAuthResult.fail ||
            SpfAuthResult.softfail ||
            SpfAuthResult.temperror ||
            SpfAuthResult.permerror,
      ) =>
        false,
      Unknown() => false,
    };
    if (passes) {
      sawPass = true;
      aligned = aligned || domainsAlign(detail.domain, record.headerFrom, aspf);
    }
  }
  if (!sawPass) {
    return null;
  }
  return aligned;
}

DkimSummary _summarizeOneDkim(
  DkimAuthDetail detail,
  String headerFrom,
  Lenient<AlignmentMode> adkim,
) => switch (detail.result) {
  Known(value: DkimAuthResult.pass) =>
    domainsAlign(detail.domain, headerFrom, adkim)
        ? DkimSummary.passAligned
        : DkimSummary.passUnaligned,
  Known(value: DkimAuthResult.temperror) => DkimSummary.temperror,
  Known(
    value: DkimAuthResult.fail ||
        DkimAuthResult.policy ||
        DkimAuthResult.permerror,
  ) =>
    DkimSummary.failed,
  Known(value: DkimAuthResult.none || DkimAuthResult.neutral) =>
    DkimSummary.absent,
  Unknown() => DkimSummary.other,
};

SpfSummary _summarizeOneSpf(
  SpfAuthDetail detail,
  String headerFrom,
  Lenient<AlignmentMode> aspf,
) => switch (detail.result) {
  Known(value: SpfAuthResult.pass) =>
    domainsAlign(detail.domain, headerFrom, aspf)
        ? SpfSummary.passAligned
        : SpfSummary.passUnaligned,
  Known(value: SpfAuthResult.temperror) => SpfSummary.temperror,
  Known(
    value: SpfAuthResult.fail ||
        SpfAuthResult.softfail ||
        SpfAuthResult.permerror,
  ) =>
    SpfSummary.failed,
  Known(value: SpfAuthResult.none || SpfAuthResult.neutral) =>
    SpfSummary.absent,
  Unknown() => SpfSummary.other,
};

/// Priority order used when one record carries several results for a
/// mechanism: a definitive pass wins, then a provisional temperror, then a
/// definitive failure. Higher wins.
int _dkimPriority(DkimSummary summary) => switch (summary) {
  DkimSummary.passAligned => 5,
  DkimSummary.passUnaligned => 4,
  DkimSummary.temperror => 3,
  DkimSummary.failed => 2,
  DkimSummary.other => 1,
  DkimSummary.absent => 0,
};

/// Like [_dkimPriority] for SPF.
int _spfPriority(SpfSummary summary) => switch (summary) {
  SpfSummary.passAligned => 5,
  SpfSummary.passUnaligned => 4,
  SpfSummary.temperror => 3,
  SpfSummary.failed => 2,
  SpfSummary.other => 1,
  SpfSummary.absent => 0,
};

/// Reduces all DKIM results of [record] to one summary.
DkimSummary summarizeDkim(DmarcRecord record, Lenient<AlignmentMode> adkim) {
  var summary = DkimSummary.absent;
  for (final detail in record.dkimResults) {
    final next = _summarizeOneDkim(detail, record.headerFrom, adkim);
    if (_dkimPriority(next) > _dkimPriority(summary)) {
      summary = next;
    }
  }
  return summary;
}

/// Reduces all SPF results of [record] to one summary.
SpfSummary summarizeSpf(DmarcRecord record, Lenient<AlignmentMode> aspf) {
  var summary = SpfSummary.absent;
  for (final detail in record.spfResults) {
    final next = _summarizeOneSpf(detail, record.headerFrom, aspf);
    if (_spfPriority(next) > _spfPriority(summary)) {
      summary = next;
    }
  }
  return summary;
}

/// Reason types that describe forwarding. A record carrying one of these
/// failed for an explainable transport reason rather than an auth problem.
const forwardingReasonTypes = {
  'forwarded',
  'trusted_forwarder',
  'mailing_list',
};

/// Whether the receiver overrode the policy for a forwarding reason.
bool hasForwardingReason(DmarcRecord record) {
  for (final reason in record.reasons) {
    if (forwardingReasonTypes.contains(reason.type.trim().toLowerCase())) {
      return true;
    }
  }
  return false;
}

bool _policyPass(Lenient<PolicyResult> result) => switch (result) {
  Known(value: PolicyResult.pass) => true,
  Known(value: PolicyResult.fail) => false,
  // An unknown verdict is not a pass.
  Unknown() => false,
};

/// One short derived label per row, so a reader can sort by cause.
///
/// The receiver's verdict rules: when either mechanism passed, the row is
/// `ok`, whatever this tool computes. Otherwise the first matching arm wins;
/// every label is documented in the README with its usual producer and remedy.
String failureCause({
  required Lenient<PolicyResult> dkimPolicy,
  required Lenient<PolicyResult> spfPolicy,
  required bool forwardingReason,
  required DkimSummary dkim,
  required SpfSummary spf,
}) {
  if (_policyPass(dkimPolicy) || _policyPass(spfPolicy)) {
    return 'ok';
  }
  if (forwardingReason) {
    return 'forwarded';
  }
  return switch ((dkim, spf)) {
    (DkimSummary.passAligned, _) ||
    (_, SpfSummary.passAligned) => 'verdict-differs',
    (DkimSummary.temperror, _) || (_, SpfSummary.temperror) => 'temperror',
    (DkimSummary.passUnaligned, _) => 'dkim-unaligned',
    (_, SpfSummary.passUnaligned) => 'spf-unaligned',
    (DkimSummary.failed, _) => 'dkim-broken',
    (_, SpfSummary.failed) => 'spf-not-listed',
    (DkimSummary.absent, SpfSummary.absent) => 'unsigned',
    (DkimSummary.other, _) || (_, SpfSummary.other) => 'unrecognized',
  };
}
