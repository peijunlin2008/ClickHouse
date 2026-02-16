-- Tags: no-parallel
-- Tag no-parallel: Messes with internal cache and global udf factory

-- Tests the preprocessor argument in the text indexes

DROP TABLE IF EXISTS tab;

SELECT 'Basic expressions.';

SELECT '- Test simple preprocessor expression with String.';

CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(val))
)
ENGINE = MergeTree
ORDER BY key;

INSERT INTO tab VALUES (1, 'foo'), (2, 'BAR'), (3, 'Baz');

SELECT count() FROM tab WHERE hasToken(val, 'foo');
SELECT count() FROM tab WHERE hasToken(val, 'FOO');
SELECT count() FROM tab WHERE hasToken(val, 'BAR');
SELECT count() FROM tab WHERE hasToken(val, 'Baz');
SELECT count() FROM tab WHERE hasToken(val, 'bar');
SELECT count() FROM tab WHERE hasToken(val, 'baz');
SELECT count() FROM tab WHERE hasToken(val, 'def');

SELECT count() FROM tab WHERE hasAllTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAllTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAllTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAllTokens(val, 'Baz');

SELECT count() FROM tab WHERE hasAnyTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'Baz');

DROP TABLE tab;

SELECT '- Test simple preprocessor expression with LowCardinality.';

CREATE TABLE tab
(
    key UInt64,
    val LowCardinality(String),
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(val))
)
ENGINE = MergeTree
ORDER BY key;

INSERT INTO tab VALUES (1, 'foo'), (2, 'BAR'), (3, 'Baz');

SELECT count() FROM tab WHERE hasToken(val, 'foo');
SELECT count() FROM tab WHERE hasToken(val, 'FOO');
SELECT count() FROM tab WHERE hasToken(val, 'BAR');
SELECT count() FROM tab WHERE hasToken(val, 'Baz');
SELECT count() FROM tab WHERE hasToken(val, 'bar');
SELECT count() FROM tab WHERE hasToken(val, 'baz');
SELECT count() FROM tab WHERE hasToken(val, 'def');

SELECT count() FROM tab WHERE hasAllTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAllTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAllTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAllTokens(val, 'Baz');

SELECT count() FROM tab WHERE hasAnyTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'Baz');

DROP TABLE tab;

SELECT '- Test simple preprocessor expression with FixedString.';

CREATE TABLE tab
(
    key UInt64,
    val FixedString(3),
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(val))
)
ENGINE = MergeTree
ORDER BY key;

INSERT INTO tab VALUES (1, 'foo'), (2, 'BAR'), (3, 'Baz');

-- hasToken doesn't support FixedString columns
SELECT count() FROM tab WHERE hasToken(val, 'foo'); -- { serverError ILLEGAL_COLUMN }

SELECT count() FROM tab WHERE hasAllTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAllTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAllTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAllTokens(val, 'Baz');

SELECT count() FROM tab WHERE hasAnyTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'Baz');

DROP TABLE tab;

SELECT '- Test preprocessor declaration using the same column more than once.';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = concat(val, val))
)
ENGINE = MergeTree
ORDER BY tuple();

INSERT INTO tab VALUES (1, 'foo'), (2, 'BAR'), (3, 'Baz');

SELECT count() FROM tab WHERE hasToken(val, 'foo');
SELECT count() FROM tab WHERE hasToken(val, 'FOO');
SELECT count() FROM tab WHERE hasToken(val, 'BAR');
SELECT count() FROM tab WHERE hasToken(val, 'Baz');
SELECT count() FROM tab WHERE hasToken(val, 'bar');
SELECT count() FROM tab WHERE hasToken(val, 'baz');
SELECT count() FROM tab WHERE hasToken(val, 'def');

SELECT count() FROM tab WHERE hasAllTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAllTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAllTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAllTokens(val, 'Baz');

SELECT count() FROM tab WHERE hasAnyTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'Baz');

DROP TABLE tab;

SELECT '- Test preprocessor declaration using a UDF.';
DROP FUNCTION IF EXISTS udf;
CREATE FUNCTION udf AS (s) -> concat(val, lower(val));

CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = udf(val))
)
ENGINE = MergeTree
ORDER BY tuple();

INSERT INTO tab VALUES (1, 'foo'), (2, 'BAR'), (3, 'Baz');

