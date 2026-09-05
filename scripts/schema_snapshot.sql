-- A comparable description of everything the migrations create.
--
--   docker exec -i <db> psql -U supabase_admin -d postgres < scripts/schema_snapshot.sql
--
-- Written to prove that compacting 42 migrations into 12 changed nothing: two
-- databases, one built each way, produced byte-identical output. Keep it for
-- the next time the same question comes up.
--
-- It caught its own bug first, which is the reason to run it against a known
-- pair before trusting it. `ORDER BY 1, 2` over a single concatenated column
-- is an error, and psql carried on to the next statement — so CONSTRAINTS,
-- POLICIES and TRIGGERS were silently absent, and a comparison that dropped
-- every RLS policy would have reported no difference at all. Hence
-- ON_ERROR_STOP below: a section that cannot be read must stop the snapshot,
-- not shorten it.
--
-- Ordered and normalised so two databases built different ways produce
-- byte-identical output when they are in fact the same. Anything a migration
-- can create and a compaction can silently drop belongs here.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\pset footer off

SELECT '== TABLES ==';
SELECT c.relname || ' | rls=' || c.relrowsecurity
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r','v')
 ORDER BY 1;

SELECT '== COLUMNS ==';
SELECT table_name || '.' || column_name || ' | ' || data_type
       || ' | null=' || is_nullable
       || ' | default=' || coalesce(column_default, '-')
  FROM information_schema.columns
 WHERE table_schema = 'public'
 ORDER BY table_name, column_name;

SELECT '== CONSTRAINTS ==';
SELECT conrelid::regclass::text || ' | ' || conname || ' | ' || pg_get_constraintdef(oid)
  FROM pg_constraint
 WHERE connamespace = 'public'::regnamespace
 ORDER BY conrelid::regclass::text, conname;

SELECT '== INDEXES ==';
SELECT indexname || ' | ' || indexdef FROM pg_indexes
 WHERE schemaname = 'public' ORDER BY 1;

SELECT '== POLICIES ==';
SELECT tablename || ' | ' || policyname || ' | ' || cmd
       || ' | roles=' || array_to_string(roles, ',')
       || ' | using=' || coalesce(qual, '-')
       || ' | check=' || coalesce(with_check, '-')
  FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename, policyname;

SELECT '== FUNCTIONS ==';
SELECT n.nspname || '.' || p.proname
       || '(' || pg_get_function_identity_arguments(p.oid) || ')'
       || ' | ' || pg_get_functiondef(p.oid)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','app')
 ORDER BY 1;

SELECT '== FUNCTION GRANTS ==';
SELECT n.nspname || '.' || p.proname
       || '(' || pg_get_function_identity_arguments(p.oid) || ')'
       || ' | ' || coalesce(array_to_string(p.proacl, ' '), '(default)')
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','app')
 ORDER BY 1;

SELECT '== TABLE GRANTS ==';
SELECT c.relname || ' | ' || coalesce(array_to_string(c.relacl, ' '), '(default)')
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r','v')
 ORDER BY 1;

SELECT '== TRIGGERS ==';
SELECT c.relname || ' | ' || t.tgname || ' | ' || pg_get_triggerdef(t.oid)
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND NOT t.tgisinternal
 ORDER BY c.relname, t.tgname;

SELECT '== TYPES ==';
SELECT typname || ' | ' || labels FROM (
  SELECT t.typname, string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder) AS labels
    FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
    JOIN pg_namespace n ON n.oid = t.typnamespace
   WHERE n.nspname = 'public' GROUP BY t.typname) x ORDER BY typname;

SELECT '== PUBLICATIONS ==';
SELECT pubname || ' | ' || coalesce(tables, '(none)') FROM (
  SELECT p.pubname, string_agg(pt.tablename, ',' ORDER BY pt.tablename) AS tables
    FROM pg_publication p LEFT JOIN pg_publication_tables pt ON pt.pubname = p.pubname
   GROUP BY p.pubname) x ORDER BY pubname;

SELECT '== CRON ==';
SELECT jobname || ' | ' || schedule || ' | ' || command FROM cron.job ORDER BY 1;
