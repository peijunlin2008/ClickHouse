DROP TABLE IF EXISTS test_startsWithUTF8;
CREATE TABLE test_startsWithUTF8 (a String) Engine = MergeTree() ORDER BY a;

INSERT INTO test_startsWithUTF8 (a) VALUES ('a'), ('abcd'), ('bbb'), (''), ('abc');

SELECT count() from test_startsWithUTF8
WHERE startsWithUTF8(a, 'a')
SETTINGS force_primary_key=1;

SELECT count() from test_startsWithUTF8
WHERE startsWithUTF8(a, '🙂')
SETTINGS force_primary_key=1; -- { serverError INDEX_NOT_USED }

SELECT count() FROM test_startsWithUTF8
WHERE startsWithUTF8('a', a)
SETTINGS force_primary_key=1; -- { serverError INDEX_NOT_USED }

SELECT count() FROM test_startsWithUTF8
WHERE startsWithUTF8('a', a);

SELECT count() FROM test_startsWithUTF8
WHERE startsWithUTF8('a', a)
SETTINGS force_primary_key = 1; -- { serverError INDEX_NOT_USED }

SELECT count() FROM test_startsWithUTF8
WHERE startsWithUTF8(a, '')
SETTINGS force_primary_key = 1; -- { serverError INDEX_NOT_USED }

SELECT count() FROM test_startsWithUTF8
WHERE startsWithUTF8(a, substring(a, 1, 1))
SETTINGS force_primary_key = 1; -- { serverError INDEX_NOT_USED }

SELECT count() FROM test_startsWithUTF8
WHERE startsWithUTF8(a, concat('a', ''))
SETTINGS force_primary_key = 1;

DROP TABLE test_startsWithUTF8;