SELECT count() FROM tab WHERE hasToken(val, 'foo');
SELECT count() FROM tab WHERE hasToken(val, 'FOO');
SELECT count() FROM tab WHERE hasToken(val, 'BAR');
SELECT count() FROM tab WHERE hasToken(val, 'Baz');
SELECT count() FROM tab WHERE hasToken(val, 'bar');
SELECT count() FROM tab WHERE hasToken(val, 'baz');
SELECT count() FROM tab WHERE hasToken(val, 'def');

SELECT count() FROM tab WHERE hasAllTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAllTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAllTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAllTokens(val, 'Baz');

SELECT count() FROM tab WHERE hasAnyTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'Baz');

DROP TABLE tab;
DROP FUNCTION udf;

SELECT 'Negative tests.';

SELECT '- The preprocessor expression must reference only the index column';
CREATE TABLE tab
(
    key UInt64,
    val String,
    other_str String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(other_str))
)
ENGINE = MergeTree ORDER BY tuple();  -- { serverError UNKNOWN_IDENTIFIER }

CREATE TABLE tab
(
    key UInt64,
    val String,
    other_str String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = concat(val, other_str))
)
ENGINE = MergeTree ORDER BY tuple();   -- { serverError UNKNOWN_IDENTIFIER }

SELECT '- The preprocessor expression must be a function, not an identifier';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = val) -- val is a column
)
ENGINE = MergeTree ORDER BY tuple();   -- { serverError INCORRECT_QUERY }

SELECT '- The preprocessor must be an expression';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = BAD) -- BAD doesn't occur anywhere
)
ENGINE = MergeTree ORDER BY key;   -- { serverError UNKNOWN_IDENTIFIER }

SELECT '- The preprocessor expression must be a known function';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = nonExistingFunction(val))
)
ENGINE = MergeTree ORDER BY tuple();   -- { serverError UNKNOWN_FUNCTION }

SELECT '- The preprocessor must have input and output values of the same type';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = length(val))
)
ENGINE = MergeTree ORDER BY tuple();   -- { serverError INCORRECT_QUERY }

SELECT '- The preprocessor expression must reference the underlying column';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = hostname())
)
ENGINE = MergeTree ORDER BY tuple();   -- { serverError INCORRECT_QUERY }

SELECT '- The preprocessor expression must use only deterministic functions';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = concat(val, toString(rand())))
)
ENGINE = MergeTree ORDER BY tuple();   -- { serverError INCORRECT_QUERY }

SELECT '- The preprocessor expression must not contain arrayJoin';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = arrayJoin(array(val)))
)
ENGINE = MergeTree ORDER BY tuple();   -- { serverError INCORRECT_QUERY }

SELECT 'Advanced expressions and types.';

SELECT '- The preprocessor expression must contain the index definition';
SELECT '-- Single arguments';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(upper(val)) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(upper(val)))
)
ENGINE = MergeTree ORDER BY tuple();

INSERT INTO tab VALUES (1, 'foo'), (2, 'BAR'), (3, 'Baz');

SELECT count() FROM tab WHERE hasToken(val, 'foo');
SELECT count() FROM tab WHERE hasToken(val, 'FOO');
SELECT count() FROM tab WHERE hasToken(val, 'BAR');
SELECT count() FROM tab WHERE hasToken(val, 'Baz');
SELECT count() FROM tab WHERE hasToken(val, 'bar');
SELECT count() FROM tab WHERE hasToken(val, 'baz');
SELECT count() FROM tab WHERE hasToken(val, 'def');

SELECT count() FROM tab WHERE hasAllTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAllTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAllTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAllTokens(val, 'Baz');

SELECT count() FROM tab WHERE hasAnyTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'Baz');

DROP TABLE tab;

SELECT '-- Multiple arguments';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(lower(val)) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = concat(lower(val), lower(val)))
)
ENGINE = MergeTree ORDER BY tuple();

INSERT INTO tab VALUES (1, 'foo'), (2, 'BAR'), (3, 'Baz');

SELECT count() FROM tab WHERE hasToken(val, 'foo');
SELECT count() FROM tab WHERE hasToken(val, 'FOO');
SELECT count() FROM tab WHERE hasToken(val, 'BAR');
SELECT count() FROM tab WHERE hasToken(val, 'Baz');
SELECT count() FROM tab WHERE hasToken(val, 'bar');
SELECT count() FROM tab WHERE hasToken(val, 'baz');
SELECT count() FROM tab WHERE hasToken(val, 'def');

