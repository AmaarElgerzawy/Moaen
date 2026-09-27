import 'package:flutter_test/flutter_test.dart';

import '../../tool/sql_statement_splitter.dart';

/// A wrong split is not a cosmetic bug: the caller sends each returned string to
/// a live database inside a transaction. A syntax error rolls back, but a valid
/// fragment runs as a statement nobody intended.
void main() {
  group('splitStatements', () {
    test('splits on semicolons', () {
      expect(
        splitStatements('select 1; select 2;'),
        <String>['select 1', 'select 2'],
      );
    });

    test('keeps a final statement with no trailing semicolon', () {
      expect(splitStatements('select 1'), <String>['select 1']);
      expect(splitStatements('select 1;\nselect 2'), <String>[
        'select 1',
        'select 2',
      ]);
    });

    test('drops empty statements from trailing semicolons and blank lines', () {
      expect(splitStatements('select 1;;;'), <String>['select 1']);
      expect(splitStatements('select 1;\n\n\n'), <String>['select 1']);
      expect(splitStatements('   \n  \n'), isEmpty);
      expect(splitStatements(''), isEmpty);
    });

    test('ignores a semicolon inside a single-quoted literal', () {
      expect(
        splitStatements("insert into t values ('a;b');"),
        <String>["insert into t values ('a;b')"],
      );
    });

    test('ignores a semicolon inside a double-quoted identifier', () {
      expect(
        splitStatements(r'select "we;ird" from t;'),
        <String>[r'select "we;ird" from t'],
      );
    });

    test('handles a doubled quote as an escape, not the end of the string', () {
      // 'it''s; fine' is one string containing a semicolon. Reading the first
      // quote as the end would split inside the literal.
      expect(
        splitStatements("select 'it''s; fine';"),
        <String>["select 'it''s; fine'"],
      );
    });

    test('ignores a semicolon inside a dollar-quoted body', () {
      const String sql = r'''
        create function f() returns void as $fn$
        begin
          raise notice 'a;b';
        end;
        $fn$ language plpgsql;
        select 1;
      ''';
      expect(splitStatements(sql), hasLength(2));
      expect(splitStatements(sql).first, contains(r'$fn$'));
      expect(splitStatements(sql).first, contains('raise notice'));
      expect(splitStatements(sql).last, 'select 1');
    });

    test('handles a bare \$\$ body', () {
      const String sql = r'select $$a;b$$; select 2;';
      expect(splitStatements(sql), <String>[r'select $$a;b$$', 'select 2']);
    });

    test('ignores a semicolon inside a line comment', () {
      expect(
        splitStatements('-- a; comment\nselect 1;'),
        <String>['select 1'],
      );
    });

    test('ignores a semicolon inside a block comment', () {
      expect(
        splitStatements('/* a; comment */ select 1;'),
        <String>['select 1'],
      );
    });

    test('handles nested block comments', () {
      // Postgres allows these to nest, unlike C.
      expect(
        splitStatements('/* outer /* inner; */ still outer; */ select 1;'),
        <String>['select 1'],
      );
    });

    test('a dollar sign that is not an opener does not swallow the file', () {
      // $1 is a bind parameter, and a bare $ followed by no closing $ is not a
      // tag. Either being mistaken for an opener would consume everything after.
      expect(
        splitStatements(r'select $1 from t; select 2;'),
        <String>[r'select $1 from t', 'select 2'],
      );
      expect(
        splitStatements(r'select a $ b; select 2;'),
        <String>[r'select a $ b', 'select 2'],
      );
    });

    test('preserves newlines so server line numbers stay meaningful', () {
      expect(
        splitStatements('select\n1\nfrom t;'),
        <String>['select\n1\nfrom t'],
      );
    });

    test('a string spanning lines is one statement', () {
      expect(
        splitStatements("insert into t values ('line one\nline two; here');"),
        <String>["insert into t values ('line one\nline two; here')"],
      );
    });
  });
}
