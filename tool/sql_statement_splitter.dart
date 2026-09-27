/// Splits a SQL file into individual statements.
///
/// The `postgres` driver always uses the extended query protocol, which accepts
/// exactly one statement per round trip, so a multi-statement migration file has
/// to be split before it can be applied. Splitting naively on `;` is wrong in
/// four separate ways, all of which occur in ordinary migration files:
///
///  * a `;` inside a string literal — `check (x in ('a;b'))`
///  * a `;` inside a dollar-quoted function body — `$$ begin ... ; end $$`
///  * a `;` inside a `--` or `/* */` comment
///  * a `;` inside a quoted identifier — `"weird;name"`
///
/// A wrong split here is not a cosmetic failure: it would send a fragment of SQL
/// to a live database. The caller runs everything in a transaction, so an
/// outright syntax error rolls back — but a *valid* fragment executed on its own
/// is a statement nobody intended.
library;

/// Returns the statements in [sql], in order, with comments and whitespace
/// removed and the trailing `;` dropped.
///
/// Empty statements — which a trailing `;` or a blank line produces — are
/// dropped rather than returned, because executing an empty string is an error.
List<String> splitStatements(String sql) {
  final List<String> statements = <String>[];
  final StringBuffer current = StringBuffer();

  int i = 0;
  // Tracks whether the scanner is inside a `--` comment, so that a newline is
  // required to end it. Line comments are not tracked to their end up front
  // because a `;` inside one must be ignored, and finding the newline requires
  // the same scan.
  bool inLineComment = false;
  // Depth of `/* ... */` comments, which nest in Postgres.
  int blockCommentDepth = 0;
  String? stringDelimiter; // `'` or `"` when inside a quoted run
  String? dollarTag; // `$$` or `$tag$` when inside a dollar-quoted body

  void flush() {
    final String statement = current.toString().trim();
    if (statement.isNotEmpty) statements.add(statement);
    current.clear();
  }

  while (i < sql.length) {
    final String char = sql[i];
    final String next = i + 1 < sql.length ? sql[i + 1] : '';

    // --- line comment -------------------------------------------------------
    if (inLineComment) {
      if (char == '\n') {
        inLineComment = false;
        current.write(char); // keep newlines so error line numbers stay sane
      }
      i++;
      continue;
    }

    // --- block comment ------------------------------------------------------
    if (blockCommentDepth > 0) {
      if (char == '/' && next == '*') {
        blockCommentDepth++;
        i += 2;
        continue;
      }
      if (char == '*' && next == '/') {
        blockCommentDepth--;
        i += 2;
        continue;
      }
      // A newline is kept for the same line-number reason as above.
      if (char == '\n') current.write(char);
      i++;
      continue;
    }

    // --- dollar-quoted body -------------------------------------------------
    if (dollarTag != null) {
      if (sql.startsWith(dollarTag, i)) {
        current.write(dollarTag);
        i += dollarTag.length;
        dollarTag = null;
        continue;
      }
      // Every other character in the body is ordinary text and must be kept.
      // Dropping it would silently truncate a function definition to its
      // signature, which is valid SQL and would apply a migration that does not
      // do what the file says.
      current.write(char);
      i++;
      continue;
    }

    // --- single- or double-quoted run --------------------------------------
    if (stringDelimiter != null) {
      current.write(char);
      if (char == stringDelimiter) {
        // A doubled quote is an escaped quote, not the end of the run.
        if (next == stringDelimiter) {
          current.write(next);
          i += 2;
          continue;
        }
        stringDelimiter = null;
      }
      i++;
      continue;
    }

    // --- start of a quoted run ---------------------------------------------
    if (char == "'" || char == '"') {
      stringDelimiter = char;
      current.write(char);
      i++;
      continue;
    }

    // --- comments -----------------------------------------------------------
    if (char == '-' && next == '-') {
      inLineComment = true;
      i += 2;
      continue;
    }
    if (char == '/' && next == '*') {
      blockCommentDepth = 1;
      i += 2;
      continue;
    }

    // --- dollar-quote opener ------------------------------------------------
    // `$tag$` where tag is an identifier, or a bare `$$`.
    if (char == r'$') {
      final String? tag = _readDollarTag(sql, i);
      if (tag != null) {
        dollarTag = tag;
        current.write(tag);
        i += tag.length;
        continue;
      }
    }

    // --- terminator ---------------------------------------------------------
    if (char == ';') {
      flush();
      i++;
      continue;
    }

    current.write(char);
    i++;
  }

  // A file whose last statement has no trailing `;` is still valid SQL.
  flush();
  return statements;
}

/// Reads a dollar-quote tag at [start], returning it including both `$`, or
/// null if this `$` does not open one.
///
/// `$1` is a positional parameter, not an opener, and `$foo` without a closing
/// `$` is neither. Getting this wrong would swallow the rest of the file.
String? _readDollarTag(String sql, int start) {
  if (sql.startsWith(r'$$', start)) return r'$$';

  int i = start + 1;
  if (i >= sql.length) return null;
  // A tag cannot start with a digit, which is what distinguishes `$1` from `$a$`.
  if (!_isTagStart(sql.codeUnitAt(i))) return null;
  i++;
  while (i < sql.length && _isTagPart(sql.codeUnitAt(i))) {
    i++;
  }
  if (i < sql.length && sql[i] == r'$') {
    return sql.substring(start, i + 1);
  }
  return null;
}

bool _isTagStart(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) || // A-Z
    (unit >= 0x61 && unit <= 0x7A) || // a-z
    unit == 0x5F; // _

bool _isTagPart(int unit) => _isTagStart(unit) || (unit >= 0x30 && unit <= 0x39); // 0-9
