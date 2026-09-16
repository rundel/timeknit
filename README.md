# timeknit

A drop-in progress display for knitr, and therefore for Quarto documents
rendered with the knitr engine, that appends the elapsed execution time to each
chunk's progress line and summarizes the slowest chunks when the document
finishes.

knitr's default progress output looks like this:

```
processing file: Lec07.qmd
1/161
2/161 [setup]
3/161
4/161 [unnamed-chunk-1]
...
```

With timeknit active it becomes:

```
processing file: Lec07.qmd
  1/161
  2/161 [setup]              4.2 ms
  3/161
  4/161 [unnamed-chunk-1]    1.2 s
...
Total chunk time: 12.3 s (86 chunks)
Slowest chunks:
  [unnamed-chunk-42]  4.5 s
  [setup]             2.1 s
  ...
```

Each chunk's line is printed when the chunk starts and its time is appended when
it finishes, so the line without a time is always the chunk currently running.

The timings are also recorded to disk, and the companion
[timeknit-vscode](https://github.com/rundel/timeknit-vscode) extension shows
them inline next to each chunk in Positron and VS Code. See
[Timing records for editors](#timing-records-for-editors) below.

## Installation

```r
pak::local_install("path/to/timeknit")
```

or from the package directory:

```sh
R CMD INSTALL .
```

## How it works

Neither knitr nor Quarto needs to be modified. knitr (>= 1.42) reads the
`knitr.progress.fun` option when it starts processing a document and uses that
function as its progress display, and `timeknit::use_timeknit()` sets the option
to `timeknit::knit_progress`. Because knitr reads the option before the first
chunk runs, it has to be set from an R profile rather than from a setup chunk.
Quarto's knitr engine runs an ordinary `Rscript` session that honours the usual
profiles, so the same setting covers `quarto render`, `rmarkdown::render()`,
and `knitr::knit()`.

## Setting up a project

`use_timeknit_project()` configures the current project without touching
`~/.Rprofile` or the site-wide profiles:

```r
timeknit::use_timeknit_project()
timeknit::sitrep()
```

It adds a managed block to the project's `.Rprofile` (creating the file if
needed) that activates timeknit. That covers R sessions started in the project,
renders run from those sessions, and Quarto renders of documents in the project
root. When the file is created from scratch the block also sources
`~/.Rprofile` first, since a project `.Rprofile` otherwise replaces it.

In a Quarto project (one with `_quarto.yml`) it also writes
`.timeknit.Rprofile` and points `R_PROFILE_USER` at it from
`_environment.local`. Quarto starts R in each document's own directory, where a
root `.Rprofile` is never read, and `_environment.local` is what reaches
documents in subdirectories. The profile loads whatever profile R would
otherwise have used, then activates timeknit. `_environment.local` holds an
absolute path, so it is added to `.gitignore` in git repositories.

Existing `R_PROFILE_USER` assignments in `_environment.local` are saved as
comments and restored on removal. The generated profile sources the previously
configured profile from `_environment.local` or `_environment` before enabling
timeknit. Duplicate assignments are preserved, with the last one taking effect.
The generated `.timeknit.Rprofile` can be committed, but may contain a
machine-specific path if the previous profile setting used one.

`sitrep()` prints a status report and changes nothing: package versions,
whether timeknit is active in the session, which profiles R reads, and which
documents are covered when rendered with Quarto. `remove_timeknit_project()`
undoes the setup, leaving other content of the touched files alone and deleting
files that end up empty.

## Global setup

If you would rather enable it everywhere, add this to `~/.Rprofile` yourself
(timeknit never edits that file):

```r
if (requireNamespace("timeknit", quietly = TRUE)) timeknit::use_timeknit()
```

For a single session, call `timeknit::use_timeknit()` before rendering.

## Options

| Option                  | Default | Effect                                              |
|-------------------------|---------|-----------------------------------------------------|
| `timeknit.slowest`      | `5`     | Number of slowest chunks listed at the end, `0` for none |
| `timeknit.summary`      | `TRUE`  | Print the total and slowest chunks at the end       |
| `timeknit.text_blocks`  | `TRUE`  | Print lines for text blocks between chunks, as knitr does |

Set them with `options()`, for example next to `use_timeknit()` in a profile.

## Notes

- Times are wall clock durations for everything knitr does for a chunk: running
  the code, but also hooks, caching, and figure processing. Cached chunks
  therefore report their (much shorter) load time.
- Units are chosen per value: microseconds below 1 ms, milliseconds below 1 s,
  seconds below 1 min, then minutes and seconds.
- When a chunk errors, its time is written to the message stream (stderr) so it
  still appears on the chunk's line, ahead of the error message and knitr's
  "Quitting from" note. No summary is printed in that case.
- Child documents (`child:` chunks) get a nested, indented display without a
  summary, and the parent chunk's line is repeated with its total time once the
  child finishes.
- Under `R CMD check` knitr disables progress output entirely, so nothing is
  printed there.

## Timing records for editors

Whenever a document is knitted from a file, timeknit also writes a JSON record
of the chunk timings to `<root>/.quarto/timeknit/<relative path>.json`, where
`root` is the Quarto project directory (Quarto sets it even for single-file
renders) or, outside Quarto, the document's own directory. Each record holds the
document path, the render time and status, the total, and one entry per chunk
with its label, source line range, elapsed seconds, and code. The companion
[timeknit-vscode](https://github.com/rundel/timeknit-vscode) extension watches
these files and shows the times inline in Positron and VS Code. Quarto projects
already ignore `.quarto/` in git; add it to `.gitignore` in other projects. Set
`options(timeknit.record = FALSE)` to turn recording off, or give a directory to
write the records elsewhere. See `?timeknit-record` for the schema.
