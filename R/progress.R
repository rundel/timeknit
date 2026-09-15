#' A knitr progress display that reports chunk execution times
#'
#' A drop-in replacement for knitr's default progress display. Each block of the
#' document is printed as `i/total [label]`, exactly as knitr does, and once a
#' code chunk finishes its elapsed wall clock time is appended to that line
#' using an appropriate unit (see [format_duration()]). When the document
#' finishes, a short summary reports the total chunk time and the slowest
#' chunks, and a JSON record of the timings is written for editor integrations
#' (see [timeknit-record]).
#'
#' knitr calls this function itself with the number of blocks and their labels,
#' then calls the returned `update()`, `interrupt()`, and `done()` functions as
#' it works through the document. Register it with knitr through the
#' `knitr.progress.fun` option, most conveniently by calling [use_timeknit()]
#' from your `.Rprofile`.
#'
#' Child documents get their own nested display: their lines are indented, they
#' print no summary, and the parent chunk's line is repeated with its time once
#' the child finishes. When a chunk errors, its time is written to the message
#' stream so it still appears before the error.
#'
#' @section Options:
#' * `timeknit.slowest`: how many of the slowest chunks to list in the summary.
#'   Defaults to 5, and `0` lists none.
#' * `timeknit.summary`: whether to print the summary at all. Defaults to
#'   `TRUE`.
#' * `timeknit.text_blocks`: whether to print lines for text (non-chunk)
#'   blocks as knitr does by default. Defaults to `TRUE`.
#' * `timeknit.record`: whether to write the JSON timing record, or a directory
#'   to write it to. Defaults to `TRUE`; see [timeknit-record].
#' * `knitr.progress.output`: knitr's own option for where progress output is
#'   written. Defaults to the console.
#'
#' @param total The number of blocks (text and code) in the document.
#' @param labels A character vector of chunk labels, with `""` for text blocks.
#' @return A list of functions `update(i)`, `interrupt()`, and `done()`.
#' @examples
#' pb = knit_progress(3, c("", "setup", "model"))
#' pb$update(1)
#' pb$update(2)
#' pb$update(3)
#' pb$done()
#' @export
knit_progress = function(total, labels) {
  con = getOption("knitr.progress.output", "")
  show_text = isTRUE(getOption("timeknit.text_blocks", TRUE))

  depth = length(.state$bars) + 1
  if (depth > 1) .state$bars[[depth - 1]]$nested()

  is_chunk = labels != ""
  tags = pad_right(ifelse(is_chunk, paste0(" [", labels, "]"), ""))
  nums = paste0(
    strrep("  ", depth - 1),
    formatC(seq_len(total), width = nchar(total), format = "d"), "/", total
  )

  target = if (depth == 1) record_target()
  lines = if (!is.null(target)) block_lines(total)
  code = if (!is.null(target)) chunk_code(labels)

  elapsed = rep(NA_real_, total)
  current = NA_integer_
  started = NA_real_
  line_open = FALSE
  line_broken = FALSE
  interrupted = FALSE
  failed = NA_character_

  out = function(..., err = FALSE) {
    cat(..., sep = "", file = if (err && identical(con, "")) stderr() else con, append = TRUE)
  }

  close_line = function(err = FALSE) {
    if (is.na(current)) return(invisible())
    elapsed[current] <<- now() - started
    if (line_open) {
      if (line_broken) out(nums[current], tags[current], err = err)
      if (is_chunk[current]) out("  ", format_duration(elapsed[current]), err = err)
      out("\n", err = err)
    }
    line_open <<- FALSE
    line_broken <<- FALSE
    current <<- NA_integer_
  }

  update = function(i) {
    close_line()
    current <<- i
    started <<- now()
    if (is_chunk[i] || show_text) {
      out(nums[i], tags[i])
      flush_output(con)
      line_open <<- TRUE
    }
  }

  interrupt = function() {
    failed <<- if (!is.na(current) && is_chunk[current]) labels[current] else NA_character_
    close_line(err = TRUE)
    interrupted <<- TRUE
  }

  done = function() {
    close_line()
    .state$bars = .state$bars[seq_len(depth - 1)]
    on.exit(flush_output(con))

    if (!is.null(target)) {
      write_record(
        target, labels[is_chunk], lines[is_chunk, , drop = FALSE], elapsed[is_chunk], code[is_chunk],
        status = if (interrupted) "error" else "complete", failed = failed
      )
    }
    if (depth > 1 || interrupted || !isTRUE(getOption("timeknit.summary", TRUE))) {
      return(invisible())
    }

    times = elapsed[is_chunk]
    names(times) = labels[is_chunk]
    times = times[!is.na(times)]
    if (length(times) == 0) return(invisible())

    out(
      "Total chunk time: ", format_duration(sum(times)),
      " (", length(times), " chunk", if (length(times) != 1) "s", ")\n"
    )

    n_slow = min(getOption("timeknit.slowest", 5), length(times))
    if (n_slow > 0) {
      slow = sort(times, decreasing = TRUE)[seq_len(n_slow)]
      out("Slowest chunk", if (n_slow != 1) "s", ":\n")
      out(paste0("  ", pad_right(paste0("[", names(slow), "]")), "  ", format_duration(slow), "\n"))
    }
    invisible()
  }

  .state$bars[[depth]] = list(nested = function() line_broken <<- line_open)
  list(update = update, interrupt = interrupt, done = done)
}

.state = new.env(parent = emptyenv())
.state$bars = list()

now = function() {
  proc.time()[["elapsed"]]
}

pad_right = function(x) {
  if (length(x) == 0) return(x)
  paste0(x, strrep(" ", max(nchar(x)) - nchar(x)))
}

flush_output = function(con) {
  if (identical(con, "")) utils::flush.console() else if (inherits(con, "connection")) flush(con)
}
