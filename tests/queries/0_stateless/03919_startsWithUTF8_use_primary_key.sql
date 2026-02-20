DROP TABLE IF EXISTS test_startsWithUTF8;
CREATE TABLE test_startsWithUTF8 (a String) Engine = MergeTree() ORDER BY a;

INSERT INTO test_startsWithUTF8 (a) values ('a'), ('abcd'), ('bbb'), (''), ('abc');

SELECT count() from test_startsWithUTF8 where startsWithUTF8(a, 'a') settings force_primary_key=1;
SELECT count() from test_startsWithUTF8 where startsWithUTF8(a, '🙂') settings force_primary_key=1; -- { serverError INDEX_NOT_USED }

DROP TABLE test_startsWithUTF8;
