# timeknit

A drop-in progress display for knitr, and Quarto documents using the knitr engine, that appends the elapsed execution time to each chunk's progress line and summarizes the slowest chunks when the document finishes.

knitr's default progress output looks like:

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

Each chunk's line is printed when the chunk starts and its time is appended when it finishes, so the line without a time is always the chunk currently running.

The timings are also recorded to disk, and the companion [timeknit-vscode](https://github.com/rundel/timeknit-vscode) extension shows them inline next to each chunk in Positron and VS Code. See [Timing records for editors](#timing-records-for-editors) below.

## Installation

The package is not on CRAN. Install it from GitHub with pak:

```r
pak::pak("rundel/timeknit")
```

or with remotes:

```r
remotes::install_github("rundel/timeknit")
```

## How it works

Neither knitr nor Quarto needs to be modified. knitr (>= 1.42) reads the `knitr.progress.fun` option when it starts processing a document and uses that function as its progress display, and `timeknit::use_timeknit()` sets the option to `timeknit::knit_progress`. Because knitr reads the option before the first chunk runs, it has to be set from an R profile rather than from a setup chunk. Quarto's knitr engine runs an ordinary `Rscript` session that honours the usual profiles, so the same setting covers `quarto render`, `rmarkdown::render()`, and `knitr::knit()`.

## Setting up a project

`use_timeknit_project()` configures the current project without touching `~/.Rprofile` or the site-wide profiles:

```r
timeknit::use_timeknit_project()
timeknit::sitrep()
```

It adds a managed block to the project's `.Rprofile`, which covers R sessions started in the project, renders run from those sessions, and Quarto renders of documents in the project root. For a project without an `.Rprofile` the file is created with:

```r
# >>> timeknit >>>
# Managed by timeknit::use_timeknit_project(); remove with timeknit::remove_timeknit_project().
# A project .Rprofile replaces ~/.Rprofile, so load that first.
if (file.exists("~/.Rprofile")) source("~/.Rprofile")
if (requireNamespace("timeknit", quietly = TRUE)) timeknit::use_timeknit()
# <<< timeknit <<<
```

Quarto starts R in each document's own directory, where a root `.Rprofile` is never read. So in a Quarto project (one with `_quarto.yml`) it also writes a `.timeknit.Rprofile` and points `R_PROFILE_USER` at it from `_environment.local`, which does reach documents in subdirectories. `_environment.local` holds an absolute path, so it is added to `.gitignore` in git repositories.

`sitrep()` prints a status report and changes nothing: package versions, whether timeknit is active in the session, which profiles R reads, and which documents are covered when rendered with Quarto. `remove_timeknit_project()` undoes the setup, leaving other content of the touched files alone and deleting files that end up empty.

<details>
<summary>Exactly what is written to each file</summary>

#### `.Rprofile`

If the project already has an `.Rprofile`, this shorter block is appended to it instead, leaving it to the existing file to decide whether `~/.Rprofile` is loaded:

```r
# >>> timeknit >>>
# Managed by timeknit::use_timeknit_project(); remove with timeknit::remove_timeknit_project().
if (requireNamespace("timeknit", quietly = TRUE)) timeknit::use_timeknit()
# <<< timeknit <<<
```

#### `.timeknit.Rprofile` (Quarto projects)

Loads whatever profile R would otherwise have used, then activates timeknit. It can be committed.

```r
# Managed by timeknit::use_timeknit_project(); remove with timeknit::remove_timeknit_project().
# Quarto starts R in each document's directory with R_PROFILE_USER pointing here
# (see _environment.local), so R reads only this file. Load the profile R would
# otherwise have used, then activate timeknit.
local({
  profile = if (file.exists(".Rprofile")) ".Rprofile" else "~/.Rprofile"
  if (file.exists(profile)) source(profile)
})
if (requireNamespace("timeknit", quietly = TRUE)) timeknit::use_timeknit()
```

#### `_environment.local` and `.gitignore` (Quarto projects)

`_environment.local` gets one line with the absolute path to `.timeknit.Rprofile`:

```sh
R_PROFILE_USER='/path/to/project/.timeknit.Rprofile'
```

and `.gitignore` gets `_environment.local` when the project is in a git repository.

#### An existing `R_PROFILE_USER`

If `_environment.local` already sets `R_PROFILE_USER`, the existing line is kept as a comment and restored on removal:

```sh
# timeknit saved R_PROFILE_USER: R_PROFILE_USER='~/custom.Rprofile'
R_PROFILE_USER='/path/to/project/.timeknit.Rprofile'
```

and `.timeknit.Rprofile` loads that profile instead of the default lookup:

```r
local({
  profile = "~/custom.Rprofile"
  if (file.exists(profile)) source(profile)
})
```

If only `_environment` sets `R_PROFILE_USER`, that file is left unchanged (`_environment.local` overrides it) and `.timeknit.Rprofile` loads the profile it names. When a file has several assignments, the last one takes effect, as it would for Quarto. In either case `.timeknit.Rprofile` contains whatever path the previous setting used, which may be machine-specific.

</details>

## Global setup

If you would rather enable it everywhere, add this to `~/.Rprofile` yourself (timeknit never edits that file):

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
| `timeknit.record`       | `TRUE`  | Write the JSON timing record for editors, `FALSE` for none, or a directory to write it elsewhere |

Set them with `options()`, for example next to `use_timeknit()` in a profile.

## Notes

- Times are wall clock durations for everything knitr does for a chunk: running the code, but also hooks, caching, and figure processing. Cached chunks therefore report their (much shorter) load time.
- Units are chosen per value: microseconds below 1 ms, milliseconds below 1 s, seconds below 1 min, then minutes and seconds.
- When a chunk errors, its time is written to the message stream (stderr) so it still appears on the chunk's line, ahead of the error message and knitr's "Quitting from" note. No summary is printed in that case.
- Child documents (`child:` chunks) get a nested, indented display without a summary, and the parent chunk's line is repeated with its total time once the child finishes.
- Under `R CMD check` knitr disables progress output entirely, so nothing is printed there.

## Python chunks and reticulate

Documents that mix R and Python chunks, with reticulate running the Python ones, need no extra setup. knitr reports progress per chunk regardless of the engine, so Python chunks get their times on the progress line, in the summary, and in the timing record, and the editor extension annotates them like R chunks. The example document in `inst/examples/mixed-reticulate.qmd` shows a typical mix.

Two things are worth knowing:

- The first Python chunk also pays for starting the interpreter and importing modules, so it is often the slowest chunk in a document even when it does little work.
- Output that bypasses knitr's capture, such as reticulate's startup messages or a native library writing directly to the terminal, lands in the middle of the running chunk's progress line and pushes its time onto the next line. This is the same text knitr's default display would show after the line.

## Timing records for editors

Whenever a document is knitted from a file, timeknit also writes a JSON record of the chunk timings to `<root>/.quarto/timeknit/<relative path>.json`, where `root` is the Quarto project directory (Quarto sets it even for single-file renders) or, outside Quarto, the document's own directory. Each record holds the document path, the render time and status, the total, and one entry per chunk with its label, source line range, elapsed seconds, and code. The companion [timeknit-vscode](https://github.com/rundel/timeknit-vscode) extension watches these files and shows the times inline in Positron and VS Code. Quarto projects already ignore `.quarto/` in git; add it to `.gitignore` in other projects. Set `options(timeknit.record = FALSE)` to turn recording off, or give a directory to write the records elsewhere. See [`?timeknit-record`](https://rundel.github.io/timeknit/reference/timeknit-record.html) for the schema.
