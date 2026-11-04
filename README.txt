CURRENT Coaching Tracker — database setup

1. This schema is for a NEW, EMPTY Supabase project. Do not run over an existing installation.
2. Open your Supabase project > SQL Editor > New query.
3. Open schema.sql in Notepad or VS Code, select all, copy and paste into Supabase SQL Editor.
4. Press Run ONCE. Wait for 'Success. No rows returned'.
5. The SQL file can then be closed; it does not need to remain running.
6. When the website is deployed and you've registered your coach account, use the commented examples at the end of schema.sql to promote the coach account and link fictional test athletes.

IMPORTANT
- The app website is separate from the database. This SQL file only sets up the database.
- Do not upload database passwords, service_role keys, or athlete data to GitHub.
- This schema has not been tested against a live Supabase project or the existing app build.
- The current app may assume coaches can see all athletes. This schema intentionally requires explicit coach-athlete assignment, so the app code may need adjustment before the coach dashboard works.
- Use only fictional test accounts until authentication, RLS, privacy and safeguarding checks have been completed.
