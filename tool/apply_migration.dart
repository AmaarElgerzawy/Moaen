// Applies a migration file to the live database.
//
// This exists because the usual routes are all unavailable on this machine:
// `supabase db push` needs `supabase link`, `psql` is not on PATH, and
// `supabase db reset` needs Docker. The `postgres` package is already a
// dev-dependency for the RLS suite, so the driver is here regardless.
//
// The whole file runs in one transaction, so a failure part-way through leaves
// the database exactly as it was. That matters for migrations containing
// several statements: a half-applied one is far worse than a rejected one.
//
//   MOAEN_DB_URL=<uri> dart run tool/apply_migration.dart <file.sql> [more.sql]
import 'dart:io';

import 'package:postgres/postgres.dart';

import 'sql_statement_splitter.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: MOAEN_DB_URL=<uri> dart run tool/apply_migration.dart <file.sql> ...',
    );
    exit(64);
  }

  final String? url = Platform.environment['MOAEN_DB_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('MOAEN_DB_URL is not set.');
    exit(78); // EX_CONFIG
  }

  final Connection conn = await Connection.openFromUrl(url);

  try {
    for (final String path in args) {
      final File file = File(path);
      if (!file.existsSync()) {
        stderr.writeln('no such file: $path');
        exit(66); // EX_NOINPUT
      }

      final String sql = file.readAsStringSync();
      final List<String> statements = splitStatements(sql);
      stdout.writeln('applying $path (${sql.length} bytes, ${statements.length} statements)');

      await conn.execute('begin');
      try {
        // The driver always uses the extended query protocol, which takes one
        // statement per round trip, so a multi-statement file has to be split.
        for (int i = 0; i < statements.length; i++) {
          try {
            await conn.execute(statements[i]);
          } on Object catch (error) {
            // The index identifies which statement, since the file as a whole
            // is no longer a meaningful unit once split.
            stderr.writeln('  statement ${i + 1}/${statements.length} failed: $error');
            stderr.writeln('  ${_preview(statements[i])}');
            rethrow;
          }
        }
        await conn.execute('commit');
        stdout.writeln('  ok');
      } on Object catch (error, stackTrace) {
        await conn.execute('rollback');
        stderr.writeln('  FAILED, rolled back: $error');
        stderr.writeln(stackTrace);
        exit(1);
      }
    }

    // Best effort. The table only exists if migrations were pushed through the
    // Supabase CLI at some point; a project applied entirely by this script will
    // not have it, and that is not a reason to fail.
    stdout.writeln('\nverifying car_inspections:');
    final Result result = await conn.execute('''
      select column_name, data_type, is_nullable
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'car_inspections'
        and column_name in ('reference_no', 'client_notes')
      order by column_name
    ''');
    // Custom enum types come back as UndecodedBytes, so cast to text rather than
    // trusting the driver's decoding. `Result` is a list of rows, so the row
    // count is its length and a scalar is the first column of the first row.
    for (final Object? row in result) {
      stdout.writeln('  $row');
    }
    stdout.writeln('  ${result.length} column(s) found');
  } finally {
    await conn.close();
  }
}

/// The first few lines of a statement, for diagnosing which one failed.
String _preview(String statement, {int lines = 4}) {
  final List<String> all = statement.split('\n');
  final List<String> shown = all.take(lines).toList();
  return shown.join('\n    ') + (all.length > lines ? '\n    ...' : '');
}
