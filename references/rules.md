# Classification and risk rules

Use path, basename, extension, and parent-directory context together. Suggested categories: University Courses, Lecture Notes, Assignments, Exams, AI/ML, Mathematics, Research, Coding Projects, Internships, Applications, Personal Documents, Downloads, Archives, Unknown. Names are hints, never proof. Retain original hierarchy in the proposed move manifest; do not move automatically.

Candidate classes:

| Signal | Treatment | Risk |
| --- | --- | --- |
| `__pycache__`, `.pyc`, ordinary build output, nonactive logs | Regenerable candidate after project review | Medium |
| Old installers, large archives, downloads | Manual review; check whether the original or backup exists | Medium |
| pip/npm cache | Review cache location and active processes | Medium |
| coursework, research, source, `.git`, config, `.env`, keys, venv, dependencies, datasets, weights | Retain or Unknown | High |
| cloud placeholder, reparse point, inaccessible file | Unknown; no content or saving claim | High |

For duplicate groups, size-match first, hash each regular local file with SHA-256, then group by hash. Keep one verified copy at minimum. If hard-link identity is unavailable, label physical saving as uncertain. Do not aggregate duplicate savings with cache candidates without de-duplicating paths.

Archive structure suggestion: `Archive/University/<course>/<year>/`, `Archive/Projects/<project>/<version>/`, `Archive/Downloads/<year>/`. A proposal is organizational only; archived bytes do not count as freed space.
