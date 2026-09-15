#' Timing records for editor integrations
#'
#' When a document is knitted from a file, [knit_progress()] also writes a JSON
#' record of the chunk timings so that editor extensions can show them inline.
#' The record goes to `<root>/.quarto/timeknit/<relative path>.json`, where
#' `root` is the Quarto project directory (`QUARTO_PROJECT_DIR`, which Quarto
#' sets even for single-file renders) or, outside Quarto, the document's own
#' directory. Quarto projects already ignore `.quarto/` in git.
#'
#' The record is a JSON object with `file` (absolute document path), `root`,
#' `relative`, `time` (UTC), `status` (`"complete"` or `"error"`), `failed`
#' (the label of the chunk that errored, or `null`), `total` (seconds), and
#' `chunks`, an array with one object per executed chunk holding `label`,
#' `start` and `end` (1-based source lines of the chunk fences), `elapsed`
#' (seconds), and `code` (the chunk body without leading `#|` option lines).
#' Child documents are not recorded separately; their time is part of the
#' parent chunk.
#'
#' Control it with the `timeknit.record` option: `TRUE` (the default) writes to
#' the location above, `FALSE` disables recording, and a directory path writes
#' `<relative path>.json` below that directory instead.
#'
#' @name timeknit-record
#' @keywords internal
NULL

record_target = function() {
  opt = getOption("timeknit.record", TRUE)
  if (isFALSE(opt)) return(NULL)
  doc = document_path()
  if (is.null(doc)) return(NULL)

  root = Sys.getenv("QUARTO_PROJECT_DIR")
  root = normalizePath(if (nzchar(root)) root else dirname(doc), mustWork = FALSE)
  relative = relative_path(doc, root)
  dir = if (is.character(opt)) opt else file.path(root, ".quarto", "timeknit")
  list(file = file.path(dir, paste0(relative, ".json")), doc = doc, root = root, relative = relative)
}

document_path = function() {
  dir = Sys.getenv("QUARTO_DOCUMENT_PATH")
  file = Sys.getenv("QUARTO_DOCUMENT_FILE")
  input = if (nzchar(dir) && nzchar(file)) file.path(dir, file) else knitr::current_input(dir = TRUE)
  if (is.null(input) || !nzchar(input)) return(NULL)
  normalizePath(input, mustWork = FALSE)
}

relative_path = function(path, root) {
  prefix = paste0(sub("/+$", "", root), "/")
  if (startsWith(path, prefix)) substring(path, nchar(prefix) + 1) else basename(path)
}

block_lines = function(total) {
  current_lines = tryCatch(utils::getFromNamespace("current_lines", "knitr"), error = function(e) NULL)
  if (is.null(current_lines)) return(matrix(NA_integer_, total, 2))
  t(vapply(seq_len(total), function(i) {
    range = tryCatch(current_lines(i), error = function(e) NA_character_)
    parts = suppressWarnings(as.integer(strsplit(as.character(range), "-", fixed = TRUE)[[1]]))
    if (length(parts) == 0 || anyNA(parts)) c(NA_integer_, NA_integer_) else c(parts[1], parts[length(parts)])
  }, integer(2)))
}

chunk_code = function(labels) {
  vapply(labels, function(label) {
    if (label == "") NA_character_ else paste(knitr::knit_code$get(label), collapse = "\n")
  }, character(1), USE.NAMES = FALSE)
}

write_record = function(target, labels, lines, elapsed, code, status, failed) {
  tryCatch(
    write_record_unsafe(target, labels, lines, elapsed, code, status, failed),
    error = function(e) {
      message("timeknit: could not write the timing record to ", target$file, ": ", conditionMessage(e))
    }
  )
  invisible(target$file)
}

write_record_unsafe = function(target, labels, lines, elapsed, code, status, failed) {
  keep = which(!is.na(elapsed))
  chunks = vapply(keep, function(i) {
    json_object(list(
      label = json_string(labels[i]),
      start = json_number(lines[i, 1]),
      end = json_number(lines[i, 2]),
      elapsed = json_number(elapsed[i]),
      code = json_string(code[i])
    ))
  }, character(1))
  body = json_object(list(
    version = json_number(1),
    timeknit = json_string(as.character(utils::packageVersion("timeknit"))),
    file = json_string(target$doc),
    root = json_string(target$root),
    relative = json_string(target$relative),
    time = json_string(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
    status = json_string(status),
    failed = json_string(failed),
    total = json_number(sum(elapsed[keep])),
    chunks = paste0("[", paste(chunks, collapse = ","), "]")
  ))
  dir.create(dirname(target$file), recursive = TRUE, showWarnings = FALSE)
  writeLines(enc2utf8(body), target$file, useBytes = TRUE)
}

json_object = function(fields) {
  paste0("{", paste0(json_string(names(fields)), ":", unlist(fields), collapse = ","), "}")
}

json_string = function(x) {
  if (length(x) == 0) return("null")
  vapply(x, json_string_one, character(1), USE.NAMES = FALSE)
}

json_string_one = function(x) {
  if (is.na(x)) return("null")
  x = enc2utf8(x)
  x = gsub("\\", "\\\\", x, fixed = TRUE)
  x = gsub("\"", "\\\"", x, fixed = TRUE)
  x = gsub("\n", "\\n", x, fixed = TRUE)
  x = gsub("\r", "\\r", x, fixed = TRUE)
  x = gsub("\t", "\\t", x, fixed = TRUE)
  for (i in c(1:8, 11, 12, 14:31)) {
    x = gsub(intToUtf8(i), paste0("\\u", format(as.hexmode(i), width = 4)), x, fixed = TRUE)
  }
  paste0("\"", x, "\"")
}

json_number = function(x) {
  if (length(x) == 0 || is.na(x) || !is.finite(x)) return("null")
  as.character(x)
}
