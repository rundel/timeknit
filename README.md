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

## Installation

```r
pak::local_install("path/to/timeknit")
```

or from the package directory:

```sh
R CMD INSTALL .
```

## Usage

Neither knitr nor Quarto needs to be modified. knitr (>= 1.42) lets the
`knitr.progress.fun` option supply the progress display, and Quarto's knitr
engine runs an ordinary `Rscript` session that reads your `.Rprofile`. So the
only setup is to register timeknit from `~/.Rprofile`, or from a project's
`.Rprofile` next to the documents you render:

```r
if (requireNamespace("timeknit", quietly = TRUE)) timeknit::use_timeknit()
```

After that both `quarto render` and `knitr::knit()` or `rmarkdown::render()`
report chunk times. To use it for a single session instead, call
`timeknit::use_timeknit()` before rendering.

## Options

| Option                  | Default | Effect                                              |
|-------------------------|---------|-----------------------------------------------------|
| `timeknit.slowest`      | `5`     | Number of slowest chunks listed at the end, `0` for none |
| `timeknit.summary`      | `TRUE`  | Print the total and slowest chunks at the end       |
| `timeknit.text_blocks`  | `TRUE`  | Print lines for text blocks between chunks, as knitr does |

Set them with `options()`, for example alongside `use_timeknit()` in `.Rprofile`.

## Notes

- Times are wall clock durations for everything knitr does for a chunk: running
  the code, but also hooks, caching, and figure processing. Cached chunks
  therefore report their (much shorter) load time.
- Units are chosen per value: microseconds below 1 ms, milliseconds below 1 s,
  seconds below 1 min, then minutes and seconds.
- Under `R CMD check` knitr disables progress output entirely, so nothing is
  printed there.
- When a chunk errors, its time is written to the message stream (stderr) so it
  still appears on the chunk's line, ahead of the error message and knitr's
  "Quitting from" note. No summary is printed in that case.
- Child documents (`child:` chunks) get a nested, indented display without a
  summary, and the parent chunk's line is repeated with its total time once the
  child finishes.
- The display is registered with knitr, so it also applies to
  `rmarkdown::render()` and plain `knitr::knit()` calls.
