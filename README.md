# dmarc_logger

A simple dmarc report email analyser. Converts incoming emails into a flat CSV file.

# Building

1. Clone repository
2. Install dart
3. `pub get`
4. `dart compile exe bin/dmarc_logger.dart -o dmarc_logger_linux.exe`

# Usage

Copy `dmarc_logger_linux.exe` on your email server and pipe dmarc report email address into it.

For example for postfix you can edit `/etc/aliases` and add:

```
dmarc.report.receive: "|/path/to/dmarc_logger_linux.exe --csv-file /path/to/output-reports.csv"
```

Now incoming emails will be parsed, and appended to the given CSV.