SELECT count() FROM tab WHERE hasAllTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAllTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAllTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAllTokens(val, 'Baz');

SELECT count() FROM tab WHERE hasAnyTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'Baz');

DROP TABLE tab;

SELECT '- Negative tests';
SELECT '-- Index definition may not be a different expression than used in the preprocessor';
CREATE TABLE tab
(
    key UInt64,
    val String,
    INDEX idx(upper(val)) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(val))
)
ENGINE = MergeTree ORDER BY tuple();   -- { serverError UNKNOWN_IDENTIFIER }

SELECT 'Array support';
SELECT '- Test simple preprocessor expression with Array(String).';

CREATE TABLE tab
(
    key UInt64,
    val Array(String),
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(val))
)
ENGINE = MergeTree ORDER BY tuple();

INSERT INTO tab VALUES (1, ['foo']), (2, ['BAR']), (3, ['Baz']);

-- hasToken doesn't support Array(String) columns
SELECT count() FROM tab WHERE hasToken(val, 'foo'); -- { serverError ILLEGAL_TYPE_OF_ARGUMENT }

SELECT count() FROM tab WHERE hasAllTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAllTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAllTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAllTokens(val, 'Baz');

SELECT count() FROM tab WHERE hasAnyTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'Baz');

DROP TABLE tab;

SELECT '- Test simple preprocessor expression with Array(FixedString).';
CREATE TABLE tab
(
    key UInt64,
    val Array(FixedString(3)),
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(val))
)
ENGINE = MergeTree ORDER BY tuple();

INSERT INTO tab VALUES (1, ['foo']), (2, ['BAR']), (3, ['Baz']);

-- hasToken doesn't support Array(FixedString) columns
SELECT count() FROM tab WHERE hasToken(val, 'foo'); -- { serverError ILLEGAL_TYPE_OF_ARGUMENT }

SELECT count() FROM tab WHERE hasAllTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAllTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAllTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAllTokens(val, 'Baz');

SELECT count() FROM tab WHERE hasAnyTokens(val, 'foo');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'FOO');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'BAR');
SELECT count() FROM tab WHERE hasAnyTokens(val, 'Baz');

DROP TABLE tab;

SELECT 'Maps support';
SELECT '- Index definition must be an expression';

CREATE TABLE tab
(
    key UInt64,
    val Map(String, String),
    INDEX idx(mapKeys(val)) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(mapKeys(val)))
)
ENGINE = MergeTree ORDER BY key;

INSERT INTO tab VALUES (1, {'foo': 'dummy'}), (2, {'BAR': 'dummy'}), (3, {'Baz': 'dummy'});

-- Map itself should not be passed as argument
SELECT count() FROM tab WHERE hasAllTokens(val, 'foo');  -- { serverError ILLEGAL_TYPE_OF_ARGUMENT }

SELECT count() FROM tab WHERE hasAllTokens(mapKeys(val), 'foo');
SELECT count() FROM tab WHERE hasAllTokens(mapKeys(val), 'FOO');
SELECT count() FROM tab WHERE hasAllTokens(mapKeys(val), 'BAR');
SELECT count() FROM tab WHERE hasAllTokens(mapKeys(val), 'Baz');

SELECT count() FROM tab WHERE hasAnyTokens(mapKeys(val), 'foo');
SELECT count() FROM tab WHERE hasAnyTokens(mapKeys(val), 'FOO');
SELECT count() FROM tab WHERE hasAnyTokens(mapKeys(val), 'BAR');
SELECT count() FROM tab WHERE hasAnyTokens(mapKeys(val), 'Baz');

DROP TABLE tab;

SELECT '- Negative tests';
SELECT '-- Index on whole map must fail';
CREATE TABLE tab
(
    key UInt64,
    val Map(String, String),
    INDEX idx(val) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(mapKeys(val)))
)
ENGINE = MergeTree ORDER BY key;   -- { serverError BAD_ARGUMENTS }

SELECT '-- The preprocessor expression must contain the index definition';
CREATE TABLE tab
(
    key UInt64,
    val Map(String, String),
    INDEX idx(mapKeys(val)) TYPE text(tokenizer = 'splitByNonAlpha', preprocessor = lower(val))
)
ENGINE = MergeTree ORDER BY key;   -- { serverError ILLEGAL_TYPE_OF_ARGUMENT }

DROP TABLE IF EXISTS tab;
